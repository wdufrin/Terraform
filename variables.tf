variable "project_id" {
  description = "The GCP Project ID where Gemini Enterprise (Discovery Engine) connectors will be created."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 lowercase letters, digits, or hyphens, starting with a letter)."
  }
}

variable "location" {
  description = "The Discovery Engine location where collections and connectors reside (global, us, or eu)."
  type        = string
  default     = "global"

  validation {
    condition     = contains(["global", "us", "eu"], var.location)
    error_message = "location must be one of: 'global', 'us', 'eu'."
  }
}

variable "manage_apis" {
  description = "Whether to manage API enablement via Terraform. Set to false if APIs are pre-enabled."
  type        = bool
  default     = false
}

variable "append_random_suffix" {
  description = "Whether to append a random hex suffix to collection IDs. Set to true for ephemeral test environments to avoid Discovery Engine's 2-hour DataStore soft-deletion queue on rapid re-applies. Set to false for deterministic production naming, state recovery, and importing existing connectors."
  type        = bool
  default     = false
}

variable "connectors" {
  description = <<-EOT
    Configuration map for the core 1st-party Gemini Enterprise (Google Workspace) connectors.
    Defaults deploy all 4 Workspace connectors (Drive, Calendar, Gmail, Chat) in zero-credential
    FEDERATED search mode. To also enable BAP Actions ("ACTIONS" in connector_modes), set
    create_bap_connection = true, supported_bap_modes = ["ACTIONS"], enabled_actions, and supply a
    Google OAuth 2.0 Web client's client_id and client_secret via connector_secret_refs (or
    connector_secrets) under action_params.
  EOT
  type = map(object({
    collection_id           = string
    collection_display_name = string
    data_source             = string
    data_source_version     = optional(number, 2)
    entity_name             = string
    refresh_interval        = optional(string, "0s")
    auto_run_disabled       = optional(bool, false)
    json_params             = optional(string, "{}")
    connector_modes         = list(string)
    create_bap_connection   = optional(bool, false)
    action_params           = optional(map(string), {})
    supported_bap_modes     = optional(list(string), [])
    enabled_actions         = optional(list(string), [])
  }))

  # Live-verified against the Discovery Engine API (2026-11-05):
  # - Public REST calls strip `data_source_version` at the API gateway (ESF), routing Workspace
  #   connectors through the V1 enterprise flow unless the project has internal V2 promotion enabled.
  # - In the standard V1 flow, FEDERATED search requires zero credentials and reaches ACTIVE in ~1s.
  # - Enabling "ACTIONS" provisions a BAP/MCP connection and requires `client_id` + `client_secret` in
  #   action_params (supplied via connector_secret_refs / connector_secrets) plus the V2 Workspace MCP
  #   action IDs (checked by the Cloud Console UI Actions tab):
  #     google_drive (22 V2 actions):
  #       ["copy_file", "create_file", "download_file_content", "get_file_metadata",
  #        "get_file_permissions", "googledocs_read_doc", "googledocs_update_doc",
  #        "googlesheets_get_spreadsheet", "googlesheets_get_values", "googlesheets_insert_dimension",
  #        "googlesheets_update_formulas", "googlesheets_update_spreadsheet", "googlesheets_update_values",
  #        "googleslides_read_presentation", "googleslides_update_presentation", "list_recent_files",
  #        "list_shared_drives", "read_file_content", "search_files", "share_file", "trash_file", "update_file"]
  #     google_calendar (9 V2 actions):
  #       ["create_event", "delete_event", "respond_to_event", "update_event", "get_event",
  #        "list_calendars", "list_events", "search_events", "suggest_time"]
  #     google_mail (26 V2 actions):
  #       ["batch_label_messages", "batch_label_threads", "batch_unlabel_messages", "batch_unlabel_threads",
  #        "create_draft", "create_filter", "create_label", "delete_filter", "delete_label",
  #        "download_attachment", "forward", "get_message_attachment", "get_thread", "label_message",
  #        "label_thread", "list_drafts", "list_filters", "list_labels", "list_threads", "read_attachment",
  #        "reply", "search_threads", "send_message", "unlabel_message", "unlabel_thread", "update_draft",
  #        "update_label"]
  #     google_chat (13 V2 actions):
  #       ["add_membership", "add_reaction", "create_conversation", "list_memberships", "list_messages",
  #        "list_messages_markdown", "remove_membership", "remove_reaction", "search_conversations",
  #        "search_messages", "send_message", "send_message_markdown", "update_membership"]
  default = {
    google_drive = {
      collection_id           = "ge-1p-google-drive"
      collection_display_name = "Google Drive (1P Federated Search)"
      data_source             = "google_drive"
      data_source_version     = 2
      entity_name             = "google_drive"
      refresh_interval        = "0s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED"]
    }

    google_calendar = {
      collection_id           = "ge-1p-google-cal"
      collection_display_name = "Google Calendar (1P Federated Search)"
      data_source             = "google_calendar"
      data_source_version     = 2
      entity_name             = "google_calendar"
      refresh_interval        = "0s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED"]
    }

    google_mail = {
      collection_id           = "ge-1p-google-mail-v2"
      collection_display_name = "Gmail (1P Federated Search)"
      data_source             = "google_mail"
      data_source_version     = 2
      entity_name             = "google_mail"
      refresh_interval        = "0s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED"]
    }

    google_chat = {
      collection_id           = "ge-1p-google-chat-v2"
      collection_display_name = "Google Chat (1P Federated Search)"
      data_source             = "google_chat"
      data_source_version     = 2
      entity_name             = "google_chat"
      refresh_interval        = "0s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED"]
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

  validation {
    condition = alltrue([
      for k, v in var.connectors : contains(["google_drive", "google_calendar", "google_mail", "google_chat", "google_sites"], v.data_source) && (
        v.data_source != "google_sites" || !contains(v.connector_modes, "ACTIONS")
      )
    ])
    error_message = "All 1P connectors must use a supported core 1st-party data_source (google_drive, google_calendar, google_mail, google_chat, or google_sites), and google_sites only supports FEDERATED search (not ACTIONS)."
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : length(v.connector_modes) > 0 && alltrue([
        for m in v.connector_modes : contains(["FEDERATED", "ACTIONS", "DATA_INGESTION", "EUA", "FEDERATED_AND_EUA"], m)
      ])
    ])
    error_message = "connector_modes must be a non-empty list drawn from: FEDERATED, ACTIONS, DATA_INGESTION, EUA, FEDERATED_AND_EUA."
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : !contains(v.connector_modes, "ACTIONS") || (
        v.create_bap_connection && contains(v.supported_bap_modes, "ACTIONS") && length(v.enabled_actions) > 0
      )
    ])
    error_message = "A 1P connector with 'ACTIONS' in connector_modes needs create_bap_connection = true, 'ACTIONS' in supported_bap_modes, and a non-empty enabled_actions list. Remove 'ACTIONS' for a search-only connector."
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : contains(v.connector_modes, "ACTIONS") || (!v.create_bap_connection && length(v.enabled_actions) == 0)
    ])
    error_message = "A search-only 1P connector (no 'ACTIONS' in connector_modes) must set create_bap_connection = false and enabled_actions = []."
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : (v.data_source_version == null || contains([1, 2], v.data_source_version)) && (!contains(v.connector_modes, "ACTIONS") || (
        lookup(v.action_params, "auth_key", "OAuth") == "OAuth" && lookup(v.action_params, "auth_type", "OAUTH") == "OAUTH" &&
        alltrue([
          for val in values(v.action_params) :
          length(trimspace(val)) > 0 && !can(regex("(?i)(^<your-|://your-|^your-)", trimspace(val)))
        ])
      ))
    ])
    error_message = "1st-party connectors must use data_source_version 1 or 2, and when Actions are enabled any action_params values must be non-empty and free of '<your-...>' placeholders."
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : can(regex("^[a-zA-Z0-9_-]{1,63}$", v.collection_id))
    ])
    error_message = "Every collection_id must be 1-63 characters containing only letters, numbers, hyphens, or underscores."
  }
}

