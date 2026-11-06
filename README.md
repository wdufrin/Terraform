# Gemini Enterprise Connectors (Terraform)

Production-ready Terraform configuration for provisioning **1st-party Google Workspace connectors** and **3rd-party enterprise connectors** in **Gemini Enterprise (Google Cloud Discovery Engine)**, supporting **Federated Search (`FEDERATED`)**, **Assistant Actions (`ACTIONS`)**, and **Identity Sync (`DATA_INGESTION`)**.

---

## 1. What Has Been Tested & Verified vs. Untested

Every connector configuration in this repository has been audited against the Discovery Engine C++ backend parameter schemas (`ConnectorSource` registry textprotos) and validated with 38 offline `terraform test` assertions + 16 Python unit tests. In addition, **12 connectors have been deployed and verified end-to-end against a live GCP project**.

### 1.1 Live End-to-End Tested & Verified (12 Connectors)

The following 12 connectors have been deployed end-to-end via `terraform apply`, verified to reach `state = "ACTIVE"` (and `action_state = "ACTIVE"` + `is_action_configured = true` on all 9 action-enabled connectors), verified in the Google Cloud Console UI, and verified to produce **zero drift** (`No changes. Your infrastructure matches the configuration.`) on subsequent `terraform plan` runs:

| Category | Connector Key (`data_source`) | Tested Modes | Live Status | Notes |
| :--- | :--- | :--- | :---: | :--- |
| **1P Workspace** | **`google_drive`** | `["FEDERATED"]` & `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Zero-credential in `FEDERATED` search mode; all 22 V2 Workspace MCP actions verified `Enabled` in UI with a GCP OAuth 2.0 Web Client (`client_id` + `client_secret`). |
| **1P Workspace** | **`google_calendar`** | `["FEDERATED"]` & `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Zero-credential in `FEDERATED` search mode; all 9 V2 Workspace MCP actions verified `Enabled` in UI with a GCP OAuth 2.0 Web Client. |
| **1P Workspace** | **`google_mail`** (Gmail) | `["FEDERATED"]` & `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Zero-credential in `FEDERATED` search mode; all 26 V2 Workspace MCP actions verified `Enabled` in UI with a GCP OAuth 2.0 Web Client. |
| **1P Workspace** | **`google_chat`** | `["FEDERATED"]` & `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Zero-credential in `FEDERATED` search mode; all 13 V2 Workspace MCP actions verified `Enabled` in UI with a GCP OAuth 2.0 Web Client. |
| **1P Workspace** | **`google_sites`** | `["FEDERATED"]` | **Live-Verified (`ACTIVE`)** | Zero-credential `FEDERATED` search mode (`google_sites` does not support `ACTIONS` in GA). |
| **3P Microsoft 365** | **`outlook`** (`v1`) | `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Verified with Entra ID OAuth client + all 8 actions enabled (`root` placeholder entity handled automatically). |
| **3P Microsoft 365** | **`onedrive`** (`v1`) | `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Verified with Entra ID OAuth client + all 3 actions enabled (`upload_file`, `copy_file`, `create_folder`). |
| **3P Microsoft 365** | **`teams`** (`v1`) | `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Verified with Entra ID OAuth client + both actions enabled (`root` placeholder entity handled automatically). |
| **3P Microsoft 365** | **`sharepoint`** (`v2`) | `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Verified with Entra ID OAuth client + all 8 actions enabled (`site` placeholder entity handled automatically). |
| **3P Microsoft 365** | **`azure_active_directory`** (`v1`) | `["DATA_INGESTION"]` | **Live-Verified (`ACTIVE`)** | Verified Microsoft Entra ID user profile identity synchronization (`Userprofiles`). |
| **3P Enterprise** | **`servicenow`** (`v2`) | `["FEDERATED", "ACTIONS"]` | **Live-Verified (`ACTIVE`)** | Verified with ServiceNow OAuth client + service account + all 8 actions enabled (`knowledge_base` placeholder entity handled automatically). |
| **3P BYO MCP** | **`custom_mcp`** (`v1`) | `["FEDERATED"]` | **Live-Verified (`ACTIVE`)** | Verified against Google's Remote BigQuery MCP server (`https://bigquery.googleapis.com/mcp`) with OAuth 2.0. |

