# Native Terraform Test Suite (`terraform test`)
#
# What this suite proves: input validation (including hostile / malformed inputs), plan-time
# wiring from variables to resources, the ignore_changes lifecycle rule, the finalizer's target
# selection, and secret-merging logic - all evaluated by Terraform core.
#
# What it does NOT prove: that the Discovery Engine API accepts these payloads. Every provider is
# a mock_provider, so no request ever reaches Google Cloud. Live behaviour must be verified with a
# real `terraform apply` in a disposable project.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "example-enterprise-prod"
  location   = "global"
}

run "provisions_all_five_1p_connectors_in_federated_search_mode_by_default" {
  command = plan

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_drive"].connector_modes == tolist(["FEDERATED"]) && length(google_discovery_engine_data_connector.core_1p_connectors["google_drive"].action_config) == 0
    error_message = "Google Drive connector must default to zero-credential FEDERATED search mode."
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_calendar"].connector_modes == tolist(["FEDERATED"]) && length(google_discovery_engine_data_connector.core_1p_connectors["google_calendar"].action_config) == 0
    error_message = "Google Calendar connector must default to zero-credential FEDERATED search mode."
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_mail"].connector_modes == tolist(["FEDERATED"]) && length(google_discovery_engine_data_connector.core_1p_connectors["google_mail"].action_config) == 0
    error_message = "Gmail connector must default to zero-credential FEDERATED search mode."
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_chat"].connector_modes == tolist(["FEDERATED"]) && length(google_discovery_engine_data_connector.core_1p_connectors["google_chat"].action_config) == 0
    error_message = "Google Chat connector must default to zero-credential FEDERATED search mode."
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_sites"].connector_modes == tolist(["FEDERATED"]) && length(google_discovery_engine_data_connector.core_1p_connectors["google_sites"].action_config) == 0
    error_message = "Google Sites connector must default to zero-credential FEDERATED search mode."
  }

  assert {
    condition     = alltrue([for c in google_discovery_engine_data_connector.core_1p_connectors : c.deletion_policy == "PREVENT"])
    error_message = "Connectors must default to deletion_policy = PREVENT so a destroy or forced replacement cannot silently delete them."
  }

  assert {
    condition     = length(google_discovery_engine_data_connector.core_1p_connectors) == 5 && length(terraform_data.finalize_connector_actions) == 0 && length(google_discovery_engine_data_connector.third_party_connectors) == 0
    error_message = "Defaults must create the 5 core 1P search connectors, no action finalizers, and no 3P connectors."
  }
}

run "provisions_1p_connector_with_actions_and_oauth_secrets" {
  command = plan

  variables {
    connectors = {
      google_calendar = {
        collection_id           = "ge-1p-google-cal"
        collection_display_name = "Google Calendar (1P Federated + Actions)"
        data_source             = "google_calendar"
        data_source_version     = 2
        entity_name             = "google_calendar"
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = ["create_calendar_event", "update_calendar_event"]
      }
    }
    connector_secret_refs = {
      google_calendar = {
        action_params = {
          client_id     = "projects/acme-secrets/secrets/gws-oauth-client-id/versions/latest"
          client_secret = "projects/acme-secrets/secrets/gws-oauth-client-secret/versions/latest"
        }
      }
    }
  }

  override_data {
    target = data.google_secret_manager_secret_version.connector_secret_refs
    values = {
      secret_data = "resolved-gws-oauth-value"
    }
  }

  assert {
    condition = nonsensitive(
      google_discovery_engine_data_connector.core_1p_connectors["google_calendar"].action_config[0].action_params["client_id"] == "resolved-gws-oauth-value" &&
      google_discovery_engine_data_connector.core_1p_connectors["google_calendar"].action_config[0].action_params["client_secret"] == "resolved-gws-oauth-value" &&
      google_discovery_engine_data_connector.core_1p_connectors["google_calendar"].action_config[0].action_params["auth_key"] == "OAuth" &&
      google_discovery_engine_data_connector.core_1p_connectors["google_calendar"].action_config[0].action_params["auth_type"] == "OAUTH"
    )
    error_message = "1P connector with ACTIONS must merge resolved OAuth client_id and client_secret into action_config.action_params."
  }

  assert {
    condition     = contains(keys(terraform_data.finalize_connector_actions), "google_calendar")
    error_message = "1P connector with ACTIONS must be registered in finalize_connector_actions."
  }
}

