terraform {
  # >= 1.7.0: connectors.tftest.hcl uses mock_provider / override_data.
  required_version = ">= 1.7.0"

  required_providers {
    # google-beta >= 7.30.0: action_config / bap_config / data_source_version were added in
    # 7.23.0 and destination_configs.params / destinations.port in 7.30.0. Upper bound guards
    # against breaking changes in the next major version.
    google = {
      source  = "hashicorp/google"
      version = ">= 7.30.0, < 9.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.30.0, < 9.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0, < 4.0.0"
    }
  }
}
