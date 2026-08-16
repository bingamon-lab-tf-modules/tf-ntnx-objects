terraform {

  required_version = ">= 1.10.0"

  # ONLY the aws provider. This entry point is the S3 data plane; the nutanix
  # provider is deliberately absent so a consumer that only deploys object
  # stores (../../module) is never forced to supply an S3 credential, and a
  # consumer that only manages buckets is never forced to supply Prism Central
  # credentials.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }

}