run "rejects_1p_connector_with_actions_missing_oauth_credentials" {
  command = plan

  variables {
    connectors = {
      google_calendar = {
        collection_id           = "ge-1p-google-cal"
        collection_display_name = "Google Calendar (1P Federated + Actions)"
        data_source             = "google_calendar"
        data_source_version     = 2
        entity_name             = "google_calendar"
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        action_params           = { auth_key = "OAuth", auth_type = "OAUTH" }
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = ["create_calendar_event", "update_calendar_event"]
      }
    }
  }

  expect_failures = [
    terraform_data.input_validation
  ]
}

run "rejects_invalid_project_id" {
  command = plan

  variables {
    project_id = "INVALID_PROJECT_ID!"
  }

  expect_failures = [
    var.project_id
  ]
}

run "rejects_unsupported_location" {
  command = plan

  variables {
    location = "us-central1"
  }

  expect_failures = [
    var.location
  ]
}

run "rejects_connector_with_disabled_or_empty_actions" {
  command = plan

  variables {
    connectors = {
      google_drive = {
        collection_id           = "ge-1p-google-drive"
        collection_display_name = "Google Drive"
        data_source             = "google_drive"
        data_source_version     = 2
        entity_name             = "google_drive"
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        action_params           = { auth_key = "OAuth", auth_type = "OAUTH" }
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = []
      }
    }
  }

  expect_failures = [
    var.connectors
  ]
}

run "rejects_malformed_collection_id" {
  command = plan

  variables {
    connectors = {
      google_drive = {
        collection_id           = "Invalid_Collection_ID!"
        collection_display_name = "Google Drive"
        data_source             = "google_drive"
        data_source_version     = 2
        entity_name             = "google_drive"
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        action_params           = { auth_key = "OAuth", auth_type = "OAUTH" }
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = ["search_files"]
      }
    }
  }

  expect_failures = [
    var.connectors
  ]
}

run "rejects_invalid_1p_connector_mode" {
  command = plan

  variables {
    connectors = {
      google_drive = {
        collection_id           = "ge-1p-google-drive"
        collection_display_name = "Google Drive"
        data_source             = "google_drive"
        data_source_version     = 2
        entity_name             = "google_drive"
        connector_modes         = ["SEARCH"]
      }
    }
  }

  expect_failures = [
    var.connectors
  ]
}

run "allows_search_only_1p_connector" {
  command = plan

  variables {
    connectors = {
      google_drive = {
        collection_id           = "ge-1p-google-drive"
        collection_display_name = "Google Drive (search only)"
        data_source             = "google_drive"
        data_source_version     = 2
        entity_name             = "google_drive"
        connector_modes         = ["FEDERATED"]
      }
      google_sites = {
        collection_id           = "ge-1p-google-sites"
        collection_display_name = "Google Sites (search only)"
        data_source             = "google_sites"
        data_source_version     = 1
        entity_name             = "google_sites"
        connector_modes         = ["FEDERATED"]
      }
    }
  }

  assert {
    condition     = length(google_discovery_engine_data_connector.core_1p_connectors["google_drive"].action_config) == 0 && length(google_discovery_engine_data_connector.core_1p_connectors["google_drive"].bap_config) == 0
    error_message = "A search-only 1P connector must not send action_config or bap_config."
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_sites"].data_source == "google_sites" && length(google_discovery_engine_data_connector.core_1p_connectors["google_sites"].action_config) == 0
    error_message = "Google Sites must be accepted as a search-only 1P connector."
  }

  assert {
    condition     = length(terraform_data.finalize_connector_actions) == 0
    error_message = "A search-only connector must not be targeted by the action finalizer."
  }
}

run "rejects_google_sites_with_actions_mode" {
  command = plan

  variables {
    connectors = {
      google_sites = {
        collection_id           = "ge-1p-google-sites"
        collection_display_name = "Google Sites"
        data_source             = "google_sites"
        data_source_version     = 1
        entity_name             = "google_sites"
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = ["search_sites"]
      }
    }
  }

  expect_failures = [
    var.connectors
  ]
}

