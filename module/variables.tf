##################################################
# Object stores
##################################################

# Map of Nutanix Objects object stores to manage, keyed by a logical name.
# Wraps nutanix_object_store_v2. Store-level only: this module does NOT manage
# buckets, users or access policies (the 2.4.2 provider has no such resources).
variable "object_stores" {
  description = "Map of Nutanix Objects object stores to deploy/manage (nutanix_object_store_v2), keyed by a logical name."
  type = map(object({
    # Identity
    name        = string                 # Object store deployment name.
    description = optional(string, null) # Free-form description.

    # Placement. Supply EITHER 'cluster' (name, resolved to ext_id via the
    # nutanix_clusters_v2 data source) OR 'cluster_ext_id' directly.
    cluster        = optional(string, null)
    cluster_ext_id = optional(string, null)

    # Deployment sizing / addressing (all optional; null lets the provider
    # compute a default where it supports one).
    deployment_version = optional(string, null) # e.g. "5.1.1".
    domain             = optional(string, null) # DNS (sub)domain, e.g. "objects-0.pc.example.com".
    region             = optional(string, null) # Deployment region.
    num_worker_nodes   = optional(number, null) # Worker VM count (each needs 10 vCPU / 32 GiB).
    total_capacity_gib = optional(number, null) # Total capacity in GiB.
    state              = optional(string, null) # e.g. "UNDEPLOYED_OBJECT_STORE" for a draft.

    # Networking. References are subnet UUIDs (AHV) or IPAM names (ESXi).
    public_network_reference  = optional(string, null)
    storage_network_reference = optional(string, null)

    # Static public network IPs (set of ipv4/ipv6 addresses).
    public_network_ips = optional(list(object({
      ipv4 = optional(object({
        value         = string
        prefix_length = optional(number, null)
      }), null)
      ipv6 = optional(object({
        value         = string
        prefix_length = optional(number, null)
      }), null)
    })), [])

    # Storage network virtual IP (single).
    storage_network_vip = optional(object({
      ipv4 = optional(object({ value = string, prefix_length = optional(number, null) }), null)
      ipv6 = optional(object({ value = string, prefix_length = optional(number, null) }), null)
    }), null)

    # Storage network DNS IP (single).
    storage_network_dns_ip = optional(object({
      ipv4 = optional(object({ value = string, prefix_length = optional(number, null) }), null)
      ipv6 = optional(object({ value = string, prefix_length = optional(number, null) }), null)
    }), null)

    # Ownership / category metadata (optional).
    metadata = optional(object({
      category_ids         = optional(list(string), null)
      owner_reference_id   = optional(string, null)
      project_reference_id = optional(string, null)
    }), null)

    # Per-store create/update/delete timeouts. Object-store deployment
    # provisions worker VMs and is long running; raise 'create' for real applies.
    timeouts = optional(object({
      create = optional(string, null)
      update = optional(string, null)
      delete = optional(string, null)
    }), null)
  }))
  default = {}

  # Every store needs a non-empty name.
  validation {
    condition     = alltrue([for k, s in var.object_stores : s.name != null && trimspace(s.name) != ""])
    error_message = "Each object_stores entry must set a non-empty 'name'."
  }

  # Exactly one of 'cluster' or 'cluster_ext_id' must identify the cluster.
  validation {
    condition = alltrue([
      for k, s in var.object_stores : (s.cluster != null) != (s.cluster_ext_id != null)
    ])
    error_message = "Each object_stores entry must set EITHER 'cluster' (name) OR 'cluster_ext_id' (not both, not neither)."
  }

  # Worker node count, when set, must be at least one.
  validation {
    condition     = alltrue([for k, s in var.object_stores : s.num_worker_nodes == null || try(s.num_worker_nodes >= 1, false)])
    error_message = "When set, 'num_worker_nodes' must be >= 1."
  }

  # Total capacity, when set, must be positive.
  validation {
    condition     = alltrue([for k, s in var.object_stores : s.total_capacity_gib == null || try(s.total_capacity_gib > 0, false)])
    error_message = "When set, 'total_capacity_gib' must be greater than 0."
  }

  # Domain, when set, must have at least two dot-separated parts.
  validation {
    condition     = alltrue([for k, s in var.object_stores : s.domain == null || length(split(".", s.domain)) >= 2])
    error_message = "When set, 'domain' must be a fully qualified name with at least two dot-separated parts (e.g. 'objects-0.pc.example.com')."
  }
}

##################################################
# Object store certificates
##################################################

# TLS certificates to attach to managed object stores (nutanix_object_store_certificate_v2).
# The provider requires a 'path' to a JSON bundle on disk (public cert, private
# key, CA chain, alternate FQDNs/IPs). Supply that bundle EITHER as an existing
# file via 'path', OR inline (sensitive) via var.object_store_certificate_bundles
# which this module renders to disk with local_sensitive_file. Key material is
# NEVER read from YAML.
variable "object_store_certificates" {
  description = "TLS certificates to attach to object stores (nutanix_object_store_certificate_v2), keyed by a logical name."
  type = map(object({
    object_store_key = string                 # Key into var.object_stores this certificate belongs to.
    path             = optional(string, null) # Path to an existing JSON certificate bundle. When null, the bundle is rendered from var.object_store_certificate_bundles[<key>].
  }))
  default = {}

  # Every certificate must reference an object store key.
  validation {
    condition     = alltrue([for k, c in var.object_store_certificates : c.object_store_key != null && trimspace(c.object_store_key) != ""])
    error_message = "Each object_store_certificates entry must set a non-empty 'object_store_key'."
  }
}

# SENSITIVE. Certificate JSON bundles keyed by the SAME key as
# object_store_certificates. Each value is the raw JSON document the provider
# expects (publicCert, privateKey, ca, alternateFqdns, alternateIps, ...). The
# module writes each to disk via local_sensitive_file and passes the path to the
# certificate resource. This is the ONLY channel for private key material — it
# must never appear in YAML or non-sensitive variables.
variable "object_store_certificate_bundles" {
  description = "SENSITIVE map (cert key => raw JSON certificate bundle) rendered to disk for certificates that do not supply an existing 'path'. The only supported channel for private key material."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# Directory into which inline certificate bundles are rendered. Defaults to a
# hidden directory under the root module.
variable "certificate_output_dir" {
  description = "Directory where inline certificate JSON bundles are written. Defaults to '<root>/.object_store_certificates'."
  type        = string
  default     = null
}

##################################################
# Data source lookups (gated)
##################################################

# When true, look up the full inventory of existing object stores via the
# nutanix_object_stores_v2 list data source and expose it through outputs.
variable "lookup_existing_object_stores" {
  description = "When true, query all existing object stores (nutanix_object_stores_v2) and expose them via the 'existing_object_stores' output."
  type        = bool
  default     = false
}

# Optional map of ext_ids to look up individually via the singular
# nutanix_object_store_v2 data source.
variable "object_store_lookup_ext_ids" {
  description = "Map of logical name => object store ext_id to look up individually (nutanix_object_store_v2). Exposed via the 'looked_up_object_stores' output."
  type        = map(string)
  default     = {}
}

##################################################
# Behaviour
##################################################

# Default create timeout applied to object stores that do not set their own
# timeouts.create. Object-store deployment is long running.
variable "object_store_create_timeout" {
  description = "Default create timeout for nutanix_object_store_v2 when a store does not set timeouts.create. Object-store deployment is long running; raise for real applies."
  type        = string
  default     = "60m"
}
