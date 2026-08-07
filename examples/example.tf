# This example wires BOTH entry points of this repo together:
#
#   ../module          — the object store itself (nutanix provider)
#   ../modules/buckets — buckets on that store's S3 endpoint (aws provider)
#
# The two are separate entry points precisely so neither consumer is forced to
# hold the other's credential. A root module that wants both, like this one,
# declares both providers; a deploy-only root declares only nutanix.
terraform {
  # Provider 'for_each' (used for the aws provider below) needs >= 1.9.0.
  required_version = ">= 1.9.0"

  required_providers {
    nutanix = {
      source  = "nutanix/nutanix"
      version = ">= 2.4.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0"
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

##################################################
# Entry point 2: buckets (aws provider)
##################################################

# One aws provider instance per object store, so N stores need no hand-written
# aliases. Each instance points at that store's S3 endpoint.
#
# The 'skip_*' arguments are all mandatory against Objects: there is no IAM to
# validate credentials against, no account id to fetch, no EC2 metadata service
# and no AWS region. 'region' is required by the provider but arbitrary — it is
# never sent anywhere meaningful — and 's3_use_path_style' is required because
# ADR 0023 pins path-style addressing (one endpoint fronts every bucket, so DNS
# needs one name rather than a wildcard zone).
variable "object_store_endpoints" {
  description = "Map of object store key => S3 endpoint URL, e.g. { lab = \"https://lab-objects.objects.example.com\" }."
  type        = map(string)
  default     = {}
}

# The S3 access key pair for the Objects store. Per ADR 0023 this comes from a
# PREVIOUS apply (SOPS), never from a resource in this one: provider
# configuration cannot depend on a resource, so wiring it from
# nutanix_user_key_v2 in the same apply leaves it unknown at the first plan and
# can never bootstrap.
variable "objects_access_key" {
  description = "S3 access key for the Objects endpoint."
  type        = string
  sensitive   = true
  default     = null
}

variable "objects_secret_key" {
  description = "S3 secret key for the Objects endpoint."
  type        = string
  sensitive   = true
  default     = null
}

provider "aws" {
  alias    = "objects"
  for_each = var.object_store_endpoints

  region     = "us-east-1" # Arbitrary; Objects has no regions.
  access_key = var.objects_access_key
  secret_key = var.objects_secret_key

  endpoints {
    s3 = each.value
  }

  # Path-style addressing: <endpoint>/<bucket>, not <bucket>.<endpoint>.
  s3_use_path_style = true

  # None of the AWS control-plane calls the provider would otherwise make exist
  # on an Objects endpoint.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

# The buckets entry point is instantiated once per store and handed the WHOLE
# bucket map; each instance manages only the entries whose 'store' matches.
#
# NOTE: OpenTofu warns that this module's for_each matches the provider's. A
# provider instance must outlive the resources bound to it by one plan/apply
# round, so REMOVING a store from var.object_store_endpoints in the same change
# that removes its buckets is a planning error. Remove the buckets first, apply,
# then remove the store. Driving the provider from a superset collection (the
# full store inventory) rather than the same variable avoids the warning.
module "buckets" {
  # source = "git::ssh://git@github.com/bingamon-lab-tf-modules/tf-ntnx-objects.git//modules/buckets?ref=v0.1.0"
  source   = "../modules/buckets"
  for_each = var.object_store_endpoints

  providers = {
    aws = aws.objects[each.key]
  }

  store = each.key

  buckets = {
    # Durable: the state bucket is managed by state stored inside it, which is
    # exactly why prevent_destroy on it is mandatory.
    tofu_state = {
      store      = "lab"
      name       = "lab-tofu-state"
      durable    = true
      versioning = true
    }

    # Durable: re-mirroring a registry inside an air gap is the expensive
    # failure this flag exists to prevent.
    harbor = {
      store   = "lab"
      name    = "lab-harbor-registry"
      durable = true
      access = {
        read  = ["arn:aws:iam::000000000000:user/harbor"]
        write = ["arn:aws:iam::000000000000:user/harbor"]
      }
    }

    # Durable + WORM. COMPLIANCE mode is the only mode Objects implements, and
    # its retention cannot be shortened or lifted by anyone — hence the
    # explicit acknowledgement.
    velero = {
      store      = "lab"
      name       = "lab-velero"
      durable    = true
      versioning = true
      object_lock = {
        mode                     = "COMPLIANCE"
        retention_days           = 35
        acknowledge_irreversible = true
      }
    }

    # Ephemeral, with a lifecycle rule and the raw policy escape hatch.
    scratch = {
      store         = "lab"
      name          = "lab-scratch"
      durable       = false
      force_destroy = true
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::000000000000:user/ci" }
          Action    = ["s3:GetObject", "s3:PutObject"]
          Resource  = "arn:aws:s3:::lab-scratch/*"
        }]
      })
      lifecycle_rules = [{
        id                                     = "expire-scratch"
        expiration_days                        = 7
        abort_incomplete_multipart_upload_days = 1
      }]
    }

    # Bound to a DIFFERENT store, so the 'lab' instance above ignores it.
    dr_velero = {
      store      = "dr"
      name       = "dr-velero"
      durable    = true
      versioning = true
    }
  }
}

output "bucket_arns" {
  description = "Store key => (bucket key => ARN), for building policies elsewhere."
  value       = { for k, m in module.buckets : k => m.bucket_arns }
}
