##################################################
# Object store outputs
##################################################

output "object_stores" {
  description = "Managed object stores keyed by input key (ext_id, name, cluster, sizing, certificate ext_ids)."
  value       = local.object_stores_out
}

output "object_store_ids" {
  description = "Map of object store key => ext_id."
  value       = local.object_store_ids_out
}

output "object_store_certificates" {
  description = "Managed object-store TLS certificates keyed by input key."
  value       = local.certificates_out
}

##################################################
# Lookup outputs (gated data sources)
##################################################

output "existing_object_stores" {
  description = "Inventory of existing object stores from nutanix_object_stores_v2 (empty unless lookup_existing_object_stores = true)."
  value       = try(data.nutanix_object_stores_v2.existing[0].object_stores, [])
}

output "looked_up_object_stores" {
  description = "Individually looked-up object stores from nutanix_object_store_v2, keyed as in object_store_lookup_ext_ids."
  value = {
    for k, d in data.nutanix_object_store_v2.by_ext_id : k => {
      ext_id = d.ext_id
      name   = d.name
      domain = d.domain
      state  = d.state
    }
  }
}

##################################################
# Summary + aggregate
##################################################

output "objects_summary" {
  description = "Plan-time summary of the requested object-store configuration."
  value       = local.objects_summary
}

# Single aggregate output exposing everything the module produces. Required by
# spec §7.6 (issue 502) so the LZ -> root forwarding chain never re-introduces
# the silently-empty root output bug.
output "outputs" {
  description = "Aggregate of all module outputs."
  value = {
    object_stores             = local.object_stores_out
    object_store_ids          = local.object_store_ids_out
    object_store_certificates = local.certificates_out
    objects_summary           = local.objects_summary
    existing_object_stores    = try(data.nutanix_object_stores_v2.existing[0].object_stores, [])
    looked_up_object_stores = {
      for k, d in data.nutanix_object_store_v2.by_ext_id : k => {
        ext_id = d.ext_id
        name   = d.name
        domain = d.domain
        state  = d.state
      }
    }
  }
}