variable "third_party_connectors" {
  description = "Configuration map for enterprise 3rd-party Gemini Enterprise connectors (Jira, Confluence, GitHub, Slack, ServiceNow, SharePoint, Microsoft 365, Entra ID, Salesforce, Box, HubSpot, Monday, Asana, Linear, Notion, Canva, Figma, Zendesk, custom MCP). Put credentials in connector_secret_refs / connector_secrets, not in params."
  type = map(object({
    enabled                 = optional(bool, false)
    collection_id           = string
    collection_display_name = string
    data_source             = string
    data_source_version     = optional(number)
    entities                = list(string)
    entity_params           = optional(map(string), {}) # entity name => JSON object string
    refresh_interval        = optional(string, "86400s")
    auto_run_disabled       = optional(bool, true)
    connector_modes         = list(string)
    create_bap_connection   = optional(bool, false)
    params                  = optional(map(string), {})
    json_params             = optional(string, null)
    action_params           = optional(map(string), {})
    supported_bap_modes     = optional(list(string), [])
    enabled_actions         = optional(list(string), [])
    destination_configs = optional(list(object({
      key = string
      destinations = list(object({
        host = string
        port = optional(number)
      }))
      params = optional(string)
    })), [])
  }))

  default = {
    jira = {
      enabled                 = false
      collection_id           = "ge-3p-jira"
      collection_display_name = "Jira Cloud (3P Federated + Actions)"
      data_source             = "jira"
      data_source_version     = 3
      entities                = ["project", "issue", "comment", "attachment", "worklog", "board"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "create_issue",
        "update_issue",
        "change_issue_status",
        "create_comment",
        "update_comment",
        "upload_attachment",
        "link_issues",
        "get_board",
        "get_issues_for_board",
        "list_boards",
        "assign_issue",
        "create_project",
        "update_project",
        "create_worklog",
        "update_worklog"
      ]
      # SetUpDataConnector validates BOTH top-level params (against ingestion authorization_parameters)
      # AND action_params (against BAP action_authorization_parameters). In jira v3.0, default
      # authorization_parameters[0] (OAUTH) requires a 3LO refresh_token; setting
      # auth_type = "OAUTH_TWO_LEGGED" in params selects authorization_parameters[1] so only
      # client_id and client_secret are required. Supply client_id / client_secret through
      # connector_secret_refs or connector_secrets in BOTH params and action_params.
      params = {
        auth_type    = "OAUTH_TWO_LEGGED"
        instance_id  = "<your-atlassian-cloud-id>"
        instance_uri = "https://your-company.atlassian.net"
      }
      action_params = {
        auth_type             = "OAUTH"
        instance_uri          = "https://your-company.atlassian.net"
        include_custom_fields = "false"
      }
      destination_configs = [
        {
          key          = "url"
          destinations = [{ host = "https://your-company.atlassian.net", port = 443 }]
        }
      ]
    }

    confluence = {
      enabled                 = false
      collection_id           = "ge-3p-confluence"
      collection_display_name = "Confluence Cloud (3P Federated + Actions)"
      data_source             = "confluence"
      data_source_version     = 4
      entities                = ["space", "page", "whiteboard", "blog", "attachment", "comment"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "create_page",
        "upload_attachment",
        "download_attachment",
        "create_blogpost",
        "create_space",
        "update_page",
        "list_pages",
        "list_attachments",
        "list_tasks",
        "list_comments",
        "list_blogposts",
        "list_whiteboards",
        "get_system_info"
      ]
      # Like Jira v3.0, Confluence v4.0 default authorization_parameters[0] (OAUTH) requires a 3LO
      # refresh_token; setting auth_type = "OAUTH_TWO_LEGGED" in top-level params selects the 2LO
      # schema (client_id + client_secret only).
      params = {
        auth_type    = "OAUTH_TWO_LEGGED"
        instance_uri = "https://your-company.atlassian.net"
      }
      action_params = {
        auth_key     = "OAuth"
        auth_type    = "OAUTH"
        instance_uri = "https://your-company.atlassian.net"
      }
    }

    github = {
      enabled                 = false
      collection_id           = "ge-3p-github"
      collection_display_name = "GitHub (3P Federated + Actions)"
      data_source             = "github"
      data_source_version     = 2
      entities                = ["repository", "issue", "pull_request"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "actions_run_trigger",
        "add_comment_to_pending_review",
        "add_issue_comment",
        "add_reply_to_pull_request_comment",
        "create_branch",
        "create_gist",
        "create_or_update_file",
        "create_pull_request",
        "create_repository_issue",
        "delete_file",
        "get_file_content",
        "get_issue",
        "get_pull_request",
        "get_repository",
        "list_branches",
        "list_gists",
        "list_issue_comments",
        "list_organization_repositories",
        "list_pull_request_comments",
        "list_pull_request_commits",
        "list_pull_request_files",
        "list_pull_requests",
        "list_repositories",
        "list_repository_collaborators",
        "list_repository_issues",
        "merge_pull_request",
        "star_repository",
        "triage_issue",
        "unstar_repository",
        "update_gist",
        "update_pull_request"
      ]
      # Verified against prod github_v2_0.textproto:
      # - authorization_parameters[0] (`OAuth`) requires `client_id` and `client_secret` (`refresh_token` is optional).
      # - action_authorization_parameters[0] (`OAuth`) requires `client_id` and `client_secret`, plus `owner_login` (GitHub org name) in `action_params`.
      params = {
        auth_key  = "OAuth"
        auth_type = "OAUTH"
      }
      action_params = {
        auth_key    = "OAuth"
        auth_type   = "OAUTH"
        owner_login = "<your-github-org-name>"
      }
    }

    slack = {
      enabled                 = false
      collection_id           = "ge-3p-slack"
      collection_display_name = "Slack (3P Federated + Actions)"
      data_source             = "slack"
      data_source_version     = 3
      entities                = ["conversation", "file", "message"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "slack_send_message",
        "slack_schedule_message",
        "slack_create_canvas",
        "slack_send_message_draft"
      ]
      # Slack v3.0 marks `unused_auth_param` as `is_required: true` in top-level `authorization_parameters[0]`,
      # and uses `use_google_managed_oauth: true` in `action_authorization_parameters[0]` (zero client_id/secret required!).
      params = {
        unused_auth_param = "unused"
      }
      action_params = {
        auth_key  = "OAuth"
        auth_type = "OAUTH"
      }
    }

    servicenow = {
      enabled                 = false
      collection_id           = "ge-3p-servicenow"
      collection_display_name = "ServiceNow (3P Federated + Actions)"
      data_source             = "servicenow"
      data_source_version     = 2
      entities                = ["catalog", "incident", "knowledge", "users", "attachment"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "create_incident",
        "update_incident",
        "create_change_request",
        "create_task",
        "create_service_catalog_request",
        "update_service_catalog_request",
        "create_request_item",
        "update_request_item"
      ]
      # Live-verified (2026-11-05): ServiceNow v2 validates top-level params against
      # OAUTH_PASSWORD_GRANT (instance_uri, user_account, password, client_id, client_secret) and
      # action_params against OAUTH (auth_key, auth_type, instance_uri, auth_uri, token_uri,
      # client_id, client_secret). Note that the backend appends a placeholder `knowledge_base`
      # entity (`data_store = ""`), so do not include `knowledge_base` in `entities`.
      params = {
        auth_type    = "OAUTH_PASSWORD_GRANT"
        instance_uri = "https://your-instance.service-now.com"
        user_account = "<your-servicenow-username>"
      }
      action_params = {
        auth_key     = "OAuth"
        auth_type    = "OAUTH"
        instance_uri = "https://your-instance.service-now.com"
        auth_uri     = "https://your-instance.service-now.com/oauth_auth.do"
        token_uri    = "https://your-instance.service-now.com/oauth_token.do"
      }
      destination_configs = [
        {
          key          = "host_url"
          destinations = [{ host = "https://your-instance.service-now.com" }]
        }
      ]
    }

    # Live-verified (2026-11-05): SharePoint Online v2 requires `client_id` in top-level `params`
    # (along with `instance_uri` and `tenant_id`), and `client_id`, `client_secret`, `tenant_id`,
    # `instance_uri`, and `o365_environment_type` in `action_params`. The backend appends a
    # placeholder `site` entity (`data_store = ""`).
    sharepoint = {
      enabled                 = false
      collection_id           = "ge-3p-sharepoint"
      collection_display_name = "SharePoint Online (3P Federated + Actions)"
      data_source             = "sharepoint"
      data_source_version     = 2
      entities                = ["attachment", "comment", "event", "page", "file"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "add_list",
        "add_page",
        "check_in_document",
        "check_out_document",
        "create_folder",
        "move_attachment_or_document",
        "rename_attachment_or_document",
        "upload_document"
      ]
      params = {
        tenant_id    = "<your-azure-tenant-id>"
        instance_uri = "https://your-company.sharepoint.com/"
      }
      action_params = {
        auth_type             = "OAUTH"
        instance_uri          = "https://your-company.sharepoint.com/"
        tenant_id             = "<your-azure-tenant-id>"
        o365_environment_type = "com"
      }
      destination_configs = [
        {
          key          = "url"
          destinations = [{ host = "https://your-company.sharepoint.com/", port = 443 }]
        }
      ]
    }

    # Live-verified (2026-11-05): Outlook v1 requires `instance_id`, `client_id`, and `client_secret`
    # in top-level `params`, and `instance_id`, `azure_tenant`, `o365_environment_type`, `client_id`,
    # and `client_secret` in `action_params`. Do not include `"root"` in `entities` — the backend
    # appends `"root"` automatically as a placeholder entity (`data_store = ""`).
    outlook = {
      enabled                 = false
      collection_id           = "ge-3p-outlook"
      collection_display_name = "Outlook (3P Federated + Actions)"
      data_source             = "outlook"
      data_source_version     = 1
      entities                = ["mail", "mail-attachment", "calendar", "contact"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "send_mail",
        "create_event",
        "create_contact",
        "download_attachments",
        "forward_mail",
        "move_mail",
        "update_event",
        "update_contact"
      ]
      params = {
        instance_id = "<your-azure-tenant-id>"
      }
      action_params = {
        auth_type             = "OAUTH"
        instance_id           = "<your-azure-tenant-id>"
        azure_tenant          = "<your-azure-tenant-id>"
        o365_environment_type = "com"
      }
    }

    # Live-verified (2026-11-05): OneDrive v1 requires `instance_uri`, `tenant_id`,
    # `decrypt_mip_files`, and `client_id` in top-level `params`, and `tenant_id`, `azure_tenant`,
    # `o365_environment_type`, `client_id`, and `client_secret` in `action_params`.
    onedrive = {
      enabled                 = false
      collection_id           = "ge-3p-onedrive"
      collection_display_name = "OneDrive (3P Federated + Actions)"
      data_source             = "onedrive"
      data_source_version     = 1
      entities                = ["file"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "upload_file",
        "copy_file",
        "create_folder"
      ]
      params = {
        instance_uri      = "https://your-company-my.sharepoint.com/"
        tenant_id         = "<your-azure-tenant-id>"
        decrypt_mip_files = "false"
      }
      action_params = {
        auth_type             = "OAUTH"
        tenant_id             = "<your-azure-tenant-id>"
        azure_tenant          = "<your-azure-tenant-id>"
        o365_environment_type = "com"
      }
      destination_configs = [
        {
          key          = "url"
          destinations = [{ host = "https://your-company-my.sharepoint.com/", port = 443 }]
        }
      ]
    }

    # Live-verified (2026-11-05): Teams v1 requires `instance_id`, `domain_url`, `client_id`, and
    # `client_secret` in top-level `params`, and `instance_id`, `azure_tenant`, `include_all_groups`,
    # `include_all_users`, `client_id`, and `client_secret` in `action_params`.
    teams = {
      enabled                 = false
      collection_id           = "ge-3p-teams"
      collection_display_name = "Microsoft Teams (3P Federated + Actions)"
      data_source             = "teams"
      data_source_version     = 1
      entities                = ["team", "channel", "channel-message", "channel-file", "chat-message"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED", "ACTIONS"]
      create_bap_connection   = true
      supported_bap_modes     = ["ACTIONS"]
      enabled_actions = [
        "send_chat_message",
        "send_channel_message"
      ]
      params = {
        instance_id = "<your-azure-tenant-id>"
        domain_url  = "https://your-company.sharepoint.com"
      }
      action_params = {
        auth_type          = "OAUTH"
        instance_id        = "<your-azure-tenant-id>"
        azure_tenant       = "<your-azure-tenant-id>"
        include_all_groups = "true"
        include_all_users  = "true"
      }
    }

    azure_active_directory = {
      enabled                 = false
      collection_id           = "ge-3p-entraid"
      collection_display_name = "Microsoft Entra ID"
      data_source             = "azure_active_directory"
      data_source_version     = 1
      entities                = ["Userprofiles"]
      refresh_interval        = "10800s"
      auto_run_disabled       = true
      connector_modes         = ["DATA_INGESTION"]
      create_bap_connection   = false
      supported_bap_modes     = []
      enabled_actions         = []
      params = {
        azure_tenant                         = "<your-azure-tenant-id>"
        fetch_extension_properties_for_users = "false"
        realtime_sync_enabled                = "false"
      }
    }

    # Live-verified (2026-11-05): custom_mcp v1 requires `oauth_access_token` in top-level `params`
    # (no `instance_uri` in top-level `params` — `instance_uri` belongs in `action_params` along
    # with `mcp_server_description`, `mcp_server_source`, `auth_type`, `auth_uri`, `token_uri`,
    # `scopes`, `auth_uri_params`, `client_id`, and `client_secret`).
    custom_mcp = {
      enabled                 = false
      collection_id           = "ge-3p-bq-mcp"
      collection_display_name = "BigQuery MCP (Federated)"
      data_source             = "custom_mcp"
      data_source_version     = 1
      entities                = ["mcp_data"]
      refresh_interval        = "86400s"
      auto_run_disabled       = true
      connector_modes         = ["FEDERATED"]
      create_bap_connection   = true
      supported_bap_modes     = []
      enabled_actions         = ["search"]
      params = {
        oauth_access_token = "unused"
      }
      action_params = {
        mcp_server_source      = "BYO_MCP"
        mcp_server_description = "BigQuery MCP Server for querying and analyzing datasets."
        auth_type              = "OAUTH"
        instance_uri           = "https://bigquery.googleapis.com/mcp"
        auth_uri               = "https://accounts.google.com/o/oauth2/v2/auth"
        token_uri              = "https://oauth2.googleapis.com/token"
        scopes                 = "openid email https://www.googleapis.com/auth/cloud-platform"
        auth_uri_params        = "&access_type=offline&prompt=consent"
      }
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.third_party_connectors : contains([
        "jira", "confluence", "github", "slack", "servicenow", "sharepoint",
        "outlook", "onedrive", "teams", "azure_active_directory", "custom_mcp",
        "salesforce", "box", "hubspot", "monday", "asana", "linear",
        "notion", "canva", "figma", "zendesk", "dropbox",
        "atlassian_rovo", "autodesk_product_help", "sourcegraph"
      ], v.data_source)
    ])
    error_message = "All 3P connectors must use a supported enterprise data_source: jira, confluence, github, slack, servicenow, sharepoint, outlook, onedrive, teams, azure_active_directory, custom_mcp, salesforce, box, hubspot, monday, asana, linear, notion, canva, figma, zendesk, dropbox, atlassian_rovo, autodesk_product_help, or sourcegraph."
  }

  validation {
    condition = alltrue([
      for k, v in var.third_party_connectors : can(regex("^[a-zA-Z0-9_-]{1,63}$", v.collection_id))
    ])
    error_message = "Every 3P collection_id must be 1-63 characters containing only letters, numbers, hyphens, or underscores."
  }

  validation {
    condition = alltrue([
      for k, v in var.third_party_connectors : !v.enabled || length(v.entities) > 0
    ])
    error_message = "Every enabled 3P connector must specify at least one entity in 'entities'."
  }

  validation {
    condition = alltrue([
      for k, v in var.third_party_connectors : !v.enabled || !v.create_bap_connection || (
        !contains(v.connector_modes, "ACTIONS") || length(v.enabled_actions) > 0
      )
    ])
    error_message = "Every enabled 3P connector with create_bap_connection = true and 'ACTIONS' mode must have a non-empty enabled_actions list."
  }

  validation {
    condition = alltrue([
      for k, v in var.third_party_connectors : length(v.connector_modes) > 0 && alltrue([
        for m in v.connector_modes : contains(["FEDERATED", "ACTIONS", "DATA_INGESTION", "EUA", "FEDERATED_AND_EUA"], m)
      ])
    ])
    error_message = "Every 3P connector needs a non-empty connector_modes list drawn from: FEDERATED, ACTIONS, DATA_INGESTION, EUA, FEDERATED_AND_EUA."
  }

  validation {
    condition = alltrue([
      for k, v in var.third_party_connectors : !v.enabled || alltrue([
        for value in concat(
          values(v.params),
          values(v.action_params),
          flatten([for d in v.destination_configs : [for dest in d.destinations : dest.host]])
        ) : !can(regex("(?i)(<your|your-|\\[your_|://example\\.)", value))
      ])
    ])
    error_message = "An enabled 3P connector still contains a placeholder value (for example '<your-azure-tenant-id>', 'https://your-company...', or 'https://example...'). Replace every placeholder in params, action_params, and destination_configs before enabling it."
  }

  validation {
    condition = alltrue([
      for k, v in var.third_party_connectors : alltrue([
        for entity, p in v.entity_params : contains(v.entities, entity) && can(keys(jsondecode(p)))
      ])
    ])
    error_message = "entity_params keys must be entity names listed in 'entities', and each value must be a JSON object string, e.g. jsonencode({ exclusion_filters = {}, inclusion_filters = {} })."
  }
}

