# tf-ntnx-objects

## Overview

Terraform/OpenTofu modules for managing **Nutanix Objects** (NUS) end to end — the
object store on Prism Central, and the buckets on its S3 endpoint.

There are **two entry points**, not one module behind a flag. Each declares exactly
one provider, so neither consumer is forced to hold a credential it has no business
holding: the deploy-only consumer has no S3 access key, and the bucket consumer has
no reason to hold Prism Central credentials.

| Entry point                                     | Provider           | Manages                                                                                               |
| ----------------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------- |
| [`module/`](module/README.md)                   | `nutanix` **only** | `nutanix_object_store_v2`, `nutanix_object_store_certificate_v2` — the store and its TLS certificate. |
| [`modules/buckets/`](modules/buckets/README.md) | `aws` **only**     | Buckets, versioning, lifecycle rules, policies and S3 Object Lock (WORM) over the store's S3 API.     |

The boundary between them is **lifetime, not location**: buckets that must outlive
the cluster (OpenTofu state, the Velero/DR target, the Harbor registry) are Terraform
here, marked `durable: true`; buckets whose lifetime _is_ a cluster's belong to COSI
in-cluster. Each entry point's README documents its own variables, outputs and traps.
[`examples/example.tf`](examples/example.tf) wires both together, with the `aws`
provider `for_each`'d over the object stores.

## Capability boundary

Provider `>= 2.4.2` exposes object store and object-store-certificate resources
only, so this module is **store level**. But the boundary is narrower than "no S3
management at all" — be precise about what is and is not available:

| Concern                                    | Available?                                                               |
| ------------------------------------------ | ------------------------------------------------------------------------ |
| Object store + TLS certificate             | **Yes** — this module                                                    |
| S3 access keys (access key + secret pair)  | **Yes**, but elsewhere — `nutanix_user_key_v2`, wrapped by `tf-ntnx-iam` |
| Buckets, bucket policies, lifecycle, WORM  | **No Nutanix resource exists.** Use the S3 API — `modules/buckets/`      |
| Federated namespace, streaming replication | **No** — UI only                                                         |

**Access keys are not missing.** Provider 2.4.2 ships `nutanix_user_key_v2` with
`key_type = "OBJECT_KEY"`, which returns
`key_details.object_key_details.{access_key, secret_key}` — marked sensitive and
persisted on create as of 2.4.2 (issue #1112). `tf-ntnx-iam` already wraps it via
its `user_keys` variable, so use that rather than adding an IAM surface here.

Note this means an S3 secret lands in OpenTofu state whenever a key is minted by
Terraform. Sensitive-in-state is still in state; generating keys in the Objects UI
and storing them under SOPS avoids it.

**Buckets genuinely have no Nutanix resource.** The vendor's own example says so —
"we are not supporting delete bucket API in terraform" — and Objects offers no
non-S3 bucket API: v5.3 states buckets are managed "by using Prism Central or the
S3-compatible REST APIs". The S3 plane therefore belongs to an S3 client, which is
what [`modules/buckets/`](modules/buckets/README.md) is: `hashicorp/aws` with an
endpoint override, path-style addressing, and single-purpose `aws_s3_*` resources
rather than the aggregate `aws_s3_bucket`.

**WORM _is_ expressible**, contrary to a first reading of the vendor docs. "You
cannot enable the WORM policy while creating a bucket" describes the Objects **UI**
workflow; the S3 Object Lock API is separately supported. Objects implements
COMPLIANCE mode only, requires versioning, and requires Object Lock be enabled at
bucket creation — all three enforced at plan time by `modules/buckets/`.

## Operational notes

Things that are easy to discover the hard way:

- **`name` is capped at 16 characters**, must begin with a letter, end with a
  letter or number, and contain only letters, digits and hyphens. Validated by
  this module so it fails at plan with the reason.
- **`total_capacity_gib`'s unit is unconfirmed.** The name and docs say GiB; the
  vendor's own examples and the provider's acceptance tests imply **bytes**. See
  the comment on the variable. Being wrong here is a factor of 2^30.
- **Update cannot change anything.** The provider documents that update "does not
  allow modification of any configuration parameters (including `name` and
  `description`)" and exists solely to resume a deployment stuck in
  `OBJECT_STORE_DEPLOYMENT_FAILED`. So capacity, worker count and the public IP
  set are **not** expressible as a Terraform diff — changing them means destroying
  and recreating a store that has data in it. Scale-out is an out-of-band
  operation.
- **Deployment takes ≥30 minutes** and leaves debris behind: a
  `predeployment_port_vm` image plus `predeployment_objects_public` and
  `predeployment_objects_storage` VMs. Teardown must expect them.
- **Delete all buckets before destroying a store.** The provider cannot do it for
  you, so a store with buckets in it will fail to delete.
- **The certificate takes a file path, not inline PEMs.** `path` points at a JSON
  bundle containing `publicCert`, `privateKey`, `ca`, `alternateFqdns`,
  `alternateIps` and `shouldGenerate`. Supply `object_store_certificate_bundles`
  to have the module render that file at `0600` for you.