run "rejects_search_only_1p_connector_with_actions_configured" {
  command = plan

  variables {
    connectors = {
      google_drive = {
        collection_id           = "ge-1p-google-drive"
        collection_display_name = "Google Drive"
        data_source             = "google_drive"
        data_source_version     = 2
        entity_name             = "google_drive"
        connector_modes         = ["FEDERATED"]
        create_bap_connection   = true
        enabled_actions         = ["share_file"]
      }
    }
  }

  expect_failures = [
    var.connectors
  ]
}

run "provisions_all_six_3p_connectors_when_enabled" {
  command = plan

  variables {
    third_party_connectors = {
      jira = {
        enabled                 = true
        collection_id           = "ge-3p-jira"
        collection_display_name = "Jira Cloud (3P Federated + Actions)"
        data_source             = "jira"
        data_source_version     = 3
        entities                = ["project", "issue", "comment", "attachment", "worklog", "board"]
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
        params = {
          instance_id  = "11111111-2222-3333-4444-555555555555"
          instance_uri = "https://acme-corp.atlassian.net"
        }
        action_params = {
          auth_type             = "OAUTH"
          instance_uri          = "https://acme-corp.atlassian.net"
          include_custom_fields = "false"
        }
      }

      confluence = {
        enabled                 = true
        collection_id           = "ge-3p-confluence"
        collection_display_name = "Confluence Cloud (3P Federated + Actions)"
        data_source             = "confluence"
        data_source_version     = 4
        entities                = ["space", "page", "whiteboard", "blog", "attachment", "comment"]
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
        params = {
          auth_type    = "OAUTH"
          instance_uri = "https://acme-corp.atlassian.net"
        }
        action_params = {
          auth_key     = "OAuth"
          auth_type    = "OAUTH"
          instance_uri = "https://acme-corp.atlassian.net"
        }
      }

      github = {
        enabled                 = true
        collection_id           = "ge-3p-github"
        collection_display_name = "GitHub (3P Federated + Actions)"
        data_source             = "github"
        data_source_version     = 2
        entities                = ["repository", "issue", "pull_request"]
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions = [
          "actions_run_trigger",
          "create_pull_request",
          "get_repository",
          "merge_pull_request"
        ]
        params = {
          auth_type = "OAUTH"
        }
        action_params = {
          auth_key  = "OAuth"
          auth_type = "OAUTH_PKCE"
        }
      }

      slack = {
        enabled                 = true
        collection_id           = "ge-3p-slack"
        collection_display_name = "Slack (3P Federated + Actions)"
        data_source             = "slack"
        data_source_version     = 3
        entities                = ["message", "channel"]
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions = [
          "slack_send_message",
          "slack_schedule_message"
        ]
        params = {}
        action_params = {
          auth_key  = "OAuth"
          auth_type = "OAUTH"
        }
      }

      servicenow = {
        enabled                 = true
        collection_id           = "ge-3p-servicenow"
        collection_display_name = "ServiceNow (3P Federated + Actions)"
        data_source             = "servicenow"
        data_source_version     = 2
        entities                = ["incident", "change_request"]
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions = [
          "create_incident",
          "update_incident"
        ]
        params = {
          auth_type    = "OAUTH_PASSWORD_GRANT"
          instance_uri = "https://acme-corp.service-now.com"
        }
        action_params = {
          auth_key     = "OAuth"
          auth_type    = "OAUTH"
          instance_uri = "https://acme-corp.service-now.com"
        }
      }

      sharepoint = {
        enabled                 = true
        collection_id           = "ge-3p-sharepoint"
        collection_display_name = "SharePoint Online (3P Federated + Actions)"
        data_source             = "sharepoint"
        data_source_version     = 2
        entities                = ["file", "page"]
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions = [
          "create_folder",
          "upload_document"
        ]
        params = {
          tenant_id    = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
          instance_uri = "https://acme-corp.sharepoint.com"
        }
        action_params = {
          auth_type    = "OAUTH"
          instance_uri = "https://acme-corp.sharepoint.com"
        }
      }
    }
  }

  assert {
    condition     = length(google_discovery_engine_data_connector.third_party_connectors) == 6
    error_message = "All 6 third-party connectors must be planned when enabled = true."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["jira"].data_source == "jira" && length(google_discovery_engine_data_connector.third_party_connectors["jira"].bap_config[0].enabled_actions) == 15
    error_message = "Jira connector must enable all 15 actions."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["confluence"].data_source == "confluence" && length(google_discovery_engine_data_connector.third_party_connectors["confluence"].bap_config[0].enabled_actions) == 13
    error_message = "Confluence connector must enable all 13 actions."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["github"].data_source == "github" && length(google_discovery_engine_data_connector.third_party_connectors["github"].bap_config[0].enabled_actions) == 4
    error_message = "GitHub connector must enable all 4 configured actions."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["slack"].data_source == "slack" && length(google_discovery_engine_data_connector.third_party_connectors["slack"].bap_config[0].enabled_actions) == 2
    error_message = "Slack connector must enable all 2 configured actions."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["slack"].json_params == "{}" && google_discovery_engine_data_connector.third_party_connectors["slack"].params == null
    error_message = "A 3P connector with no params must send json_params = \"{}\" and no params (the provider requires exactly one of the two)."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["servicenow"].data_source == "servicenow" && length(google_discovery_engine_data_connector.third_party_connectors["servicenow"].bap_config[0].enabled_actions) == 2
    error_message = "ServiceNow connector must enable all 2 configured actions."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["sharepoint"].data_source == "sharepoint" && length(google_discovery_engine_data_connector.third_party_connectors["sharepoint"].bap_config[0].enabled_actions) == 2
    error_message = "SharePoint connector must enable all 2 configured actions."
  }

  assert {
    condition     = length(terraform_data.finalize_connector_actions) == 6
    error_message = "Finalize actions step must target the 6 enabled 3P action connectors (default 1P connectors are search-only)."
  }
}

