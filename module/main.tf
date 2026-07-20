##################################################
# Object stores
##################################################

# Deploy/manage each Nutanix Objects object store. This provisions worker VMs
# and networking and is long running; timeouts.create defaults to
# var.object_store_create_timeout.
resource "nutanix_object_store_v2" "object_store" {
  for_each = var.object_stores

  name               = each.value.name
  description        = each.value.description
  cluster_ext_id     = local.object_store_cluster_ext_ids[each.key]
  deployment_version = each.value.deployment_version
  domain             = each.value.domain
  region             = each.value.region
  num_worker_nodes   = each.value.num_worker_nodes
  total_capacity_gib = each.value.total_capacity_gib
  state              = each.value.state

  public_network_reference  = each.value.public_network_reference
  storage_network_reference = each.value.storage_network_reference

  # Static public network IP addresses.
  dynamic "public_network_ips" {
    for_each = each.value.public_network_ips
    content {
      dynamic "ipv4" {
        for_each = public_network_ips.value.ipv4 != null ? [public_network_ips.value.ipv4] : []
        content {
          value         = ipv4.value.value
          prefix_length = ipv4.value.prefix_length
        }
      }
      dynamic "ipv6" {
        for_each = public_network_ips.value.ipv6 != null ? [public_network_ips.value.ipv6] : []
        content {
          value         = ipv6.value.value
          prefix_length = ipv6.value.prefix_length
        }
      }
    }
  }

  # Storage network virtual IP.
  dynamic "storage_network_vip" {
    for_each = each.value.storage_network_vip != null ? [each.value.storage_network_vip] : []
    content {
      dynamic "ipv4" {
        for_each = storage_network_vip.value.ipv4 != null ? [storage_network_vip.value.ipv4] : []
        content {
          value         = ipv4.value.value
          prefix_length = ipv4.value.prefix_length
        }
      }
      dynamic "ipv6" {
        for_each = storage_network_vip.value.ipv6 != null ? [storage_network_vip.value.ipv6] : []
        content {
          value         = ipv6.value.value
          prefix_length = ipv6.value.prefix_length
        }
      }
    }
  }

  # Storage network DNS IP.
  dynamic "storage_network_dns_ip" {
    for_each = each.value.storage_network_dns_ip != null ? [each.value.storage_network_dns_ip] : []
    content {
      dynamic "ipv4" {
        for_each = storage_network_dns_ip.value.ipv4 != null ? [storage_network_dns_ip.value.ipv4] : []
        content {
          value         = ipv4.value.value
          prefix_length = ipv4.value.prefix_length
        }
      }
      dynamic "ipv6" {
        for_each = storage_network_dns_ip.value.ipv6 != null ? [storage_network_dns_ip.value.ipv6] : []
        content {
          value         = ipv6.value.value
          prefix_length = ipv6.value.prefix_length
        }
      }
    }
  }

  # Ownership / category metadata.
  dynamic "metadata" {
    for_each = each.value.metadata != null ? [each.value.metadata] : []
    content {
      category_ids         = metadata.value.category_ids
      owner_reference_id   = metadata.value.owner_reference_id
      project_reference_id = metadata.value.project_reference_id
    }
  }

  timeouts {
    create = local.object_store_create_timeout[each.key]
    update = try(each.value.timeouts.update, null)
    delete = try(each.value.timeouts.delete, null)
  }
}

##################################################
# Certificate bundles (rendered from sensitive input)
##################################################

# Render inline certificate bundles to disk. The bundle content is sensitive and
# is written with restrictive permissions; the provider then reads the file via
# the certificate resource's 'path'. Only certificates without an existing
# 'path' are rendered here.
resource "local_sensitive_file" "certificate_bundle" {
  for_each = local.rendered_certificates

  filename        = local.certificate_paths[each.key]
  content         = lookup(var.object_store_certificate_bundles, each.key, "")
  file_permission = "0600"
}

##################################################
# Object store certificates
##################################################

# Attach a TLS certificate to an object store. The provider consumes a JSON
# bundle at 'path' (either an operator-managed file or one rendered above).
resource "nutanix_object_store_certificate_v2" "certificate" {
  for_each = var.object_store_certificates

  object_store_ext_id = nutanix_object_store_v2.object_store[each.value.object_store_key].ext_id
  path                = local.certificate_paths[each.key]

  depends_on = [local_sensitive_file.certificate_bundle]
}
