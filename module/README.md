# tf-ntnx-objects

## Table of Contents

## Overview

A description of the module goes here.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | >= 2.4.0 |
| <a name="requirement_nutanix"></a> [nutanix](#requirement\_nutanix) | >= 2.4.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | 2.9.0 |
| <a name="provider_nutanix"></a> [nutanix](#provider\_nutanix) | 2.4.2 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [local_sensitive_file.certificate_bundle](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [nutanix_object_store_certificate_v2.certificate](https://registry.terraform.io/providers/nutanix/nutanix/latest/docs/resources/object_store_certificate_v2) | resource |
| [nutanix_object_store_v2.object_store](https://registry.terraform.io/providers/nutanix/nutanix/latest/docs/resources/object_store_v2) | resource |
| [nutanix_clusters_v2.clusters](https://registry.terraform.io/providers/nutanix/nutanix/latest/docs/data-sources/clusters_v2) | data source |
| [nutanix_object_store_v2.by_ext_id](https://registry.terraform.io/providers/nutanix/nutanix/latest/docs/data-sources/object_store_v2) | data source |
| [nutanix_object_stores_v2.existing](https://registry.terraform.io/providers/nutanix/nutanix/latest/docs/data-sources/object_stores_v2) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_certificate_output_dir"></a> [certificate\_output\_dir](#input\_certificate\_output\_dir) | Directory where inline certificate JSON bundles are written. Defaults to '<root>/.object\_store\_certificates'. | `string` | `null` | no |
| <a name="input_lookup_existing_object_stores"></a> [lookup\_existing\_object\_stores](#input\_lookup\_existing\_object\_stores) | When true, query all existing object stores (nutanix\_object\_stores\_v2) and expose them via the 'existing\_object\_stores' output. | `bool` | `false` | no |
| <a name="input_object_store_certificate_bundles"></a> [object\_store\_certificate\_bundles](#input\_object\_store\_certificate\_bundles) | SENSITIVE map (cert key => raw JSON certificate bundle) rendered to disk for certificates that do not supply an existing 'path'. The only supported channel for private key material. | `map(string)` | `{}` | no |
| <a name="input_object_store_certificates"></a> [object\_store\_certificates](#input\_object\_store\_certificates) | TLS certificates to attach to object stores (nutanix\_object\_store\_certificate\_v2), keyed by a logical name. | <pre>map(object({<br/>    object_store_key = string                 # Key into var.object_stores this certificate belongs to.<br/>    path             = optional(string, null) # Path to an existing JSON certificate bundle. When null, the bundle is rendered from var.object_store_certificate_bundles[<key>].<br/>  }))</pre> | `{}` | no |
| <a name="input_object_store_create_timeout"></a> [object\_store\_create\_timeout](#input\_object\_store\_create\_timeout) | Default create timeout for nutanix\_object\_store\_v2 when a store does not set timeouts.create. Object-store deployment is long running; raise for real applies. | `string` | `"60m"` | no |
| <a name="input_object_store_lookup_ext_ids"></a> [object\_store\_lookup\_ext\_ids](#input\_object\_store\_lookup\_ext\_ids) | Map of logical name => object store ext\_id to look up individually (nutanix\_object\_store\_v2). Exposed via the 'looked\_up\_object\_stores' output. | `map(string)` | `{}` | no |
| <a name="input_object_stores"></a> [object\_stores](#input\_object\_stores) | Map of Nutanix Objects object stores to deploy/manage (nutanix\_object\_store\_v2), keyed by a logical name. | <pre>map(object({<br/>    # Identity<br/>    name        = string                 # Object store deployment name.<br/>    description = optional(string, null) # Free-form description.<br/><br/>    # Placement. Supply EITHER 'cluster' (name, resolved to ext_id via the<br/>    # nutanix_clusters_v2 data source) OR 'cluster_ext_id' directly.<br/>    cluster        = optional(string, null)<br/>    cluster_ext_id = optional(string, null)<br/><br/>    # Deployment sizing / addressing (all optional; null lets the provider<br/>    # compute a default where it supports one).<br/>    deployment_version = optional(string, null) # e.g. "5.1.1".<br/>    domain             = optional(string, null) # DNS (sub)domain, e.g. "objects-0.pc.example.com".<br/>    region             = optional(string, null) # Deployment region.<br/>    num_worker_nodes   = optional(number, null) # Worker VM count (each needs 10 vCPU / 32 GiB).<br/>    total_capacity_gib = optional(number, null) # Total capacity in GiB.<br/>    state              = optional(string, null) # e.g. "UNDEPLOYED_OBJECT_STORE" for a draft.<br/><br/>    # Networking. References are subnet UUIDs (AHV) or IPAM names (ESXi).<br/>    public_network_reference  = optional(string, null)<br/>    storage_network_reference = optional(string, null)<br/><br/>    # Static public network IPs (set of ipv4/ipv6 addresses).<br/>    public_network_ips = optional(list(object({<br/>      ipv4 = optional(object({<br/>        value         = string<br/>        prefix_length = optional(number, null)<br/>      }), null)<br/>      ipv6 = optional(object({<br/>        value         = string<br/>        prefix_length = optional(number, null)<br/>      }), null)<br/>    })), [])<br/><br/>    # Storage network virtual IP (single).<br/>    storage_network_vip = optional(object({<br/>      ipv4 = optional(object({ value = string, prefix_length = optional(number, null) }), null)<br/>      ipv6 = optional(object({ value = string, prefix_length = optional(number, null) }), null)<br/>    }), null)<br/><br/>    # Storage network DNS IP (single).<br/>    storage_network_dns_ip = optional(object({<br/>      ipv4 = optional(object({ value = string, prefix_length = optional(number, null) }), null)<br/>      ipv6 = optional(object({ value = string, prefix_length = optional(number, null) }), null)<br/>    }), null)<br/><br/>    # Ownership / category metadata (optional).<br/>    metadata = optional(object({<br/>      category_ids         = optional(list(string), null)<br/>      owner_reference_id   = optional(string, null)<br/>      project_reference_id = optional(string, null)<br/>    }), null)<br/><br/>    # Per-store create/update/delete timeouts. Object-store deployment<br/>    # provisions worker VMs and is long running; raise 'create' for real applies.<br/>    timeouts = optional(object({<br/>      create = optional(string, null)<br/>      update = optional(string, null)<br/>      delete = optional(string, null)<br/>    }), null)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_existing_object_stores"></a> [existing\_object\_stores](#output\_existing\_object\_stores) | Inventory of existing object stores from nutanix\_object\_stores\_v2 (empty unless lookup\_existing\_object\_stores = true). |
| <a name="output_looked_up_object_stores"></a> [looked\_up\_object\_stores](#output\_looked\_up\_object\_stores) | Individually looked-up object stores from nutanix\_object\_store\_v2, keyed as in object\_store\_lookup\_ext\_ids. |
| <a name="output_object_store_certificates"></a> [object\_store\_certificates](#output\_object\_store\_certificates) | Managed object-store TLS certificates keyed by input key. |
| <a name="output_object_store_ids"></a> [object\_store\_ids](#output\_object\_store\_ids) | Map of object store key => ext\_id. |
| <a name="output_object_stores"></a> [object\_stores](#output\_object\_stores) | Managed object stores keyed by input key (ext\_id, name, cluster, sizing, certificate ext\_ids). |
| <a name="output_objects_summary"></a> [objects\_summary](#output\_objects\_summary) | Plan-time summary of the requested object-store configuration. |
| <a name="output_outputs"></a> [outputs](#output\_outputs) | Aggregate of all module outputs. |
<!-- END_TF_DOCS -->