---

### 1.2 Schema-Verified Against Production Registry, But Live End-to-End Untested (4 Connectors in `variables.tf`)

The following 4 connectors are pre-configured in [`variables.tf`](variables.tf) (`enabled = false` by default) and have had their exact parameter schemas, `auth_type` selectors, entity names, and action IDs verified against the production Discovery Engine `ConnectorSource` registry definitions, but have **not yet been live-deployed** in our sandbox because we did not have target sandbox credentials for them:

| Connector Key (`data_source`) | Version | Configured Modes | Registry-Verified Configuration Details | Why Live Deployment Was Not Run |
| :--- | :---: | :--- | :--- | :--- |
| **`jira`** | `3` | `["FEDERATED", "ACTIONS"]` | Uses `auth_type = "OAUTH_TWO_LEGGED"` in top-level `params` (to bypass the 3LO `refresh_token` requirement in `authorization_parameters[0]`) and `auth_type = "OAUTH"` in `action_params`. | Requires a live Atlassian Cloud `instance_id`, `instance_uri`, and OAuth `client_id` / `client_secret`. |
| **`confluence`** | `4` | `["FEDERATED", "ACTIONS"]` | Uses `auth_type = "OAUTH_TWO_LEGGED"` in top-level `params` and `auth_key = "OAuth"`, `auth_type = "OAUTH"` in `action_params`. | Requires a live Atlassian Cloud `instance_uri` and OAuth `client_id` / `client_secret`. |
| **`github`** | `2` | `["FEDERATED", "ACTIONS"]` | Uses `auth_key = "OAuth"`, `auth_type = "OAUTH"` in both `params` and `action_params`, plus `owner_login = "<github-org>"` in `action_params`. | Requires a live GitHub Organization OAuth App (`client_id` + `client_secret`). |
| **`slack`** | `3` | `["FEDERATED", "ACTIONS"]` | Uses `unused_auth_param = "unused"` in top-level `params` and Google-managed OAuth (`auth_key = "OAuth"`, `auth_type = "OAUTH"`) in `action_params` (or BYO OAuth with `auth_key = "ByoOAuth"`). | Not yet live-run in sandbox. |

---

### 1.3 Additional GA Federated Connectors Not Yet Pre-Populated in `variables.tf` (Untested Live)

Customers can also add any of the following GA Federated connectors to `var.third_party_connectors` in their `.tfvars` file using the schema requirements below:
- **Standard 3P Federated + Actions (`PUBLIC_GA`):**
  - **`salesforce` (`v3`):** Requires `params = { unused_auth_param = "unused" }` (to prevent a 0-byte `AuthConfig` Secret Manager crash) and `action_params = { auth_key = "OAuth", auth_type = "OAUTH", instance_uri = "...", client_id = "...", client_secret = "..." }`.
  - **`box` (`v2`):** Requires `params = { unused_auth_param = "unused" }` and `action_params = { auth_key = "OAuth", auth_type = "OAUTH" }`.
  - **`hubspot` (`v1`):** Requires `params = { instance_id = "<hubspot-app-id>" }` and `action_params = { auth_key = "OAuth", auth_type = "OAUTH", instance_id = "<hubspot-app-id>", client_id = "...", client_secret = "..." }`.
  - **`zendesk` (`v2`):** Requires `instance_uri`, `client_id`, `client_secret` in both `params` and `action_params` (with `auth_key = "OAuth"`, `auth_type = "OAUTH"`).
  - **`monday` (`v2`):** Requires `host`, `api_version`, `client_id`, `client_secret` in `params`, and `auth_key = "OAuth"`, `auth_type = "OAUTH"` in `action_params`.
