##################################################
# Validation checks
##################################################

# Every object store must resolve to a cluster ext_id, either supplied directly
# via 'cluster_ext_id' or looked up from 'cluster' by name.
check "object_store_cluster_resolved" {
  assert {
    condition = alltrue([
      for k, id in local.object_store_cluster_ext_ids : id != null && id != ""
    ])
    error_message = "One or more object stores could not resolve a cluster ext_id. Set 'cluster_ext_id' directly, or ensure the 'cluster' name exists on Prism Central."
  }
}

# Every certificate must reference an object store that this module manages.
check "certificate_object_store_exists" {
  assert {
    condition = alltrue([
      for k, c in var.object_store_certificates : contains(keys(var.object_stores), c.object_store_key)
    ])
    error_message = "Each object_store_certificates entry's 'object_store_key' must match a key in var.object_stores."
  }
}
