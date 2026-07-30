# tf-ntnx-objects — buckets

## Table of Contents

## Overview

Manages **buckets** on a Nutanix Objects object store over the **S3 API**, wrapping
`hashicorp/aws`'s single-purpose `aws_s3_*` resources.

This is the second of two entry points in this repository, and it declares **only**
the `aws` provider. [`../../module`](../../module/README.md) is the first, declares
only `nutanix`, and manages the object store itself. They are separate entry points
rather than one module behind a flag so that neither consumer is forced to hold the
other's credential: the deploy-only consumer has no S3 access key to give, and the
bucket consumer has no reason to hold Prism Central credentials.

Provider 2.4.2 registers **no** bucket, policy, lifecycle or WORM resource — the
vendor's own example carries the note _"we are not supporting delete bucket API in
terraform"_ — and Objects offers no non-S3 bucket API: v5.3 states buckets are
managed _"by using Prism Central or the S3-compatible REST APIs"_ and nothing else.
So the bucket layer is `hashicorp/aws` pointed at the Objects endpoint.

## Configuring the provider

This module does **not** configure the `aws` provider; its caller does, and passes
it in. Against an Objects endpoint the provider needs all of the following:

| Argument                      | Value                      | Why                                                                                                          |
| ----------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `endpoints { s3 = ... }`      | the store's S3 URL         | The whole point.                                                                                             |
| `s3_use_path_style`           | `true`                     | **Required.** `<endpoint>/<bucket>`, not `<bucket>.<endpoint>` — so DNS needs one name, not a wildcard zone. |
| `region`                      | anything, e.g. `us-east-1` | The provider demands a region; Objects has none, and it is never used meaningfully.                          |
| `skip_credentials_validation` | `true`                     | There is no STS to call.                                                                                     |
| `skip_requesting_account_id`  | `true`                     | There is no AWS account.                                                                                     |
| `skip_metadata_api_check`     | `true`                     | There is no EC2 instance metadata service.                                                                   |
| `skip_region_validation`      | `true`                     | The arbitrary region above is not a real AWS region.                                                         |

Virtual-hosted-style addressing is deliberately **out of scope** — there is no
variable for it. Path-style is pinned by ADR 0023 because the AD-managed production
site will not grant a wildcard record in the main zone.

## One module instance per store

One `aws` provider instance addresses one S3 endpoint, so this module is
instantiated once per object store. Each instance is handed the **whole** `buckets`
map and manages only the entries whose `store` matches its `store` argument:

```hcl
provider "aws" {
  alias    = "objects"
  for_each = var.object_store_endpoints
  # ... the arguments above, with endpoints { s3 = each.value }
}

module "buckets" {
  source    = "git::ssh://git@github.com/bingamon-lab-tf-modules/tf-ntnx-objects.git//modules/buckets?ref=v0.1.0"
  for_each  = var.object_store_endpoints
  providers = { aws = aws.objects[each.key] }

  store   = each.key
  buckets = var.buckets
}
```

Leaving `store` null disables the filter and manages every entry, which is only
correct for a single-store deployment. See
[`../../examples/example.tf`](../../examples/example.tf) for both entry points wired
together.

## Things worth knowing before first use

- **`durable` is two resource blocks, not an argument.** `prevent_destroy` is a
  meta-argument that cannot reference a variable — it must be a literal. So durable
  buckets are rendered by `aws_s3_bucket.durable`, which hardcodes
  `prevent_destroy = true` and `force_destroy = false`, and ephemeral ones by
  `aws_s3_bucket.ephemeral`, which carries neither. Durable means "must outlive the
  cluster": the OpenTofu state bucket, the Velero/DR target, the Harbor registry.
  Losing Harbor's bucket means re-mirroring a registry inside an air gap.
  Consequently **`tofu destroy` can never fully tear down an environment**, by
  design. Flipping `durable` from true to false is a config change, not a state
  change — it moves the bucket between resource addresses, so it needs a
  `tofu state mv` (or a `moved` block) rather than a destroy/recreate.

