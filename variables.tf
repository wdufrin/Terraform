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

variable "connectors" {
  description = "Configuration map for the core 1st-party Gemini Enterprise connectors with all supported BAP Actions enabled."
  type = map(object({
    collection_id           = string
    collection_display_name = string
    data_source             = string
    data_source_version     = optional(number)
    entity_name             = string
    refresh_interval        = optional(string, "0s")
    auto_run_disabled       = optional(bool, false)
    json_params             = optional(string, "{}")
    connector_modes         = list(string)
    create_bap_connection   = bool
    action_params           = optional(map(string), {})
    supported_bap_modes     = list(string)
    enabled_actions         = list(string)
  }))

  default = {
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
      action_params = {
        auth_key  = "OAuth"
        auth_type = "OAUTH"
      }
      supported_bap_modes = ["ACTIONS"]
      enabled_actions = [
        "copy_file",
        "create_file",
        "download_file_content",
        "get_file_metadata",
        "get_file_permissions",
        "googledocs_read_doc",
        "googledocs_update_doc",
        "googlesheets_get_spreadsheet",
        "googlesheets_get_values",
        "googlesheets_insert_dimension",
        "googlesheets_update_formulas",
        "googlesheets_update_spreadsheet",
        "googlesheets_update_values",
        "googleslides_read_presentation",
        "googleslides_update_presentation",
        "list_recent_files",
        "read_file_content",
        "search_files",
        "share_file",
        "trash_file",
        "update_file"
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
      action_params = {
        auth_key  = "OAuth"
        auth_type = "OAUTH"
      }
      supported_bap_modes = ["ACTIONS"]
      enabled_actions = [
        "create_event",
        "delete_event",
        "get_event",
        "list_calendars",
        "list_events",
        "respond_to_event",
        "search_events",
        "suggest_time",
        "update_event"
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
      action_params = {
        auth_key  = "OAuth"
        auth_type = "OAUTH"
      }
      supported_bap_modes = ["ACTIONS"]
      enabled_actions = [
        "batch_label_messages",
        "batch_label_threads",
        "batch_unlabel_messages",
        "batch_unlabel_threads",
        "create_draft",
        "create_filter",
        "create_label",
        "delete_filter",
        "delete_label",
        "forward",
        "get_message_attachment",
        "get_thread",
        "label_message",
        "label_thread",
        "list_drafts",
        "list_filters",
        "list_labels",
        "list_threads",
        "reply",
        "search_threads",
        "send_message",
        "unlabel_message",
        "unlabel_thread",
        "update_draft",
        "update_label"
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
      action_params = {
        auth_key  = "OAuth"
        auth_type = "OAUTH"
      }
      supported_bap_modes = ["ACTIONS"]
      enabled_actions = [
        "add_membership",
        "add_reaction",
        "create_conversation",
        "list_memberships",
        "list_messages",
        "list_messages_markdown",
        "remove_membership",
        "remove_reaction",
        "search_conversations",
        "search_messages",
        "send_message",
        "send_message_markdown",
        "update_membership"
      ]
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : contains(["google_drive", "google_calendar", "google_mail", "google_chat"], v.data_source)
    ])
    error_message = "All connectors must use a supported core 1st-party data_source: google_drive, google_calendar, google_mail, or google_chat."
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : contains(v.connector_modes, "ACTIONS") && v.create_bap_connection == true && contains(v.supported_bap_modes, "ACTIONS") && length(v.enabled_actions) > 0
    ])
    error_message = "Every connector must have 'ACTIONS' enabled in connector_modes, create_bap_connection = true, 'ACTIONS' in supported_bap_modes, and a non-empty enabled_actions list."
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : v.data_source_version == 2 && lookup(v.action_params, "auth_key", "") == "OAuth" && lookup(v.action_params, "auth_type", "") == "OAUTH"
    ])
    error_message = "1st-party connectors with Actions enabled require data_source_version = 2 and action_params = { auth_key = 'OAuth', auth_type = 'OAUTH' } so Discovery Engine enables static 1P OAuth secrets."
  }

  validation {
    condition = alltrue([
      for k, v in var.connectors : can(regex("^[a-z][a-z0-9-]{0,62}$", v.collection_id))
    ])
    error_message = "Every collection_id must conform to RFC-1034 (start with a lowercase letter, contain only lowercase letters, digits, or hyphens, max 63 characters)."
  }
}
