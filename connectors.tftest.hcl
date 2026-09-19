# Native Terraform Test Suite (`terraform test`)
# Validates positive plan configuration for all 4 connectors (68 enabled actions)
# and negative/adversarial rejection of invalid inputs.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id = "example-enterprise-prod"
  location   = "global"
}

run "provisions_all_four_1p_connectors_with_all_68_actions_enabled" {
  command = plan

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_drive"].data_source_version == 2 && length(google_discovery_engine_data_connector.core_1p_connectors["google_drive"].bap_config[0].enabled_actions) == 21
    error_message = "Google Drive connector must use v2 and enable all 21 supported actions."
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_calendar"].data_source_version == 2 && length(google_discovery_engine_data_connector.core_1p_connectors["google_calendar"].bap_config[0].enabled_actions) == 9
    error_message = "Google Calendar connector must use v2 and enable all 9 supported actions."
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_mail"].data_source_version == 2 && length(google_discovery_engine_data_connector.core_1p_connectors["google_mail"].bap_config[0].enabled_actions) == 25
    error_message = "Gmail connector must use v2 and enable all 25 supported actions."
  }

  assert {
    condition     = google_discovery_engine_data_connector.core_1p_connectors["google_chat"].data_source_version == 2 && length(google_discovery_engine_data_connector.core_1p_connectors["google_chat"].bap_config[0].enabled_actions) == 13
    error_message = "Google Chat connector must use v2 and enable all 13 supported actions."
  }
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
