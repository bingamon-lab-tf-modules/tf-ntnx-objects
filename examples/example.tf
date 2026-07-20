terraform {
  required_version = ">= 1.9.0"

  required_providers {
    nutanix = {
      source  = "nutanix/nutanix"
      version = ">= 2.4.2"
    }
  }
}

# This module is a Day-2 Prism Central operation: point the provider at the
# Prism Central VIP.
provider "nutanix" {
  endpoint = var.prism_central_endpoint
  username = var.prism_central_username
  password = var.prism_central_password
  insecure = true
}

variable "prism_central_endpoint" {
  description = "Prism Central VIP / endpoint."
  type        = string
}

variable "prism_central_username" {
  description = "Prism Central username."
  type        = string
}

variable "prism_central_password" {
  description = "Prism Central password."
  type        = string
  sensitive   = true
}

# SENSITIVE certificate bundle (raw JSON the provider expects). Supplied via a
# sensitive variable / TF_VAR, never committed to YAML.
variable "objects_certificate_bundle" {
  description = "Raw JSON certificate bundle for the object store TLS certificate."
  type        = string
  sensitive   = true
  default     = null
}

module "objects" {
  # source = "git::ssh://git@github.com/bingamon-lab-tf-modules/tf-ntnx-objects.git//module?ref=v0.1.0"
  source = "../module"

  # Object store(s) to deploy. The cluster is resolved from its name.
  object_stores = {
    lab = {
      name               = "lab-objects"
      description        = "S3-compatible object store for lab backups"
      cluster            = "bingamon"
      deployment_version = "5.1.1"
      domain             = "objects-0.pc.example.com"
      num_worker_nodes   = 1
      total_capacity_gib = 20

      public_network_reference  = "57c4caf1-67e3-457e-8265-6d872f2a3135"
      storage_network_reference = "57c4caf1-67e3-457e-8265-6d872f2a3135"

      public_network_ips = [
        { ipv4 = { value = "10.44.77.123" } },
      ]
      storage_network_vip    = { ipv4 = { value = "10.44.77.125" } }
      storage_network_dns_ip = { ipv4 = { value = "10.44.77.124" } }

      # Object-store deployment is long running.
      timeouts = { create = "90m" }
    }
  }

  # TLS certificate for the store. Key material flows through the sensitive
  # bundle variable and is rendered to disk by the module.
  object_store_certificates = {
    lab_cert = {
      object_store_key = "lab"
    }
  }

  object_store_certificate_bundles = var.objects_certificate_bundle != null ? {
    lab_cert = var.objects_certificate_bundle
  } : {}
}

output "object_store_ids" {
  description = "Object store key => ext_id."
  value       = module.objects.object_store_ids
}

output "outputs" {
  description = "Aggregate outputs from the objects module."
  value       = module.objects.outputs
}