- **Partner Remote MCP Connectors (`PUBLIC_GA` — `asana`, `linear`, `notion`, `canva`, `figma`):**
  - Require `params = {}` (empty) and `create_bap_connection = true`.
  - `linear`, `notion`, `canva` (and `asana` BYO) use Dynamic Client Registration: `action_params = { auth_key = "ByoOAuth", auth_type = "OAUTH_DCR" }`.
  - `figma` uses OAuth 2.0: `action_params = { auth_key = "OAuth", auth_type = "OAUTH", client_id = "...", client_secret = "..." }`.
- **Allowlist-Gated Preview (`PRIVATE_GA`) Partner MCP Connectors (`atlassian_rovo_mcp`, `autodesk_mcp`, `github_mcp`, `sourcegraph_mcp`):**
  - Require Google to allowlist the customer's GCP project for `PRIVATE_GA` preview before `:setUpDataConnectorV2` will accept them.
- **Known Limitation — `dropbox` (`v1`):**
  - Both `authorization_parameters[0]` and `action_authorization_parameters[0]` require a 3-legged OAuth (`3LO`) `refresh_token` (`is_required: true`). Cannot be Terraformed headlessly without first generating a `refresh_token` out-of-band.

---

## 2. Prerequisites

1. **Tools Required on the Machine Running Terraform**
   - [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.7.0`
   - `/bin/bash` and `curl` (used by `terraform_data.finalize_connector_actions` to wait for BAP action readiness and set `actionConfig.isActionConfigured = true`)
   - [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install)
2. **GCP Project & APIs**
   - Gemini Enterprise must be initialized in your target GCP project and location (`global`, `us`, or `eu`).
   - Enable `discoveryengine.googleapis.com` and `secretmanager.googleapis.com` (or set `manage_apis = true` in your `.tfvars` to have Terraform enable `discoveryengine.googleapis.com`).
   - **If enabling Actions (`"ACTIONS"`) on 1st-Party Google Workspace connectors:** Also enable the corresponding Google Workspace APIs in the GCP project where your OAuth 2.0 Web Client lives:
     ```bash
     gcloud services enable \
       drive.googleapis.com \
        docs.googleapis.com \
       sheets.googleapis.com \
       slides.googleapis.com \
       calendar-json.googleapis.com \
       gmail.googleapis.com \
       chat.googleapis.com \
       --project="<your-gcp-project-id>"
     ```
3. **IAM Roles for the Identity Running Terraform**
   - `roles/discoveryengine.admin` on the target project
   - `roles/secretmanager.secretAccessor` on any secrets referenced in `var.connector_secret_refs`
   - `roles/serviceusage.serviceUsageAdmin` (only if `manage_apis = true`)
4. **OAuth 2.0 Redirect URIs (Required When Configuring OAuth Clients)**
   When creating an OAuth 2.0 Web Client in **Google Cloud Console (for 1P Workspace Actions)**, **Microsoft Entra ID (Outlook, OneDrive, Teams, SharePoint)**, **ServiceNow**, **Atlassian**, or **GitHub**, add the following **Authorized redirect URIs**:
   - `https://vertexaisearch.cloud.google.com/oauth-redirect`
   - `https://vertexaisearch.cloud.google.com/console/oauth/default_oauth.html`
5. **Remote Terraform State**
   - The `google-beta` provider stores resolved `params` and `action_params` in Terraform state. Always configure an encrypted remote backend (such as a GCS bucket with restricted IAM access) for production deployments.

---

## 3. Step-by-Step Usage Instructions

### Step 1: Clone & Initialize

```bash
git clone <your-repo-url>
cd Terraform

gcloud auth application-default login
terraform init
```

### Step 2: Create Your `.tfvars` Configuration

Start from one of the provided templates:
- **Minimal quickstart:** `cp terraform.tfvars.example terraform.tfvars`
- **Production template (all 1P + M365 + ServiceNow + Jira):** `cp environments/prod.tfvars.example prod.tfvars`
- **Development/Sandbox template (`append_random_suffix = true`, `deletion_policy = "DELETE"`):** `cp environments/dev.tfvars.example dev.tfvars`

*(Note: `*.tfvars` files are gitignored by default so your project IDs, tenant IDs, and secrets are never accidentally committed.)*

### Step 3: Configure 1st-Party Google Workspace Connectors (`var.connectors`)

#### Option A: Federated Search Only (`["FEDERATED"]` — Default, Zero Credentials Required)
By default, `var.connectors` deploys all 5 1st-party Google Workspace connectors (`google_drive`, `google_calendar`, `google_mail`, `google_chat`, `google_sites`) in **zero-credential `FEDERATED` search mode**. No OAuth client or secrets are needed.

#### Option B: Federated Search + Assistant Actions (`["FEDERATED", "ACTIONS"]`)
To enable Assistant Actions on `google_drive`, `google_calendar`, `google_mail`, or `google_chat`:
1. In the Google Cloud Console (**APIs & Services → Credentials**), create an **OAuth 2.0 Client ID** of type **Web application** and add both redirect URIs (`https://vertexaisearch.cloud.google.com/oauth-redirect` and `https://vertexaisearch.cloud.google.com/console/oauth/default_oauth.html`).
2. Store the OAuth `client_id` and `client_secret` in Secret Manager (recommended) and reference them via `connector_secret_refs` (or pass them via the sensitive `connector_secrets` variable), along with `auth_key = "OAuth"` and `auth_type = "OAUTH"`.
3. Configure the V2 Workspace MCP action IDs in `enabled_actions` so they show as **`Enabled`** in the Cloud Console UI **Actions** tab:

```hcl
connectors = {
  google_drive = {
    collection_id           = "ge-1p-google-drive"
    collection_display_name = "Google Drive (1P Federated + Actions)"
    data_source             = "google_drive"
    data_source_version     = 2
    entity_name             = "google_drive"
    refresh_interval        = "0s"
    auto_run_disabled       = true
    connector_modes         = ["FEDERATED", "ACTIONS"]
    create_bap_connection   = true
    supported_bap_modes     = ["ACTIONS"]
    enabled_actions = [
      "copy_file", "create_file", "download_file_content", "get_file_metadata",
      "get_file_permissions", "googledocs_read_doc", "googledocs_update_doc",
      "googlesheets_get_spreadsheet", "googlesheets_get_values", "googlesheets_insert_dimension",
      "googlesheets_update_formulas", "googlesheets_update_spreadsheet", "googlesheets_update_values",
      "googleslides_read_presentation", "googleslides_update_presentation", "list_recent_files",
      "list_shared_drives", "read_file_content", "search_files", "share_file", "trash_file", "update_file"
    ]
  }

  google_calendar = {
    collection_id           = "ge-1p-google-cal"
    collection_display_name = "Google Calendar (1P Federated + Actions)"
    data_source             = "google_calendar"
    data_source_version     = 2
    entity_name             = "google_calendar"
    refresh_interval        = "0s"
    auto_run_disabled       = true
    connector_modes         = ["FEDERATED", "ACTIONS"]
    create_bap_connection   = true
    supported_bap_modes     = ["ACTIONS"]
    enabled_actions = [
      "create_event", "delete_event", "respond_to_event", "update_event",
      "get_event", "list_calendars", "list_events", "search_events", "suggest_time"
    ]
  }

  google_mail = {
    collection_id           = "ge-1p-google-mail-v2"
    collection_display_name = "Gmail (1P Federated + Actions)"
    data_source             = "google_mail"
    data_source_version     = 2
    entity_name             = "google_mail"
    refresh_interval        = "0s"
    auto_run_disabled       = true
    connector_modes         = ["FEDERATED", "ACTIONS"]
    create_bap_connection   = true
    supported_bap_modes     = ["ACTIONS"]
    enabled_actions = [
      "batch_label_messages", "batch_label_threads", "batch_unlabel_messages", "batch_unlabel_threads",
      "create_draft", "create_filter", "create_label", "delete_filter", "delete_label",
      "download_attachment", "forward", "get_message_attachment", "get_thread", "label_message",
      "label_thread", "list_drafts", "list_filters", "list_labels", "list_threads", "read_attachment",
      "reply", "search_threads", "send_message", "unlabel_message", "unlabel_thread", "update_draft", "update_label"
    ]
  }

  google_chat = {
    collection_id           = "ge-1p-google-chat-v2"
    collection_display_name = "Google Chat (1P Federated + Actions)"
    data_source             = "google_chat"
    data_source_version     = 2
    entity_name             = "google_chat"
    refresh_interval        = "0s"
    auto_run_disabled       = true
    connector_modes         = ["FEDERATED", "ACTIONS"]
    create_bap_connection   = true
    supported_bap_modes     = ["ACTIONS"]
    enabled_actions = [
      "add_membership", "add_reaction", "create_conversation", "list_memberships", "list_messages",
      "list_messages_markdown", "remove_membership", "remove_reaction", "search_conversations",
      "search_messages", "send_message", "send_message_markdown", "update_membership"
    ]
  }

  google_sites = {
    collection_id           = "ge-1p-google-sites"
    collection_display_name = "Google Sites (1P Federated Search)"
    data_source             = "google_sites"
    data_source_version     = 1
    entity_name             = "google_sites"
    refresh_interval        = "0s"
    auto_run_disabled       = true
    connector_modes         = ["FEDERATED"]
  }
}

connector_secret_refs = {
  google_drive = {
    action_params = {
      client_id     = "projects/my-project/secrets/workspace-oauth-client-id/versions/latest"
      client_secret = "projects/my-project/secrets/workspace-oauth-client-secret/versions/latest"
    }
  }
  # Repeat for google_calendar, google_mail, google_chat (and pass auth_key = "OAuth", auth_type = "OAUTH" in action_params)
}
```

### Step 4: Configure 3rd-Party Connectors (`var.third_party_connectors`)

All 3rd-party connectors in [`variables.tf`](variables.tf) ship with `enabled = false` and placeholder values (`<your-azure-tenant-id>`, `https://your-company...`).
1. Copy the connector block(s) you want from [`environments/prod.tfvars.example`](environments/prod.tfvars.example) or [`variables.tf`](variables.tf) into your `.tfvars` file.
2. Set `enabled = true` and replace all `<your-...>` / `your-...` placeholders with your real tenant/instance values (plan-time validation automatically rejects any enabled connector that still contains a placeholder).
3. Provide credentials via **`connector_secret_refs`** (Secret Manager version resource names, resolved by Terraform at plan/apply time) or **`connector_secrets`** (raw sensitive values for CI/CD):

```hcl
# Option 1: Secret Manager references (Recommended for Production)
connector_secret_refs = {
  outlook = {
    params = {
      client_secret = "projects/my-project/secrets/outlook-client-secret/versions/latest"
    }
    action_params = {
      client_secret = "projects/my-project/secrets/outlook-client-secret/versions/latest"
    }
  }
}

# Option 2: Direct sensitive values (For local testing or CI environment variables)
# connector_secrets = {
#   outlook = {
#     params        = { client_secret = "..." }
#     action_params = { client_secret = "..." }
#   }
# }
```

> [!IMPORTANT]
> **Why some 3rd-party connectors require credentials in both `params` and `action_params`:**
> Even when deploying a 3rd-party connector in `FEDERATED` mode, Discovery Engine's `:setUpDataConnectorV2` endpoint validates **both** top-level `params` (against the connector's Data Ingestion schema) **and** `action_config.action_params` (against the BAP Federated/Actions schema). The templates in [`variables.tf`](variables.tf) and [`environments/prod.tfvars.example`](environments/prod.tfvars.example) already include the exact dual-parameter structures required for each connector.