run "rejects_invalid_3p_data_source" {
  command = plan

  variables {
    third_party_connectors = {
      unsupported = {
        enabled                 = true
        collection_id           = "ge-3p-unsupported"
        collection_display_name = "Unsupported"
        data_source             = "unsupported_data_source"
        entities                = ["item"]
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = ["act"]
      }
    }
  }

  expect_failures = [
    var.third_party_connectors
  ]
}

run "rejects_3p_connector_with_empty_entities" {
  command = plan

  variables {
    third_party_connectors = {
      jira = {
        enabled                 = true
        collection_id           = "ge-3p-jira"
        collection_display_name = "Jira Cloud"
        data_source             = "jira"
        data_source_version     = 3
        entities                = []
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = ["create_issue"]
      }
    }
  }

  expect_failures = [
    var.third_party_connectors
  ]
}

run "rejects_3p_connector_with_empty_actions_when_bap_enabled" {
  command = plan

  variables {
    third_party_connectors = {
      github = {
        enabled                 = true
        collection_id           = "ge-3p-github"
        collection_display_name = "GitHub"
        data_source             = "github"
        data_source_version     = 2
        entities                = ["repository"]
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = []
      }
    }
  }

  expect_failures = [
    var.third_party_connectors
  ]
}

run "rejects_invalid_3p_connector_mode" {
  command = plan

  variables {
    third_party_connectors = {
      github = {
        enabled                 = true
        collection_id           = "ge-3p-github"
        collection_display_name = "GitHub"
        data_source             = "github"
        data_source_version     = 2
        entities                = ["repository"]
        connector_modes         = ["INGESTION"]
      }
    }
  }

  expect_failures = [
    var.third_party_connectors
  ]
}

run "rejects_enabled_connector_with_placeholder_values" {
  command = plan

  variables {
    third_party_connectors = {
      jira = {
        enabled                 = true
        collection_id           = "ge-3p-jira"
        collection_display_name = "Jira Cloud"
        data_source             = "jira"
        data_source_version     = 3
        entities                = ["project", "issue"]
        connector_modes         = ["FEDERATED", "ACTIONS"]
        create_bap_connection   = true
        supported_bap_modes     = ["ACTIONS"]
        enabled_actions         = ["create_issue"]
        params = {
          instance_id  = "<your-atlassian-cloud-id>"
          instance_uri = "https://your-company.atlassian.net"
        }
      }
    }
  }

  expect_failures = [
    var.third_party_connectors
  ]
}

run "rejects_enabled_connector_with_example_host" {
  command = plan

  variables {
    third_party_connectors = {
      servicenow = {
        enabled                 = true
        collection_id           = "ge-3p-servicenow"
        collection_display_name = "ServiceNow"
        data_source             = "servicenow"
        data_source_version     = 2
        entities                = ["incident"]
        connector_modes         = ["FEDERATED"]
        params = {
          instance_uri = "https://example.service-now.com"
        }
      }
    }
  }

  expect_failures = [
    var.third_party_connectors
  ]
}

