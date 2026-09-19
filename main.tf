provider "google" {
  project               = var.project_id
  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project               = var.project_id
  user_project_override = true
  billing_project       = var.project_id
}

# Retrieve the active OAuth access token directly from the configured Google provider
data "google_client_config" "default" {}

# Generate a deployment-scoped 4-char suffix so re-applying after `terraform destroy`
# never collides with Discovery Engine's 2-hour DataStore background deletion queue.
resource "random_id" "collection_suffix" {
  byte_length = 2
}

# Ensure Discovery Engine API is enabled on the target project
resource "google_project_service" "discoveryengine" {
  project                    = var.project_id
  service                    = "discoveryengine.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Core 1st-Party Gemini Enterprise Data Connectors (Google Drive, Calendar, Gmail, Chat)
resource "google_discovery_engine_data_connector" "core_1p_connectors" {
  provider = google-beta
  for_each = var.connectors

  project                 = var.project_id
  location                = var.location
  collection_id           = "${each.value.collection_id}-${random_id.collection_suffix.hex}"
  collection_display_name = each.value.collection_display_name
  data_source             = each.value.data_source
  data_source_version     = each.value.data_source_version
  refresh_interval        = each.value.refresh_interval
  auto_run_disabled       = each.value.auto_run_disabled
  json_params             = each.value.json_params
  connector_modes         = each.value.connector_modes

  entities {
    entity_name = each.value.entity_name
  }

  action_config {
    create_bap_connection = each.value.create_bap_connection
    action_params         = length(each.value.action_params) > 0 ? each.value.action_params : null
  }

  bap_config {
    supported_connector_modes = each.value.supported_bap_modes
    enabled_actions           = length(each.value.enabled_actions) > 0 ? each.value.enabled_actions : null
  }

  depends_on = [
    google_project_service.discoveryengine
  ]
}

# Because `action_config.is_action_configured` is a read-only (`computed`) attribute in the
# hashicorp/google-beta provider schema, this native Terraform step waits for the asynchronous
# BAP connection (`actionState == ACTIVE`) and sends a REST PATCH using the Google provider's
# token to mark `isActionConfigured = true`.
resource "terraform_data" "finalize_connector_actions" {
  for_each = google_discovery_engine_data_connector.core_1p_connectors

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
      ACCESS_TOKEN = nonsensitive(data.google_client_config.default.access_token)
      PROJECT_ID   = var.project_id
      CONNECTOR_URL = (
        "https://discoveryengine.googleapis.com/v1alpha/projects/${var.project_id}/locations/${var.location}/collections/${each.value.collection_id}/dataConnector"
      )
    }
    command = <<-EOT
      set -euo pipefail
      for attempt in $(seq 1 30); do
        resp=$(curl -sS -H "Authorization: Bearer $ACCESS_TOKEN" -H "X-Goog-User-Project: $PROJECT_ID" "$CONNECTOR_URL")
        if echo "$resp" | grep -q '"actionState":[[:space:]]*"ACTIVE"' && echo "$resp" | grep -q '"state":[[:space:]]*"ACTIVE"'; then
          break
        fi
        sleep 10
      done
      curl -sS -X PATCH \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "X-Goog-User-Project: $PROJECT_ID" \
        -H "Content-Type: application/json" \
        "$CONNECTOR_URL?updateMask=actionConfig.isActionConfigured,actionConfig.useStaticSecrets,actionConfig.createBapConnection,actionConfig.actionParams" \
        -d '{"actionConfig":{"isActionConfigured":true,"createBapConnection":true,"useStaticSecrets":true,"actionParams":{"auth_key":"OAuth","auth_type":"OAUTH"}}}' >/dev/null
    EOT
  }

  depends_on = [
    google_discovery_engine_data_connector.core_1p_connectors
  ]
}