### Step 5: Plan, Apply, and Verify Zero Drift

```bash
# 1. Run offline validation and unit tests
terraform validate
terraform test

# 2. Preview the execution plan
terraform plan -var-file=terraform.tfvars

# 3. Provision the connectors and finalize BAP actions
terraform apply -var-file=terraform.tfvars

# 4. Verify zero drift
terraform plan -var-file=terraform.tfvars
```

---

## 4. Operational Notes & Troubleshooting

### 4.1 First-Time Location Tenant Project (`LTP`) Cold-Start (~3–5 Minutes)
When you create the **very first** BAP-backed connector (`ACTIONS` or 3rd-party `FEDERATED`) in a brand-new GCP project/location, Discovery Engine provisions a **Location Tenant Project (`LTP`)** in the background.
- If you create 5–10 BAP connectors simultaneously before that one-time LTP initialization finishes (~3–5 minutes), the earliest connectors may fail asynchronous initialization with `INITIALIZATION_FAILED (code: 13)`.
- **Tip for brand-new projects:** Either deploy a single connector first (to warm up the LTP) and then apply the rest, or set `append_random_suffix = true` during initial bring-up. Once the LTP is ready, all connectors deploy reliably in ~60–90 seconds.

### 4.2 Discovery Engine's 2-Hour DataStore Soft-Delete Queue
When a connector is deleted (or rolls back during initial creation), Discovery Engine places its underlying DataStores into a **~2-hour asynchronous purge queue**. Attempting to recreate a connector with the exact same `collection_id` during that window fails with `400 FAILED_PRECONDITION: DataStore ... is currently being deleted`.
- **In dev/test environments:** Set `append_random_suffix = true` in your `.tfvars`. When you run `terraform destroy` and `terraform apply`, Terraform generates a new 4-character hex suffix (e.g., `-a9f1`), bypassing the 2-hour cooldown immediately.
- **If a single connector fails mid-create:** Either change that connector's `collection_id` (e.g., `ge-3p-servicenow-v2`) or run `terraform taint 'random_id.collection_suffix[0]'` before re-running `terraform apply`.

