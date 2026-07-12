locals {

  ##################################################
  # Cluster name -> ext_id resolution
  ##################################################

  # Distinct cluster names referenced by object stores (drives the data lookup).
  cluster_names = distinct([for k, s in var.object_stores : s.cluster if s.cluster != null])

  # name -> ext_id map built from the clusters data source (empty when unused).
  cluster_name_to_ext_id = try(
    { for c in data.nutanix_clusters_v2.clusters[0].cluster_entities : c.name => c.ext_id },
    {}
  )

  # Effective cluster ext_id per object store (direct value wins over name lookup).
  object_store_cluster_ext_ids = {
    for k, s in var.object_stores : k => (
      s.cluster_ext_id != null
      ? s.cluster_ext_id
      : (s.cluster != null ? lookup(local.cluster_name_to_ext_id, s.cluster, null) : null)
    )
  }

  ##################################################
  # Timeouts
  ##################################################

  # Effective create timeout per object store (per-store override, else default).
  object_store_create_timeout = {
    for k, s in var.object_stores : k => (
      try(s.timeouts.create, null) != null ? s.timeouts.create : var.object_store_create_timeout
    )
  }

  ##################################################
  # Certificates
  ##################################################

  # Where inline certificate bundles are rendered.
  certificate_output_dir = coalesce(var.certificate_output_dir, "${path.root}/.object_store_certificates")

  # Certificates whose bundle must be rendered from the sensitive variable
  # (those without an existing 'path'). Derived only from the NON-sensitive
  # certificate map so the key set never becomes sensitive.
  rendered_certificates = {
    for k, c in var.object_store_certificates : k => c if c.path == null
  }

  # Effective JSON bundle path per certificate (existing path or rendered file).
  certificate_paths = {
    for k, c in var.object_store_certificates : k => (
      c.path != null ? c.path : "${local.certificate_output_dir}/${k}.json"
    )
  }

  ##################################################
  # Output shapes (DRY between named + aggregate outputs)
  ##################################################

  object_stores_out = {
    for k, s in nutanix_object_store_v2.object_store : k => {
      ext_id              = s.ext_id
      name                = s.name
      cluster_ext_id      = s.cluster_ext_id
      description         = s.description
      domain              = s.domain
      region              = s.region
      state               = s.state
      num_worker_nodes    = s.num_worker_nodes
      total_capacity_gib  = s.total_capacity_gib
      certificate_ext_ids = s.certificate_ext_ids
    }
  }

  object_store_ids_out = {
    for k, s in nutanix_object_store_v2.object_store : k => s.ext_id
  }

  certificates_out = {
    for k, c in nutanix_object_store_certificate_v2.certificate : k => {
      ext_id              = c.ext_id
      object_store_ext_id = c.object_store_ext_id
      path                = c.path
    }
  }

  ##################################################
  # Plan-time summary
  ##################################################

  objects_summary = {
    object_store_count         = length(var.object_stores)
    certificate_count          = length(var.object_store_certificates)
    rendered_certificate_count = length(local.rendered_certificates)
    clusters_referenced        = local.cluster_names
    existing_lookup_enabled    = var.lookup_existing_object_stores
    worker_nodes               = { for k, s in var.object_stores : k => s.num_worker_nodes }
  }
}