- **Bucket names are immutable and DNS-shaped.** 3–63 characters, lowercase letters,
  digits, dots and hyphens, beginning and ending with a letter or digit. No
  uppercase, no underscores. Nutanix documents a 64-character ceiling, but
  `hashicorp/aws` enforces the AWS S3 limit of 63 and rejects 64 with a message that
  explains nothing, so this module refuses 64 with the reason. Changing `name`
  destroys and recreates — which a durable bucket refuses outright.

- **Policies are either curated or raw, never both.** `access = { read, write }`
  compiles to an S3 policy document; `policy_json` takes a raw one for anything the
  abstraction cannot express. Setting both on one bucket fails at plan.

- **A wildcard principal needs `allow_public = true`.** A `Principal` of `"*"` —
  spelled `"*"`, `{"AWS": "*"}` or `{"AWS": ["*"]}`, in either `access` or
  `policy_json` — fails the plan unless the bucket explicitly opts in. An
  accidentally world-readable bucket must not be a typo.

- **WORM is COMPLIANCE-only, versioned, and create-time.** Objects supports
  `PUT`/`GET Bucket Object Lock Configuration`, `PUT`/`GET Object Retention` and
  `PUT`/`GET Object Legal Hold`, but has **no GOVERNANCE mode** — a `GOVERNANCE`
  config is rejected at plan rather than left to fail mid-apply. Object Lock requires
  versioning and can only be enabled **at bucket creation**; it cannot be
  retrofitted, so adding it to an existing bucket means destroying and recreating.
  COMPLIANCE retention is genuinely irreversible — nobody, including the storage
  admin, can delete an object before it expires — hence
  `object_lock.acknowledge_irreversible`, which must be set true explicitly.

- **Single-purpose resources, not the aggregate `aws_s3_bucket`.** The aggregate does
  work against Objects: all eleven of its sub-resource reads tolerate
  `NotImplemented` / `MethodNotAllowed` / `XNotImplemented`, and the only two
  intolerant calls (`HeadBucket`, `GetBucketLocation`) are both supported. This is a
  cost decision, not a correctness one — the aggregate issues eleven reads per bucket
  per plan, most of which return 501 here.

- **Objects implements none of** `GET/PUT Bucket accelerate|acl|encryption|logging|`
  `requestPayment|analytics|inventory|metrics` **nor** `GET/PUT Object ACL`, so this
  module exposes no variables for them.

- **Not in scope, deliberately:** federated namespace, streaming replication and NFS
  multi-protocol buckets. These have no Terraform surface at all.

- **`use_lockfile` on a state bucket must be `false`.** Objects accepts
  `If-None-Match` on `PUT Object` but validates the condition only at the start and
  end of an upload, so it is not a compare-and-swap and two concurrent applies can
  both acquire the "lock". That is worse than no lock, because it looks safe.

