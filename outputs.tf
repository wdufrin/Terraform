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

output "data_store_resource_names" {
  description = "Map of connector keys to the underlying Discovery Engine DataStore resource names created for each entity."
  value = {
    for k, c in google_discovery_engine_data_connector.core_1p_connectors : k => [
      for e in c.entities : e.data_store
    ]
  }
}