# ==============================================================================
# Safety, encryption, and credential handling
# ==============================================================================

variable "deletion_policy" {
  description = <<-EOT
    What Terraform does when a data connector would be deleted (terraform destroy, or a change to
    a ForceNew field such as collection_id, data_source, or entities):
      PREVENT (default) - refuse to delete; the apply fails instead of destroying the connector
                          and its DataStores.
      DELETE            - allow deletion (use for dev/test teardown).
      ABANDON           - remove the connector from Terraform state but leave it running.
    Also set as the google-beta provider default, so connectors brought in with `terraform import`
    record this policy in state immediately.
  EOT
  type        = string
  default     = "PREVENT"

  validation {
    condition     = contains(["PREVENT", "DELETE", "ABANDON"], var.deletion_policy)
    error_message = "deletion_policy must be one of: PREVENT, DELETE, ABANDON."
  }
}

variable "kms_key_name" {
  description = "Optional Cloud KMS CryptoKey (projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>) that protects the DataStores each connector creates. Required when a CMEK organization policy covers Discovery Engine. Changing it forces connector replacement."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be a full Cloud KMS CryptoKey name: projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "connector_secret_refs" {
  description = <<-EOT
    Secret Manager references for connector credentials, keyed by connectors (1P action_params) or
    enabled third_party_connectors (params / action_params) key.
    Terraform reads each secret version at plan/apply time and merges the VALUE into the
    connector's params / action_params; the Discovery Engine API never sees the reference.
    Every value must be a full secret version name:
      projects/<project>/secrets/<secret>/versions/<version|latest>
    The identity running Terraform needs roles/secretmanager.secretAccessor on those secrets.
    Resolved values are sensitive (masked in plan output) but, like all provider inputs, are
    stored in Terraform state - use an encrypted remote backend.
  EOT
  type = map(object({
    params        = optional(map(string), {})
    action_params = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for k, v in var.connector_secret_refs : [
        for ref in concat(values(v.params), values(v.action_params)) :
        can(regex("^projects/[^/]+/secrets/[^/]+/versions/[^/]+$", ref))
      ]
    ]))
    error_message = "Every connector_secret_refs value must be a full secret version name: projects/<project>/secrets/<secret>/versions/<version|latest>."
  }
}

variable "connector_secrets" {
  description = <<-EOT
    Raw credential values for connectors, keyed by connectors (1P action_params) or enabled
    third_party_connectors (params / action_params) key, merged into params / action_params.
    Marked sensitive so values are masked in plan output. Prefer connector_secret_refs; if you
    use this, supply it via TF_VAR_connector_secrets or a gitignored *.auto.tfvars file - never
    commit it. Values are stored in Terraform state.
  EOT
  type = map(object({
    params        = optional(map(string), {})
    action_params = optional(map(string), {})
  }))
  default   = {}
  sensitive = true
}

variable "action_activation_timeout_seconds" {
  description = "How long the post-create step waits for a connector's BAP action connection to reach ACTIVE before failing the apply."
  type        = number
  default     = 300

  validation {
    condition     = var.action_activation_timeout_seconds >= 30 && var.action_activation_timeout_seconds <= 1800
    error_message = "action_activation_timeout_seconds must be between 30 and 1800."
  }
}
