##################################################
# Data Lookups
##################################################

# Resolve cluster names to ext_ids. Only queried when at least one object store
# identifies its cluster by name (rather than a direct cluster_ext_id).
data "nutanix_clusters_v2" "clusters" {
  count = length(local.cluster_names) > 0 ? 1 : 0
}

# Gated inventory of all existing object stores (list data source). Enabled with
# var.lookup_existing_object_stores; useful for discovery / drift reporting.
data "nutanix_object_stores_v2" "existing" {
  count = var.lookup_existing_object_stores ? 1 : 0
}

# Gated per-ext_id lookup of specific existing object stores (singular data
# source). Populated from var.object_store_lookup_ext_ids.
data "nutanix_object_store_v2" "by_ext_id" {
  for_each = var.object_store_lookup_ext_ids

  ext_id = each.value
}

# NOTE: provider 2.4.2 exposes NO object-store certificate data source
# (no nutanix_object_store_certificate(s)_v2). Certificate discovery is therefore
# not available; only the certificate resource is managed here.
