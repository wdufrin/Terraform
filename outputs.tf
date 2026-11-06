output "project_id" {
  description = "The target GCP Project ID where the Gemini Enterprise connectors are provisioned."
  value       = var.project_id
}

output "location" {
  description = "The Discovery Engine location where the connectors reside."
  value       = var.location
}

output "connectors" {
  description = "Detailed status and metadata of all provisioned 1st-party Gemini Enterprise connectors."
  value = {
    for k, c in google_discovery_engine_data_connector.core_1p_connectors : k => {
      name                    = c.name
      collection_id           = c.collection_id
      collection_display_name = c.collection_display_name
      data_source             = c.data_source
      data_source_version     = c.data_source_version
      connector_type          = c.connector_type
      state                   = c.state
      action_state            = c.action_state
      connector_modes         = c.connector_modes
      is_action_configured    = try(c.action_config[0].is_action_configured, false)
      create_bap_connection   = try(c.action_config[0].create_bap_connection, false)
      bap_config              = c.bap_config
      entities                = c.entities
      errors                  = c.errors
    }
  }
}

output "third_party_connectors" {
  description = "Detailed status and metadata of any enabled 3rd-party Gemini Enterprise connectors."
  value = {
    for k, c in google_discovery_engine_data_connector.third_party_connectors : k => {
      name                    = c.name
      collection_id           = c.collection_id
      collection_display_name = c.collection_display_name
      data_source             = c.data_source
      data_source_version     = c.data_source_version
      connector_type          = c.connector_type
      state                   = c.state
      action_state            = c.action_state
      connector_modes         = c.connector_modes
      is_action_configured    = try(c.action_config[0].is_action_configured, false)
      create_bap_connection   = try(c.action_config[0].create_bap_connection, false)
      bap_config              = c.bap_config
      entities                = c.entities
      errors                  = c.errors
    }
  }
}

output "data_store_resource_names" {
  description = "Map of connector keys to the underlying Discovery Engine DataStore resource names created for each entity across 1P and 3P."
  value = {
    for k, c in local.all_connectors : k => [
      for e in c.entities : e.data_store
    ]
  }
}

output "import_commands" {
  description = "Ready-to-run Terraform CLI import commands to restore or adopt existing connectors into Terraform state."
  value = merge(
    {
      for k, v in var.connectors : k => "terraform import 'google_discovery_engine_data_connector.core_1p_connectors[\"${k}\"]' projects/${var.project_id}/locations/${var.location}/collections/${v.collection_id}${local.collection_suffix}/dataConnector"
    },
    {
      for k, v in var.third_party_connectors : k => "terraform import 'google_discovery_engine_data_connector.third_party_connectors[\"${k}\"]' projects/${var.project_id}/locations/${var.location}/collections/${v.collection_id}${local.collection_suffix}/dataConnector"
      if v.enabled
    }
  )
}
