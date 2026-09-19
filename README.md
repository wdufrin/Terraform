# Gemini Enterprise Core 1st-Party Connectors (Terraform)

Pure Terraform configuration for provisioning and activating the four core **1st-party Google Workspace connectors** in **Gemini Enterprise (Google Cloud Discovery Engine)** with **Federated Search (`FEDERATED`)** and **all 68 Assistant Actions (`ACTIONS`)** enabled out-of-the-box:

1. **Google Drive** (`google_drive` — 21 enabled actions)
2. **Google Calendar** (`google_calendar` — 9 enabled actions)
3. **Gmail** (`google_mail` — 25 enabled actions)
4. **Google Chat** (`google_chat` — 13 enabled actions)

---

## Prerequisites

1. **Tools Required**:
   - [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.7.0`
   - [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install)
   - `curl` (standard on Linux/macOS)
2. **GCP Permissions**:
   - `roles/discoveryengine.admin` (Discovery Engine Admin) on the target GCP project
   - `roles/serviceusage.serviceUsageAdmin` (to enable `discoveryengine.googleapis.com`)
   - Your GCP project must belong to a Google Cloud Organization associated with your Google Workspace domain.

---

## Quickstart (Setup & Deployment)

### 1. Configure Your Variables

Copy the example variable file to `terraform.tfvars` (which is gitignored so your project ID is never committed):

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your target GCP Project ID:

```hcl
project_id = "your-gcp-project-id"
location   = "global" # "global", "us", or "eu"
```

### 2. Authenticate with Google Cloud

Authenticate `gcloud` (or Application Default Credentials):

```bash
gcloud auth application-default login
```

*(Alternatively, if using `gcloud auth login`, export `export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)`.)*

### 3. Initialize, Test, and Apply Terraform

```bash
terraform init
terraform test
terraform apply
```

> **Note on Provisioning Time & Collection Naming:**
> - **Asynchronous BAP Provisioning (~2–3 minutes)**: When `create_bap_connection = true` is set, Discovery Engine asynchronously provisions an underlying Application Integration (BAP) connection for each connector (`actionState: CREATING` -> `ACTIVE`). Because `action_config[0].is_action_configured` is marked `computed` (read-only) in the `hashicorp/google-beta` provider schema, the `terraform_data.finalize_connector_actions` block in `main.tf` uses the Google provider's native OAuth token (`data.google_client_config.default.access_token`) to wait for `actionState == "ACTIVE"` and send a REST `PATCH` setting `actionConfig.isActionConfigured = true`.
> - **Automatic Suffix (`random_id.collection_suffix`)**: Discovery Engine keeps deleted DataStores in a background purge queue for ~2 hours after `terraform destroy` (`Error 400: DataStore ... is being deleted`). To allow immediate re-deployment after a `terraform destroy` without collision, `main.tf` appends a deployment-scoped 4-character hex suffix (`ge-1p-google-drive-<hex>`) that stays stable in Terraform state across updates.

---

## Connecting to Your Gemini Enterprise App & End-User Experience

1. **Attach to a Gemini Enterprise App**:
   - In the Google Cloud Console (**Gemini Enterprise -> Apps -> `<your-app>` -> Data stores**), select and attach the 4 created connectors (`Google Drive`, `Google Calendar`, `Gmail`, and `Google Chat`).
2. **Cloud Console (`connector/actions` Tab)**:
   - Because `bap_config.enabled_actions` is explicitly populated with all supported v2 action IDs in `variables.tf`, every action in the Cloud Console (**Gemini Enterprise -> Data stores -> `<connector>` -> Actions**) immediately displays **`Status: Enabled`**.
3. **First-Time User Consent (`Enable actions`)**:
   - When an end-user opens the Gemini Enterprise Web App (`Sources` menu) for the first time, they will see an **Enable** button next to each connector (`Enable actions`).
   - Clicking **Enable** launches a one-time Google Workspace OAuth consent prompt so Gemini Enterprise can execute those admin-enabled actions using the individual user's Workspace permissions.

---

## Provisioned Connectors & All 68 Enabled Actions

| Connector Key | Data Source (`v2`) | Collection ID Pattern | Modes | Enabled Actions (`bap_config.enabled_actions`) |
| :--- | :--- | :--- | :--- | :--- |
| **`google_drive`** | `google_drive` | `ge-1p-google-drive-<hex>` | `FEDERATED`, `ACTIONS` | **21 / 21 Enabled**:<br>`copy_file`, `create_file`, `download_file_content`, `get_file_metadata`, `get_file_permissions`, `googledocs_read_doc`, `googledocs_update_doc`, `googlesheets_get_spreadsheet`, `googlesheets_get_values`, `googlesheets_insert_dimension`, `googlesheets_update_formulas`, `googlesheets_update_spreadsheet`, `googlesheets_update_values`, `googleslides_read_presentation`, `googleslides_update_presentation`, `list_recent_files`, `read_file_content`, `search_files`, `share_file`, `trash_file`, `update_file` |
| **`google_calendar`** | `google_calendar` | `ge-1p-google-cal-<hex>` | `FEDERATED`, `ACTIONS` | **9 / 9 Enabled**:<br>`create_event`, `delete_event`, `get_event`, `list_calendars`, `list_events`, `respond_to_event`, `search_events`, `suggest_time`, `update_event` |
| **`google_mail`** | `google_mail` | `ge-1p-google-mail-v2-<hex>` | `FEDERATED`, `ACTIONS` | **25 / 25 Enabled**:<br>`batch_label_messages`, `batch_label_threads`, `batch_unlabel_messages`, `batch_unlabel_threads`, `create_draft`, `create_filter`, `create_label`, `delete_filter`, `delete_label`, `forward`, `get_message_attachment`, `get_thread`, `label_message`, `label_thread`, `list_drafts`, `list_filters`, `list_labels`, `list_threads`, `reply`, `search_threads`, `send_message`, `unlabel_message`, `unlabel_thread`, `update_draft`, `update_label` |
| **`google_chat`** | `google_chat` | `ge-1p-google-chat-v2-<hex>` | `FEDERATED`, `ACTIONS` | **13 / 13 Enabled**:<br>`add_membership`, `add_reaction`, `create_conversation`, `list_memberships`, `list_messages`, `list_messages_markdown`, `remove_membership`, `remove_reaction`, `search_conversations`, `search_messages`, `send_message`, `send_message_markdown`, `update_membership` |

> **Customizing Enabled Actions:** If your organization wishes to restrict specific write actions (for example, disabling `trash_file` on Google Drive or `delete_event` on Google Calendar), override the `connectors` map in `terraform.tfvars` or `variables.tf` and remove the undesired action IDs from `enabled_actions`.

---

## Teardown / Cleanup

To remove all provisioned connectors and collections from your project:

```bash
terraform destroy
```