<!-- terraform-docs generated below; its input tables are wide by construction. -->
<!-- markdownlint-disable MD013 MD033 MD049 MD060 -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.100.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.57.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_s3_bucket.durable](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.ephemeral](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_object_lock_configuration.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_object_lock_configuration) | resource |
| [aws_s3_bucket_policy.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_versioning.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_buckets"></a> [buckets](#input\_buckets) | Map of buckets to manage on the Objects S3 endpoint, keyed by a logical name. Entries whose 'store' does not match var.store are ignored. | <pre>map(object({<br/>    # Which object store this bucket belongs to. Matched against var.store.<br/>    store = string<br/><br/>    # The S3 bucket name. Immutable after creation.<br/>    name = string<br/><br/>    # Does this bucket have to outlive the cluster? true renders it through a<br/>    # resource block carrying a LITERAL prevent_destroy = true and<br/>    # force_destroy = false. OpenTofu state, the Velero/DR target and the<br/>    # Harbor registry are durable; re-mirroring a registry inside an air gap is<br/>    # the expensive failure this flag exists to prevent. No default — the<br/>    # caller must decide per bucket.<br/>    durable = bool<br/><br/>    # Only honoured for ephemeral buckets. A durable bucket is always<br/>    # force_destroy = false; setting this true alongside durable = true is<br/>    # rejected rather than silently ignored.<br/>    force_destroy = optional(bool, false)<br/><br/>    # S3 object versioning. Required (and forced) when object_lock is set.<br/>    versioning = optional(bool, false)<br/><br/>    # Lifecycle rules. Each rule needs an id and at least one action.<br/>    lifecycle_rules = optional(list(object({<br/>      id      = string<br/>      enabled = optional(bool, true)<br/>      prefix  = optional(string, null)<br/><br/>      # Expire current object versions this many days after creation.<br/>      expiration_days = optional(number, null)<br/><br/>      # Expire non-current versions this many days after they become<br/>      # non-current. Only meaningful on a versioned bucket.<br/>      noncurrent_version_expiration_days = optional(number, null)<br/><br/>      # Abort incomplete multipart uploads after this many days.<br/>      abort_incomplete_multipart_upload_days = optional(number, null)<br/>    })), [])<br/><br/>    # Curated access grants, compiled into an S3 policy document. Principals<br/>    # are S3 principal strings: an ARN, a user name as Objects presents it, or<br/>    # the wildcard (which requires allow_public). Mutually exclusive with<br/>    # policy_json.<br/>    access = optional(object({<br/>      read  = optional(list(string), [])<br/>      write = optional(list(string), [])<br/>    }), null)<br/><br/>    # Escape hatch for anything the curated 'access' block cannot express. A<br/>    # raw S3 policy document. Mutually exclusive with 'access'.<br/>    policy_json = optional(string, null)<br/><br/>    # Explicit acknowledgement that a wildcard principal is intended. Without<br/>    # it, a wildcard Principal — reachable from either 'access' or 'policy_json'<br/>    # — fails the plan. A world-readable bucket must not be a typo.<br/>    allow_public = optional(bool, false)<br/><br/>    # S3 Object Lock (WORM). Objects supports PUT/GET Bucket Object Lock<br/>    # Configuration, Object Retention and Object Legal Hold, but:<br/>    #<br/>    #   - COMPLIANCE mode ONLY. Objects has no governance mode, so GOVERNANCE<br/>    #     is rejected here rather than failing halfway through an apply.<br/>    #   - versioning is mandatory.<br/>    #   - it must be enabled AT BUCKET CREATION and cannot be retrofitted;<br/>    #     adding this to an existing bucket means destroying and recreating it.<br/>    #<br/>    # COMPLIANCE retention is genuinely irreversible: no one, including the<br/>    # storage admin, can delete an object before its retention expires. Hence<br/>    # acknowledge_irreversible, which must be set true explicitly.<br/>    object_lock = optional(object({<br/>      mode                     = optional(string, "COMPLIANCE")<br/>      retention_days           = optional(number, null)<br/>      retention_years          = optional(number, null)<br/>      acknowledge_irreversible = optional(bool, false)<br/>    }), null)<br/>  }))</pre> | `{}` | no |
| <a name="input_store"></a> [store](#input\_store) | Key of the object store this module instance manages buckets for. Only var.buckets entries whose 'store' matches are managed. Null manages every entry (single-store deployments only). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bucket_arns"></a> [bucket\_arns](#output\_bucket\_arns) | Map of bucket key => S3 bucket ARN, of the form 'arn:aws:s3:::BUCKET-NAME'. Known at plan time so consumers can build policies referencing these buckets. |
| <a name="output_bucket_names"></a> [bucket\_names](#output\_bucket\_names) | Map of bucket key => S3 bucket name. Known at plan time so consumers can build policies and app config without waiting on an apply. |
| <a name="output_bucket_policies"></a> [bucket\_policies](#output\_bucket\_policies) | Map of bucket key => effective bucket policy document, whether compiled from 'access' or supplied via 'policy\_json'. |
| <a name="output_buckets"></a> [buckets](#output\_buckets) | Managed buckets keyed by input key (store, name, arn, id, durability, versioning, object lock, policy source). |
| <a name="output_buckets_summary"></a> [buckets\_summary](#output\_buckets\_summary) | Plan-time summary of the requested bucket configuration for this store. |
| <a name="output_outputs"></a> [outputs](#output\_outputs) | Aggregate of all module outputs. |
<!-- END_TF_DOCS -->