run "excludes_connector_without_bap_from_finalizer" {
  command = plan

  variables {
    third_party_connectors = {
      github = {
        enabled                 = true
        collection_id           = "ge-3p-github"
        collection_display_name = "GitHub Ingestion Only"
        data_source             = "github"
        data_source_version     = 2
        entities                = ["repository"]
        connector_modes         = ["DATA_INGESTION"]
        create_bap_connection   = false
        supported_bap_modes     = []
        enabled_actions         = []
      }
    }
  }

  assert {
    condition     = length(google_discovery_engine_data_connector.third_party_connectors) == 1
    error_message = "GitHub connector must be planned."
  }

  assert {
    condition     = !contains(keys(terraform_data.finalize_connector_actions), "github")
    error_message = "GitHub connector without BAP connection must not be included in finalize_connector_actions."
  }

  assert {
    condition     = length(terraform_data.finalize_connector_actions) == 0
    error_message = "No connectors should be in finalize_connector_actions when all connectors are search-only or ingestion-only."
  }

  assert {
    condition     = length(google_discovery_engine_data_connector.third_party_connectors["github"].action_config) == 0 && length(google_discovery_engine_data_connector.third_party_connectors["github"].bap_config) == 0
    error_message = "An ingestion-only connector must not send empty action_config / bap_config blocks."
  }
}

run "excludes_federated_only_connector_from_finalizer" {
  command = plan

  variables {
    third_party_connectors = {
      custom_mcp = {
        enabled                 = true
        collection_id           = "ge-3p-bq-mcp"
        collection_display_name = "BigQuery MCP (Federated)"
        data_source             = "custom_mcp"
        data_source_version     = 1
        entities                = ["mcp_data"]
        connector_modes         = ["FEDERATED"]
        create_bap_connection   = true
        enabled_actions         = ["search"]
        params = {
          instance_uri = "https://bigquery.googleapis.com/mcp"
        }
      }
    }
  }

  assert {
    condition     = !contains(keys(terraform_data.finalize_connector_actions), "custom_mcp")
    error_message = "A FEDERATED-only connector never reports actionState=ACTIVE, so it must not be polled by the finalizer."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["custom_mcp"].action_config[0].create_bap_connection == true && google_discovery_engine_data_connector.third_party_connectors["custom_mcp"].bap_config[0].enabled_actions[0] == "search"
    error_message = "custom_mcp must still send createBapConnection and enabledActions = [\"search\"] like production connectors."
  }
}

run "resolves_secret_manager_refs_into_params" {
  command = plan

  variables {
    third_party_connectors = {
      jira = {
        enabled                 = true
        collection_id           = "ge-3p-jira"
        collection_display_name = "Jira Cloud"
        data_source             = "jira"
        data_source_version     = 3
        entities                = ["project"]
        connector_modes         = ["FEDERATED"]
        params = {
          instance_uri = "https://acme-corp.atlassian.net"
        }
      }
    }
    connector_secret_refs = {
      jira = {
        params = {
          client_secret = "projects/acme-secrets/secrets/jira-client-secret/versions/latest"
        }
        action_params = {
          client_secret = "projects/acme-secrets/secrets/jira-client-secret/versions/7"
        }
      }
    }
  }

  override_data {
    target = data.google_secret_manager_secret_version.connector_secret_refs
    values = {
      secret_data = "resolved-secret-value"
    }
  }

  assert {
    condition     = data.google_secret_manager_secret_version.connector_secret_refs["jira/params/client_secret"].secret == "projects/acme-secrets/secrets/jira-client-secret" && data.google_secret_manager_secret_version.connector_secret_refs["jira/params/client_secret"].version == "latest"
    error_message = "A secret version name must be split into secret = projects/<p>/secrets/<s> and version = <v>."
  }

  assert {
    condition     = data.google_secret_manager_secret_version.connector_secret_refs["jira/action_params/client_secret"].version == "7"
    error_message = "Pinned secret versions must be passed through unchanged."
  }

  assert {
    condition     = nonsensitive(google_discovery_engine_data_connector.third_party_connectors["jira"].params["client_secret"] == "resolved-secret-value")
    error_message = "The resolved secret VALUE, not the reference, must be sent in params."
  }

  assert {
    condition     = nonsensitive(google_discovery_engine_data_connector.third_party_connectors["jira"].params["instance_uri"] == "https://acme-corp.atlassian.net")
    error_message = "Non-secret params must be preserved when secrets are merged in."
  }

  assert {
    condition     = nonsensitive(google_discovery_engine_data_connector.third_party_connectors["jira"].action_config[0].action_params["client_secret"] == "resolved-secret-value")
    error_message = "Secret refs for action_params must be resolved into action_config.action_params."
  }
}

