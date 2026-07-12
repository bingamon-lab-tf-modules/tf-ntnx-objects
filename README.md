# tf-ntnx-objects

## Overview

A Terraform/OpenTofu module for managing **Nutanix Objects** (NUS) object stores
on Prism Central. It wraps:

- `nutanix_object_store_v2` — deploy/manage an object store (worker VMs + networking).
- `nutanix_object_store_certificate_v2` — attach a TLS certificate to an object store.

> **Capability boundary — store level only.** Provider `>= 2.4.2` exposes object
> store and object-store-certificate resources **only**. There are **no bucket,
> user, access-key, or IAM/access-policy resources** — S3-API-level management is
> out of scope for this module (and the provider). Manage buckets/users/policies
> via the Objects UI or the S3 API instead.

The [Terraform Module](module/README.md) documentation contains the available
variables and outputs.