### 4.3 Backend-Injected Placeholder Entities (`root`, `site`, `knowledge_base`)
When creating `outlook`, `teams`, `sharepoint`, or `servicenow` connectors, the Discovery Engine backend automatically appends an unconfigured placeholder entity (`data_store = ""`):
- `outlook` & `teams`: appends `root`
- `sharepoint`: appends `site`
- `servicenow`: appends `knowledge_base`

Do **not** add `root`, `site`, or `knowledge_base` to your `entities` list in `.tfvars` (doing so causes `:setUpDataConnectorV2` to reject the create request with `400 INVALID_ARGUMENT: Duplicate entity`). This module's `lifecycle.ignore_changes` block automatically ignores backend-appended `entities` and `destination_configs` on subsequent plans so they never trigger `ForceNew` replacement drift.

---

## 5. Connecting to Your Gemini Enterprise App & End-User Experience

1. **Attach to your Gemini Enterprise App:**
   In the Google Cloud Console, navigate to **Gemini Enterprise → Apps → `<your-app>` → Data stores** and attach the created connector data stores.
2. **Verify Enabled Actions:**
   Under **Data stores → `<connector>` → Actions**, all action IDs configured in `enabled_actions` will display as **`Enabled`**.
3. **End-User 3LO Consent at Query Time:**
   In the Gemini Enterprise web app (**Sources** menu), each end user clicks **Enable / Connect** once per connector to complete their per-user OAuth consent flow.

---

## 6. Backup, Disaster Recovery & Importing Existing Connectors

```bash
# 1. Export all existing connectors from a live project to JSON:
python3 scripts/backup_restore_connectors.py \
  --project <project-id> \
  --location global \
  --export-json connectors-backup.json

# 2. Generate a .tfvars file and import script from the backup:
python3 scripts/backup_restore_connectors.py \
  --project <project-id> \
  --location global \
  --input-json connectors-backup.json \
  --export-tfvars restored.tfvars \
  --export-import-script import.sh
```

---

## 7. Teardown

By default, `deletion_policy = "PREVENT"` blocks accidental deletion of connectors. To tear down a disposable environment:

```bash
terraform apply -var-file=terraform.tfvars -var 'deletion_policy=DELETE'
terraform destroy -var-file=terraform.tfvars -var 'deletion_policy=DELETE'
```