run "merges_raw_sensitive_secrets_into_params" {
  command = plan

  variables {
    third_party_connectors = {
      slack = {
        enabled                 = true
        collection_id           = "ge-3p-slack"
        collection_display_name = "Slack"
        data_source             = "slack"
        data_source_version     = 3
        entities                = ["message"]
        connector_modes         = ["FEDERATED"]
      }
    }
    connector_secrets = {
      slack = {
        params = {
          client_id     = "raw-client-id"
          client_secret = "raw-client-secret"
        }
      }
    }
  }

  assert {
    condition     = nonsensitive(google_discovery_engine_data_connector.third_party_connectors["slack"].params["client_secret"] == "raw-client-secret")
    error_message = "Raw connector_secrets must be merged into params."
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["slack"].json_params == null
    error_message = "Once secrets add params, json_params must not also be sent (provider ExactlyOneOf)."
  }
}

run "rejects_malformed_secret_ref" {
  command = plan

  variables {
    connector_secret_refs = {
      jira = {
        params = {
          client_secret = "jira-client-secret"
        }
      }
    }
  }

  expect_failures = [
    var.connector_secret_refs
  ]
}

run "rejects_secret_refs_for_unknown_connector" {
  command = plan

  variables {
    connector_secret_refs = {
      github = {
        params = {
          client_secret = "projects/acme-secrets/secrets/github/versions/latest"
        }
      }
    }
  }

  expect_failures = [
    terraform_data.input_validation
  ]
}

run "rejects_raw_secrets_for_unknown_connector" {
  command = plan

  variables {
    connector_secrets = {
      not_a_connector = {
        params = {
          client_secret = "value"
        }
      }
    }
  }

  expect_failures = [
    terraform_data.input_validation
  ]
}

run "rejects_duplicate_collection_ids_across_maps" {
  command = plan

  variables {
    third_party_connectors = {
      github = {
        enabled                 = true
        collection_id           = "ge-1p-google-drive"
        collection_display_name = "GitHub"
        data_source             = "github"
        data_source_version     = 2
        entities                = ["repository"]
        connector_modes         = ["FEDERATED"]
      }
    }
  }

  expect_failures = [
    terraform_data.input_validation
  ]
}

run "rejects_duplicate_keys_across_maps" {
  command = plan

  variables {
    third_party_connectors = {
      google_drive = {
        enabled                 = true
        collection_id           = "ge-3p-github"
        collection_display_name = "GitHub"
        data_source             = "github"
        data_source_version     = 2
        entities                = ["repository"]
        connector_modes         = ["FEDERATED"]
      }
    }
  }

  expect_failures = [
    terraform_data.input_validation
  ]
}

run "rejects_collection_id_too_long_with_suffix" {
  command = plan

  variables {
    append_random_suffix = true
    connectors = {
      google_drive = {
        collection_id           = "a-very-long-collection-identifier-that-is-sixty-characters-x"
        collection_display_name = "Google Drive"
        data_source             = "google_drive"
        data_source_version     = 2
        entity_name             = "google_drive"
        connector_modes         = ["FEDERATED"]
      }
    }
  }

  expect_failures = [
    terraform_data.input_validation
  ]
}

run "applies_entity_params" {
  command = plan

  variables {
    third_party_connectors = {
      jira = {
        enabled                 = true
        collection_id           = "ge-3p-jira"
        collection_display_name = "Jira Cloud"
        data_source             = "jira"
        data_source_version     = 3
        entities                = ["project", "issue"]
        entity_params = {
          project = "{\"exclusion_filters\":{},\"inclusion_filters\":{}}"
        }
        connector_modes = ["FEDERATED"]
        params = {
          instance_uri = "https://acme-corp.atlassian.net"
        }
      }
    }
  }

  assert {
    condition     = google_discovery_engine_data_connector.third_party_connectors["jira"].entities[0].params == "{\"exclusion_filters\":{},\"inclusion_filters\":{}}" && google_discovery_engine_data_connector.third_party_connectors["jira"].entities[1].params == null
    error_message = "entity_params must be applied to the matching entity only."
  }
}

