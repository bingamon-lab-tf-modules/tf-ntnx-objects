##################################################
# Buckets (durable)
##################################################

# Buckets that must outlive the cluster: OpenTofu state, the Velero/DR target,
# the Harbor registry.
#
# This block exists SEPARATELY from the ephemeral one because 'prevent_destroy'
# is a meta-argument that cannot reference a variable — it must be a literal.
# So durability is a resource-block split over two filtered maps rather than an
# argument. force_destroy is likewise hardcoded false: a destroy that has to
# empty the bucket first is exactly what must not happen here.
resource "aws_s3_bucket" "durable" {
  for_each = local.durable_buckets

  bucket        = each.value.name
  force_destroy = false

  # S3 Object Lock can only be enabled at bucket creation and cannot be
  # retrofitted, so this is a create-time decision per bucket.
  object_lock_enabled = each.value.object_lock != null

  lifecycle {
    prevent_destroy = true
  }
}

##################################################
# Buckets (ephemeral)
##################################################

# Buckets whose loss is an inconvenience rather than an incident. Identical to
# the durable block except for the two meta-arguments above.
resource "aws_s3_bucket" "ephemeral" {
  for_each = local.ephemeral_buckets

  bucket        = each.value.name
  force_destroy = each.value.force_destroy

  object_lock_enabled = each.value.object_lock != null
}

##################################################
# Versioning
##################################################

# Single-purpose resource rather than the aggregate bucket's inline block. The
# aggregate does work against Objects (all eleven of its sub-resource reads
# tolerate NotImplemented / MethodNotAllowed / XNotImplemented) but issues
# eleven reads per bucket per plan, most of which return 501 here.
resource "aws_s3_bucket_versioning" "bucket" {
  for_each = local.versioned_buckets

  bucket = local.bucket_resources[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

##################################################
# Bucket policies
##################################################

# Either the document compiled from the curated 'access' block, or the raw
# 'policy_json' escape hatch. Setting both is rejected at plan.
resource "aws_s3_bucket_policy" "bucket" {
  for_each = local.bucket_policies

  bucket = local.bucket_resources[each.key].id
  policy = each.value

  # A policy that denies the caller can lock the bucket out of further
  # management, so it is applied after versioning and Object Lock are in place.
  depends_on = [
    aws_s3_bucket_versioning.bucket,
    aws_s3_bucket_object_lock_configuration.bucket,
  ]
}

##################################################
# Lifecycle rules
##################################################

resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  for_each = local.lifecycle_buckets

  bucket = local.bucket_resources[each.key].id

  dynamic "rule" {
    for_each = { for r in each.value.lifecycle_rules : r.id => r }
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = coalesce(rule.value.prefix, "")
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [rule.value.noncurrent_version_expiration_days] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [rule.value.abort_incomplete_multipart_upload_days] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.bucket]
}

##################################################
# Object Lock (WORM) default retention
##################################################

# Objects supports PUT/GET Bucket Object Lock Configuration, Object Retention
# and Object Legal Hold, but COMPLIANCE mode only — GOVERNANCE is rejected at
# plan in variables.tf rather than left to fail mid-apply. Written only when a
# default retention is specified; 'object_lock' without one merely enables the
# feature at creation so clients can set per-object retention.
resource "aws_s3_bucket_object_lock_configuration" "bucket" {
  for_each = local.object_lock_buckets

  bucket              = local.bucket_resources[each.key].id
  object_lock_enabled = "Enabled"

  rule {
    default_retention {
      mode  = each.value.object_lock.mode
      days  = each.value.object_lock.retention_days
      years = each.value.object_lock.retention_years
    }
  }

  # Object Lock requires versioning; the variable validation enforces the
  # declaration, this enforces the ordering.
  depends_on = [aws_s3_bucket_versioning.bucket]
}
