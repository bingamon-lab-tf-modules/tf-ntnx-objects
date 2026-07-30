##################################################
# Bucket outputs
##################################################

output "buckets" {
  description = "Managed buckets keyed by input key (store, name, arn, id, durability, versioning, object lock, policy source)."
  value       = local.buckets_out
}

output "bucket_names" {
  description = "Map of bucket key => S3 bucket name. Known at plan time so consumers can build policies and app config without waiting on an apply."
  value       = local.bucket_names
}

output "bucket_arns" {
  description = "Map of bucket key => S3 bucket ARN, of the form 'arn:aws:s3:::BUCKET-NAME'. Known at plan time so consumers can build policies referencing these buckets."
  value       = local.bucket_arns
}

output "bucket_policies" {
  description = "Map of bucket key => effective bucket policy document, whether compiled from 'access' or supplied via 'policy_json'."
  value       = local.bucket_policies
}

##################################################
# Summary + aggregate
##################################################

output "buckets_summary" {
  description = "Plan-time summary of the requested bucket configuration for this store."
  value       = local.buckets_summary
}

# Single aggregate output exposing everything the module produces, matching the
# convention of the object-store entry point so the LZ -> root forwarding chain
# cannot silently drop an output.
output "outputs" {
  description = "Aggregate of all module outputs."
  value = {
    buckets         = local.buckets_out
    bucket_names    = local.bucket_names
    bucket_arns     = local.bucket_arns
    bucket_policies = local.bucket_policies
    buckets_summary = local.buckets_summary
  }
}