run "rejects_entity_params_for_unknown_entity" {
  command = plan

  variables {
    third_party_connectors = {
      jira = {
        enabled                 = true
        collection_id           = "ge-3p-jira"
        collection_display_name = "Jira Cloud"
        data_source             = "jira"
        entities                = ["project"]
        entity_params           = { board = "{}" }
        connector_modes         = ["FEDERATED"]
      }
    }
  }

  expect_failures = [
    var.third_party_connectors
  ]
}

run "rejects_entity_params_with_invalid_json" {
  command = plan

  variables {
    third_party_connectors = {
      jira = {
        enabled                 = true
        collection_id           = "ge-3p-jira"
        collection_display_name = "Jira Cloud"
        data_source             = "jira"
        entities                = ["project"]
        entity_params           = { project = "{not json" }
        connector_modes         = ["FEDERATED"]
      }
    }
  }

  expect_failures = [
    var.third_party_connectors
  ]
}

run "passes_kms_key_and_deletion_policy_through" {
  command = plan

  variables {
    kms_key_name    = "projects/acme-kms/locations/global/keyRings/ge/cryptoKeys/connectors"
    deletion_policy = "DELETE"
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_drive"].kms_key_name == "projects/acme-kms/locations/global/keyRings/ge/cryptoKeys/connectors" && google_discovery_engine_data_connector.core_1p_connectors["google_drive"].deletion_policy == "DELETE"
    error_message = "kms_key_name and deletion_policy must be applied to every connector."
  }
}

run "rejects_malformed_kms_key_name" {
  command = plan

  variables {
    kms_key_name = "my-key"
  }

  expect_failures = [
    var.kms_key_name
  ]
}

run "rejects_invalid_deletion_policy" {
  command = plan

  variables {
    deletion_policy = "NUKE"
  }

  expect_failures = [
    var.deletion_policy
  ]
}

run "uses_deterministic_collection_ids_when_suffix_disabled" {
  command = plan

  variables {
    append_random_suffix = false
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_drive"].collection_id == "ge-1p-google-drive"
    error_message = "With append_random_suffix = false, collection_id must exactly equal the input collection_id for state restoration and import."
  }

  assert {
    condition     = length(random_id.collection_suffix) == 0
    error_message = "random_id.collection_suffix must not be created when append_random_suffix = false."
  }
}

run "appends_random_suffix_when_suffix_enabled" {
  command = plan

  variables {
    append_random_suffix = true
  }

  assert {
    condition     = length(random_id.collection_suffix) == 1
    error_message = "random_id.collection_suffix must be created when append_random_suffix = true."
  }

  assert {
    condition     = random_id.collection_suffix[0].byte_length == 2
    error_message = "random_id.collection_suffix byte length must be 2 (4 hex chars)."
  }
}

# The last two runs share state: the first applies (against mocks) and the second re-plans with a
# renamed collection_display_name. They use a search-only connector so no local-exec finalizer runs.

run "apply_search_only_connector_with_original_display_name" {
  command = apply

  variables {
    deletion_policy = "DELETE"
    connectors = {
      google_drive = {
        collection_id           = "ge-1p-google-drive"
        collection_display_name = "Original Name"
        data_source             = "google_drive"
        data_source_version     = 2
        entity_name             = "google_drive"
        connector_modes         = ["FEDERATED"]
      }
    }
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_drive"].collection_display_name == "Original Name"
    error_message = "Initial apply must use the configured display name."
  }
}

run "renaming_display_name_does_not_replace_connector" {
  command = plan

  variables {
    deletion_policy = "DELETE"
    connectors = {
      google_drive = {
        collection_id           = "ge-1p-google-drive"
        collection_display_name = "Renamed"
        data_source             = "google_drive"
        data_source_version     = 2
        entity_name             = "google_drive"
        connector_modes         = ["FEDERATED"]
      }
    }
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_drive"].collection_display_name == "Original Name"
    error_message = "collection_display_name is ForceNew but never read back by the provider; ignore_changes must keep the prior value so imports and renames never destroy the connector."
  }
}
