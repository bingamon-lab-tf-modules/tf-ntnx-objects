locals {

  ##################################################
  # Store filtering
  ##################################################

  # Buckets this module instance owns. One aws provider instance addresses one
  # Objects endpoint, so an instance manages only the buckets bound to its
  # store. A null var.store disables filtering (single-store deployments).
  managed_buckets = {
    for k, b in var.buckets : k => b
    if var.store == null || b.store == var.store
  }

  ##################################################
  # The durable / ephemeral split
  ##################################################

  # 'prevent_destroy' cannot reference a variable — it must be a literal — so
  # durability cannot be a per-instance argument on one resource block. It is
  # instead two blocks over two filtered maps: the durable block hardcodes
  # prevent_destroy = true and force_destroy = false, the ephemeral block
  # carries neither.
  durable_buckets = {
    for k, b in local.managed_buckets : k => b if b.durable
  }

  ephemeral_buckets = {
    for k, b in local.managed_buckets : k => b if !b.durable
  }

  # Both blocks unified, so every sub-resource below is a single block rather
  # than a durable/ephemeral pair.
  bucket_resources = merge(
    aws_s3_bucket.durable,
    aws_s3_bucket.ephemeral,
  )

  # Wire bucket names keyed by logical name. Derived from the INPUT rather than
  # the resource so it is known at plan time.
  bucket_names = { for k, b in local.managed_buckets : k => b.name }

  # Bucket ARNs, likewise derived from the input. Objects, like AWS S3, uses
  # the partition-less, region-less S3 ARN form.
  bucket_arns = { for k, b in local.managed_buckets : k => "arn:aws:s3:::${b.name}" }

  ##################################################
  # Sub-resource selections
  ##################################################

  # Versioning is set explicitly on every bucket that asks for it, and forced
  # on for Object Lock (which cannot work without it).
  versioned_buckets = {
    for k, b in local.managed_buckets : k => b if b.versioning || b.object_lock != null
  }

  lifecycle_buckets = {
    for k, b in local.managed_buckets : k => b if length(b.lifecycle_rules) > 0
  }

  # Object Lock configuration is only written when a default retention is
  # actually specified; 'object_lock' with no retention just turns the feature
  # on at creation (object_lock_enabled) so per-object retention can be set by
  # the client.
  object_lock_buckets = {
    for k, b in local.managed_buckets : k => b
    if b.object_lock != null && (b.object_lock.retention_days != null || b.object_lock.retention_years != null)
  }

  ##################################################
  # Policy compilation
  ##################################################

  # Curated grants -> S3 policy statements. Bucket-level and object-level
  # actions need different Resource ARNs, so each grant compiles to up to two
  # statements. A principal list containing "*" renders as the scalar wildcard
  # (only reachable with allow_public = true, enforced in variables.tf).
  policy_grants = {
    read = {
      bucket = ["s3:ListBucket", "s3:GetBucketLocation"]
      object = ["s3:GetObject", "s3:GetObjectVersion"]
    }
    write = {
      bucket = ["s3:ListBucket", "s3:ListBucketMultipartUploads"]
      object = ["s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    }
  }

  # Principals per grant kind, per bucket.
  access_principals = {
    for k, b in local.managed_buckets : k => {
      read  = b.access == null ? [] : distinct(coalesce(b.access.read, []))
      write = b.access == null ? [] : distinct(coalesce(b.access.write, []))
    }
  }

  # Statements are built in two passes rather than one, because a Principal is a
  # scalar "*" for a public grant and an object for a named one, and HCL's
  # conditional operator refuses two branches of different types. The public
  # pass emits the scalar wildcard (S3's anonymous principal); the named pass
  # emits {"AWS": [...]}.
  public_statements = {
    for k, b in local.managed_buckets : k => flatten([
      for kind in ["read", "write"] : [
        for scope in ["bucket", "object"] : {
          Sid       = "Public${title(kind)}${title(scope)}"
          Effect    = "Allow"
          Principal = "*"
          Action    = local.policy_grants[kind][scope]
          Resource  = scope == "bucket" ? [local.bucket_arns[k]] : ["${local.bucket_arns[k]}/*"]
        }
      ]
      if contains(local.access_principals[k][kind], "*")
    ])
  }

  named_statements = {
    for k, b in local.managed_buckets : k => flatten([
      for kind in ["read", "write"] : [
        for scope in ["bucket", "object"] : {
          Sid       = "${title(kind)}${title(scope)}"
          Effect    = "Allow"
          Principal = { AWS = [for p in local.access_principals[k][kind] : p if p != "*"] }
          Action    = local.policy_grants[kind][scope]
          Resource  = scope == "bucket" ? [local.bucket_arns[k]] : ["${local.bucket_arns[k]}/*"]
        }
      ]
      if length([for p in local.access_principals[k][kind] : p if p != "*"]) > 0
    ])
  }

  # The compiled document for every bucket carrying an 'access' block.
  compiled_policies = {
    for k, b in local.managed_buckets : k => jsonencode({
      Version   = "2012-10-17"
      Statement = concat(local.named_statements[k], local.public_statements[k])
    })
    if b.access != null && length(concat(local.access_principals[k].read, local.access_principals[k].write)) > 0
  }

  # Effective bucket policy per bucket: the compiled document, or the raw
  # escape hatch. Never both — variables.tf rejects that combination.
  bucket_policies = merge(
    local.compiled_policies,
    {
      for k, b in local.managed_buckets : k => b.policy_json
      if b.policy_json != null
    },
  )

  ##################################################
  # Output shapes (DRY between named + aggregate outputs)
  ##################################################

  buckets_out = {
    for k, b in local.managed_buckets : k => {
      store         = b.store
      name          = local.bucket_names[k]
      arn           = local.bucket_arns[k]
      id            = local.bucket_resources[k].id
      durable       = b.durable
      versioning    = contains(keys(local.versioned_buckets), k)
      object_lock   = b.object_lock != null
      policy_source = b.policy_json != null ? "policy_json" : (b.access != null ? "access" : "none")
    }
  }

  ##################################################
  # Plan-time summary
  ##################################################

  buckets_summary = {
    store              = var.store
    bucket_count       = length(local.managed_buckets)
    durable_count      = length(local.durable_buckets)
    ephemeral_count    = length(local.ephemeral_buckets)
    versioned_count    = length(local.versioned_buckets)
    lifecycle_count    = length(local.lifecycle_buckets)
    policy_count       = length(local.bucket_policies)
    object_lock_count  = length(local.object_lock_buckets)
    stores_referenced  = distinct([for k, b in local.managed_buckets : b.store])
    unmanaged_by_store = length(var.buckets) - length(local.managed_buckets)
  }
}
