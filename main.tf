provider "google" {
  project               = var.project_id
  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project               = var.project_id
  user_project_override = true
  billing_project       = var.project_id

  # Provider-level default so connectors adopted with `terraform import` record this policy in
  # state at import time (the data connector's Read falls back to the provider default). Without
  # it an imported connector carries "DELETE" in state, and the first forced replacement deletes it.
  deletion_policy = var.deletion_policy
}

# Retrieve the active OAuth access token directly from the configured Google provider
data "google_client_config" "default" {}

# Optional deployment-scoped 4-char suffix so re-applying after `terraform destroy`
# never collides with Discovery Engine's 2-hour DataStore background deletion queue.
# When var.append_random_suffix is false (default), exact deterministic collection IDs are used,
# which is required for state recovery, disaster recovery to specific IDs, and terraform import.
resource "random_id" "collection_suffix" {
  count       = var.append_random_suffix ? 1 : 0
  byte_length = 2
}

# Ensure Discovery Engine API is enabled on the target project (optional if pre-enabled)
resource "google_project_service" "discoveryengine" {
  count                      = var.manage_apis ? 1 : 0
  project                    = var.project_id
  service                    = "discoveryengine.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

locals {
  collection_suffix             = var.append_random_suffix ? "-${random_id.collection_suffix[0].hex}" : ""
  discovery_engine_api_endpoint = var.location == "global" ? "https://discoveryengine.googleapis.com" : "https://${var.location}-discoveryengine.googleapis.com"

  enabled_third_party_connectors = { for k, v in var.third_party_connectors : k => v if v.enabled }

  # Collection IDs before the optional random suffix (the suffix is identical for every connector).
  base_collection_ids = concat(
    [for v in values(var.connectors) : v.collection_id],
    [for v in values(local.enabled_third_party_connectors) : v.collection_id]
  )

  active_connector_keys = setunion(
    toset(keys(var.connectors)),
    toset(keys(local.enabled_third_party_connectors))
  )

  # ---------------------------------------------------------------------------
  # Credentials (1P BAP Actions + 3P): Secret Manager references (resolved by Terraform)
  # and raw sensitive values. The Discovery Engine API only ever receives the resolved values.
  # ---------------------------------------------------------------------------
  connector_secret_ref_entries = {
    for e in flatten([
      for ck, cv in var.connector_secret_refs : concat(
        [for pk, ref in cv.params : { key = "${ck}/params/${pk}", connector = ck, target = "params", param = pk, ref = ref }],
        [for pk, ref in cv.action_params : { key = "${ck}/action_params/${pk}", connector = ck, target = "action_params", param = pk, ref = ref }]
      )
    ]) : e.key => e
  }

  # 1P Workspace action_params (used when 'ACTIONS' is in connector_modes)
  first_party_resolved_secret_action_params = {
    for k in keys(var.connectors) : k => {
      for ek, e in local.connector_secret_ref_entries :
      e.param => data.google_secret_manager_secret_version.connector_secret_refs[ek].secret_data
      if e.connector == k && e.target == "action_params"
    }
  }

  first_party_raw_secrets = {
    for k in keys(var.connectors) : k => lookup(var.connector_secrets, k, { params = {}, action_params = {} })
  }

  first_party_raw_secret_counts = {
    for k, s in local.first_party_raw_secrets : k => {
      params        = nonsensitive(length(s.params))
      action_params = nonsensitive(length(s.action_params))
    }
  }

  first_party_action_param_keys = {
    for k, v in var.connectors : k => setunion(
      toset(keys(v.action_params)),
      toset(keys(try(var.connector_secret_refs[k].action_params, {}))),
      toset(nonsensitive(keys(local.first_party_raw_secrets[k].action_params)))
    )
  }

  first_party_action_params = {
    for k, v in var.connectors : k => (
      local.first_party_raw_secret_counts[k].action_params > 0
      ? merge({ auth_key = "OAuth", auth_type = "OAUTH" }, v.action_params, local.first_party_resolved_secret_action_params[k], local.first_party_raw_secrets[k].action_params)
      : merge({ auth_key = "OAuth", auth_type = "OAUTH" }, v.action_params, local.first_party_resolved_secret_action_params[k])
    )
  }

  # 3P params and action_params
  resolved_secret_params = {
    for k in keys(local.enabled_third_party_connectors) : k => {
      for ek, e in local.connector_secret_ref_entries :
      e.param => data.google_secret_manager_secret_version.connector_secret_refs[ek].secret_data
      if e.connector == k && e.target == "params"
    }
  }

  resolved_secret_action_params = {
    for k in keys(local.enabled_third_party_connectors) : k => {
      for ek, e in local.connector_secret_ref_entries :
      e.param => data.google_secret_manager_secret_version.connector_secret_refs[ek].secret_data
      if e.connector == k && e.target == "action_params"
    }
  }

  raw_connector_secrets = {
    for k in keys(local.enabled_third_party_connectors) : k => lookup(var.connector_secrets, k, { params = {}, action_params = {} })
  }

  # Key counts are not secret; keeping them non-sensitive lets them drive block/argument selection
  # without masking the non-secret params of every connector in plan output.
  raw_secret_counts = {
    for k, s in local.raw_connector_secrets : k => {
      params        = nonsensitive(length(s.params))
      action_params = nonsensitive(length(s.action_params))
    }
  }

  secret_ref_counts = {
    for k in keys(local.enabled_third_party_connectors) : k => {
      params        = length(try(var.connector_secret_refs[k].params, {}))
      action_params = length(try(var.connector_secret_refs[k].action_params, {}))
    }
  }

  third_party_params = {
    for k, v in local.enabled_third_party_connectors : k => (
      local.raw_secret_counts[k].params > 0
      ? merge(v.params, local.resolved_secret_params[k], local.raw_connector_secrets[k].params)
      : merge(v.params, local.resolved_secret_params[k])
    )
  }

  third_party_action_params = {
    for k, v in local.enabled_third_party_connectors : k => (
      local.raw_secret_counts[k].action_params > 0
      ? merge(v.action_params, local.resolved_secret_action_params[k], local.raw_connector_secrets[k].action_params)
      : merge(v.action_params, local.resolved_secret_action_params[k])
    )
  }

  third_party_has_params = {
    for k, v in local.enabled_third_party_connectors : k => (
      length(v.params) > 0 || local.secret_ref_counts[k].params > 0 || local.raw_secret_counts[k].params > 0
    )
  }

  third_party_has_action_params = {
    for k, v in local.enabled_third_party_connectors : k => (
      length(v.action_params) > 0 || local.secret_ref_counts[k].action_params > 0 || local.raw_secret_counts[k].action_params > 0
    )
  }
}

# Cross-variable input checks (Terraform < 1.9 cannot reference other variables inside a
# variable validation block). These fail `terraform plan` before anything is created.
resource "terraform_data" "input_validation" {
  lifecycle {
    precondition {
      condition     = length(setintersection(toset(keys(var.connectors)), toset(keys(local.enabled_third_party_connectors)))) == 0
      error_message = "A connector key is used in both var.connectors and var.third_party_connectors. Keys must be unique across both maps."
    }

    precondition {
      condition     = length(distinct(local.base_collection_ids)) == length(local.base_collection_ids)
      error_message = "Two connectors use the same collection_id. collection_id must be unique across var.connectors and enabled var.third_party_connectors."
    }

    precondition {
      condition     = alltrue([for id in local.base_collection_ids : length(id) + (var.append_random_suffix ? 5 : 0) <= 63])
      error_message = "collection_id plus the optional '-xxxx' random suffix must be at most 63 characters (at most 58 when append_random_suffix = true)."
    }

    precondition {
      condition     = alltrue([for k in keys(var.connector_secret_refs) : contains(local.active_connector_keys, k)])
      error_message = "Every connector_secret_refs key must match an entry in var.connectors or an enabled entry in var.third_party_connectors."
    }

    precondition {
      condition     = alltrue([for k in nonsensitive(keys(var.connector_secrets)) : contains(local.active_connector_keys, k)])
      error_message = "Every connector_secrets key must match an entry in var.connectors or an enabled entry in var.third_party_connectors."
    }

    precondition {
      condition = alltrue([
        for k, v in var.connectors : !contains(v.connector_modes, "ACTIONS") || (
          contains(local.first_party_action_param_keys[k], "client_id") &&
          contains(local.first_party_action_param_keys[k], "client_secret")
        )
      ])
      error_message = "A 1st-party connector with 'ACTIONS' in connector_modes requires 'client_id' and 'client_secret' in action_params (supply them via connector_secret_refs or connector_secrets). Without them, Discovery Engine builds an empty AuthConfig, fails with HTTP 500 in Secret Manager, and soft-deletes the DataStore for 2 hours. Remove 'ACTIONS' from connector_modes for zero-credential federated search."
    }
  }
}

# Resolve Secret Manager references for connector credentials (one read per referenced param).
data "google_secret_manager_secret_version" "connector_secret_refs" {
  for_each = local.connector_secret_ref_entries

  secret  = regex("^(projects/[^/]+/secrets/[^/]+)/versions/[^/]+$", each.value.ref)[0]
  version = regex("/versions/([^/]+)$", each.value.ref)[0]
}

# Core 1st-Party Gemini Enterprise Data Connectors (Google Drive, Calendar, Gmail, Chat)
resource "google_discovery_engine_data_connector" "core_1p_connectors" {
  provider = google-beta
  for_each = var.connectors

  project                 = var.project_id
  location                = var.location
  collection_id           = "${each.value.collection_id}${local.collection_suffix}"
  collection_display_name = each.value.collection_display_name
  data_source             = each.value.data_source
  data_source_version     = each.value.data_source_version
  refresh_interval        = each.value.refresh_interval
  auto_run_disabled       = each.value.auto_run_disabled
  json_params             = each.value.json_params
  connector_modes         = each.value.connector_modes
  kms_key_name            = var.kms_key_name
  deletion_policy         = var.deletion_policy

  entities {
    entity_name = each.value.entity_name
  }

  # Action blocks are only sent for connectors in ACTIONS mode, so search-only connectors work.
  dynamic "action_config" {
    for_each = contains(each.value.connector_modes, "ACTIONS") ? [true] : []
    content {
      create_bap_connection = each.value.create_bap_connection
      action_params         = local.first_party_action_params[each.key]
    }
  }

  dynamic "bap_config" {
    for_each = contains(each.value.connector_modes, "ACTIONS") ? [true] : []
    content {
      supported_connector_modes = each.value.supported_bap_modes
      enabled_actions           = length(each.value.enabled_actions) > 0 ? each.value.enabled_actions : null
    }
  }

  lifecycle {
    ignore_changes = [
      # The provider never reads collection_display_name back from the API, yet marks it ForceNew.
      # Without this, every connector adopted via `terraform import` is planned for destroy-and-recreate.
      collection_display_name,
      # Verified in a live smoke test (2026-11-05): the external API gateway (ESF) strips dataSourceVersion
      # on non-TRUSTED_TESTER customer projects so it reads back as 0. The version is still sent at creation.
      data_source_version,
      # The API strips sensitive OAuth credentials (client_id, client_secret) from action_config.action_params
      # after storing them in Secret Manager, and injects default sync/window parameters on read-back.
      params,
      json_params,
      action_config[0].action_params,
      action_config[0].create_bap_connection,
      auto_run_disabled,
      sync_mode,
    ]
  }

  depends_on = [
    google_project_service.discoveryengine
  ]
}

# 3rd-Party Enterprise Data Connectors (Jira, Confluence, GitHub, Slack, ServiceNow, SharePoint, Microsoft 365, ...)
resource "google_discovery_engine_data_connector" "third_party_connectors" {
  provider = google-beta
  for_each = local.enabled_third_party_connectors

  project                 = var.project_id
  location                = var.location
  collection_id           = "${each.value.collection_id}${local.collection_suffix}"
  collection_display_name = each.value.collection_display_name
  data_source             = each.value.data_source
  data_source_version     = each.value.data_source_version
  refresh_interval        = each.value.refresh_interval
  auto_run_disabled       = each.value.auto_run_disabled
  connector_modes         = each.value.connector_modes
  kms_key_name            = var.kms_key_name
  deletion_policy         = var.deletion_policy

  # The provider requires exactly one of params / json_params.
  params      = local.third_party_has_params[each.key] ? local.third_party_params[each.key] : null
  json_params = local.third_party_has_params[each.key] ? null : coalesce(each.value.json_params, "{}")

  dynamic "entities" {
    for_each = each.value.entities
    content {
      entity_name = entities.value
      params      = lookup(each.value.entity_params, entities.value, null)
    }
  }

  dynamic "destination_configs" {
    for_each = each.value.destination_configs
    content {
      key    = destination_configs.value.key
      params = destination_configs.value.params
      dynamic "destinations" {
        for_each = destination_configs.value.destinations
        content {
          host = destinations.value.host
          port = destinations.value.port
        }
      }
    }
  }

  dynamic "action_config" {
    for_each = each.value.create_bap_connection || local.third_party_has_action_params[each.key] ? [true] : []
    content {
      create_bap_connection = each.value.create_bap_connection
      action_params         = local.third_party_has_action_params[each.key] ? local.third_party_action_params[each.key] : null
    }
  }

  dynamic "bap_config" {
    for_each = length(each.value.supported_bap_modes) > 0 || length(each.value.enabled_actions) > 0 ? [true] : []
    content {
      supported_connector_modes = length(each.value.supported_bap_modes) > 0 ? each.value.supported_bap_modes : null
      enabled_actions           = length(each.value.enabled_actions) > 0 ? each.value.enabled_actions : null
    }
  }

  lifecycle {
    # Verified in live validation (2026-11-05):
    # 1. collection_display_name is never read back by the provider (ForceNew).
    # 2. data_source_version is stripped by the external API gateway (ESF) on customer projects.
    # 3. The backend strips sensitive credentials from params / action_config.action_params after storing
    #    them in Secret Manager, injects default parameters (sync_window_days, auth_type, etc.), synthesizes
    #    default destination_configs from templates, and appends placeholder entities (e.g. root for outlook/teams,
    #    site for sharepoint, knowledge_base for servicenow). Because removing an entity in provider v8.3.0 has
    #    ForceNew = true, ignoring these attributes prevents destructive replacement on subsequent applies.
    ignore_changes = [
      collection_display_name,
      data_source_version,
      params,
      json_params,
      action_config,
      auto_run_disabled,
      sync_mode,
      entities,
      destination_configs,
    ]
  }

  depends_on = [
    google_project_service.discoveryengine
  ]
}

locals {
  all_connectors = merge(
    google_discovery_engine_data_connector.core_1p_connectors,
    google_discovery_engine_data_connector.third_party_connectors
  )

  # Only connectors that are actually in ACTIONS mode get their BAP connection finalized. A
  # FEDERATED-only connector (e.g. custom_mcp) may set create_bap_connection = true but never reports
  # actionState = ACTIVE, so polling it would always time out.
  actionable_connector_keys = toset(concat(
    [for k, v in var.connectors : k if v.create_bap_connection && contains(v.connector_modes, "ACTIONS")],
    [for k, v in local.enabled_third_party_connectors : k if v.create_bap_connection && contains(v.connector_modes, "ACTIONS")]
  ))

  # Non-sensitive projection of each actionable connector: credentials in params / action_params can
  # be sensitive, and sensitive values cannot drive for_each.
  actionable_connectors = {
    for k in local.actionable_connector_keys : k => {
      name                = local.all_connectors[k].name
      collection_id       = local.all_connectors[k].collection_id
      data_source         = local.all_connectors[k].data_source
      data_source_version = contains(keys(var.connectors), k) ? var.connectors[k].data_source_version : local.enabled_third_party_connectors[k].data_source_version
      bap_config          = local.all_connectors[k].bap_config
    }
  }
}

# Because `action_config.is_action_configured` is a read-only (`computed`) attribute in the
# hashicorp/google-beta provider schema, this native Terraform step waits for the asynchronous
# BAP connection (`actionState == ACTIVE`) and sends a REST PATCH using the Google provider's
# token to mark `isActionConfigured = true`.
# Requires /bin/bash and curl on the machine running Terraform.
resource "terraform_data" "finalize_connector_actions" {
  for_each = local.actionable_connectors

  triggers_replace = [
    each.value.name,
    each.value.collection_id,
    each.value.data_source,
    each.value.data_source_version,
    jsonencode(each.value.bap_config)
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      # nonsensitive(): Terraform suppresses ALL provisioner output when any environment value is
      # sensitive, which would hide the error messages below. The script never prints the token.
      ACCESS_TOKEN    = nonsensitive(data.google_client_config.default.access_token)
      PROJECT_ID      = var.project_id
      CONNECTOR_KEY   = each.key
      TIMEOUT_SECONDS = tostring(var.action_activation_timeout_seconds)
      CONNECTOR_URL = (
        "${local.discovery_engine_api_endpoint}/v1alpha/projects/${var.project_id}/locations/${var.location}/collections/${each.value.collection_id}/dataConnector"
      )
    }
    command = <<-EOT
      set -euo pipefail
      attempts=$(( TIMEOUT_SECONDS / 10 ))
      if [ "$attempts" -lt 1 ]; then attempts=1; fi
      body=""
      for attempt in $(seq 1 "$attempts"); do
        raw=$(curl -sS -w '\n%%{http_code}' \
          -H "Authorization: Bearer $ACCESS_TOKEN" \
          -H "X-Goog-User-Project: $PROJECT_ID" \
          "$CONNECTOR_URL") || raw=$(printf '\n000')
        code=$(printf '%s' "$raw" | tail -n 1)
        body=$(printf '%s' "$raw" | sed '$d')
        case "$code" in
          200) ;;
          401|403)
            echo "ERROR: HTTP $code reading connector '$CONNECTOR_KEY'. The access token captured at plan time may have expired (saved plans older than ~1h), or the caller lacks discoveryengine.dataConnectors.get. Re-run 'terraform apply' without a saved plan. Response: $body" >&2
            exit 1
            ;;
          404)
            echo "ERROR: Connector '$CONNECTOR_KEY' was not found at $CONNECTOR_URL. Response: $body" >&2
            exit 1
            ;;
          *)
            echo "WARN: HTTP $code reading connector '$CONNECTOR_KEY' (attempt $attempt/$attempts); retrying." >&2
            sleep 10
            continue
            ;;
        esac
        if grep -qE '"(actionState|state)":[[:space:]]*"(FAILED|INITIALIZATION_FAILED)"' <<<"$body"; then
          echo "ERROR: Connector '$CONNECTOR_KEY' reported FAILED or INITIALIZATION_FAILED. Response: $body" >&2
          exit 1
        fi
        if grep -qE '"actionState":[[:space:]]*"ACTIVE"' <<<"$body" && grep -qE '"state":[[:space:]]*"ACTIVE"' <<<"$body"; then
          curl -sS -f -X PATCH \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "X-Goog-User-Project: $PROJECT_ID" \
            -H "Content-Type: application/json" \
            "$CONNECTOR_URL?updateMask=actionConfig.isActionConfigured" \
            -d '{"actionConfig":{"isActionConfigured":true}}' >/dev/null
          exit 0
        fi
        sleep 10
      done
      echo "ERROR: Connector '$CONNECTOR_KEY' did not reach state=ACTIVE and actionState=ACTIVE within $TIMEOUT_SECONDS seconds. Last response: $body" >&2
      exit 1
    EOT
  }

  depends_on = [
    google_discovery_engine_data_connector.core_1p_connectors,
    google_discovery_engine_data_connector.third_party_connectors
  ]
}
