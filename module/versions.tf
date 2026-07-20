terraform {

  required_version = ">= 1.10.0"

  required_providers {
    nutanix = {
      source  = "nutanix/nutanix"
      version = ">= 2.4.2"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }

}
