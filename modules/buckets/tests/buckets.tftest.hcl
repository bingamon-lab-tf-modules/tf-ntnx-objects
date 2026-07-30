##################################################
# Unit Tests: Buckets (Objects S3 endpoint)
##################################################

#########################
# Mock Data (AWS Provider)
#########################

# The module is handed an already-configured aws provider by its caller, so the
# tests only need to stand one in. Nothing here talks to an endpoint.
mock_provider "aws" {}

#########################
# Shared defaults
#########################

variables {
  buckets = {
    state = {
      store   = "lab"
      name    = "lab-tofu-state"
      durable = true
    }
  }
}

#########################
# Tests: happy paths
#########################

# Test 1: A minimal valid bucket plans cleanly and is summarised.
run "valid_minimal_bucket" {
  command = plan

  assert {
    condition     = output.buckets_summary.bucket_count == 1
    error_message = "Expected exactly one bucket"
  }

  assert {
    condition     = output.buckets_summary.durable_count == 1
    error_message = "Expected the bucket to be counted as durable"
  }

  assert {
    condition     = output.bucket_names["state"] == "lab-tofu-state"
    error_message = "Expected the wire bucket name to be exposed at plan time"
  }

  assert {
    condition     = output.bucket_arns["state"] == "arn:aws:s3:::lab-tofu-state"
    error_message = "Expected a plan-time S3 ARN so consumers can build policies"
  }
}

# Test 2: An empty configuration plans zero buckets.
run "empty_config" {
  command = plan

  variables {
    buckets = {}
  }

  assert {
    condition     = output.buckets_summary.bucket_count == 0
    error_message = "Expected zero buckets for an empty map"
  }
}

# Test 3: A durable and an ephemeral bucket both plan, through their two
# separate resource blocks.
run "durable_and_ephemeral" {
  command = plan

  variables {
    buckets = {
      state = {
        store   = "lab"
        name    = "lab-tofu-state"
        durable = true
      }
      scratch = {
        store         = "lab"
        name          = "lab-scratch"
        durable       = false
        force_destroy = true
      }
    }
  }

  assert {
    condition     = output.buckets_summary.durable_count == 1
    error_message = "Expected one durable bucket"
  }

  assert {
    condition     = output.buckets_summary.ephemeral_count == 1
    error_message = "Expected one ephemeral bucket"
  }
}

# Test 4: 'store' selects which buckets an instance manages, so every instance
# can be handed the whole map.
run "store_filter" {
  command = plan

  variables {
    store = "lab"
    buckets = {
      here = {
        store   = "lab"
        name    = "lab-data"
        durable = false
      }
      elsewhere = {
        store   = "dr"
        name    = "dr-data"
        durable = false
      }
    }
  }

  assert {
    condition     = output.buckets_summary.bucket_count == 1
    error_message = "Expected only the bucket bound to store 'lab'"
  }

  assert {
    condition     = output.buckets_summary.unmanaged_by_store == 1
    error_message = "Expected the other store's bucket to be reported as unmanaged here"
  }
}

#########################
# Tests: bucket naming
#########################

# Test 5: Uppercase is rejected — Objects bucket names are DNS names.
run "invalid_name_uppercase" {
  command = plan

  variables {
    buckets = {
      bad = {
        store   = "lab"
        name    = "Lab-State"
        durable = false
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 6: Two characters is rejected — the floor is three.
run "invalid_name_too_short" {
  command = plan

  variables {
    buckets = {
      bad = {
        store   = "lab"
        name    = "ab"
        durable = false
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 7: An underscore is rejected. Reusing a snake_case map key as the bucket
# name is the obvious mistake.
run "invalid_name_underscore" {
  command = plan

  variables {
    buckets = {
      bad = {
        store   = "lab"
        name    = "lab_state"
        durable = false
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 8: A leading hyphen is rejected — must begin with a lowercase letter or
# digit.
run "invalid_name_leading_hyphen" {
  command = plan

  variables {
    buckets = {
      bad = {
        store   = "lab"
        name    = "-lab-state"
        durable = false
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 9: 63 characters is accepted — the effective inclusive upper bound
# (hashicorp/aws caps 'bucket' at 63, below the vendor's documented 64).
run "valid_name_at_upper_bound" {
  command = plan

  variables {
    buckets = {
      edge = {
        store   = "lab"
        name    = "a23456789012345678901234567890123456789012345678901234567890123" # 63
        durable = false
      }
    }
  }

  assert {
    condition     = output.buckets_summary.bucket_count == 1
    error_message = "64 characters is the inclusive upper bound and must plan"
  }
}

# Test 9a: 64 characters is rejected — reachable per the vendor, but not
# through hashicorp/aws, so it is refused here with the reason.
run "invalid_name_over_limit" {
  command = plan

  variables {
    buckets = {
      edge = {
        store   = "lab"
        name    = "a234567890123456789012345678901234567890123456789012345678901234" # 64
        durable = false
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 9b: Three characters is accepted — the inclusive lower bound.
run "valid_name_at_lower_bound" {
  command = plan

  variables {
    buckets = {
      edge = {
        store   = "lab"
        name    = "abc"
        durable = false
      }
    }
  }

  assert {
    condition     = output.buckets_summary.bucket_count == 1
    error_message = "A three-character name is valid and must plan"
  }
}

# Test 10: An empty DNS label ('..') is rejected even though every character is
# individually legal.
run "invalid_name_empty_label" {
  command = plan

  variables {
    buckets = {
      bad = {
        store   = "lab"
        name    = "lab..state"
        durable = false
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 10a: An empty 'store' is rejected — it would silently match no instance
# and the bucket would never be created anywhere.
run "invalid_empty_store" {
  command = plan

  variables {
    buckets = {
      bad = {
        store   = ""
        name    = "lab-state"
        durable = false
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 11: Two buckets naming the same bucket on the same store is rejected.
run "duplicate_name_same_store" {
  command = plan

  variables {
    buckets = {
      a = {
        store   = "lab"
        name    = "lab-state"
        durable = false
      }
      b = {
        store   = "lab"
        name    = "lab-state"
        durable = false
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 11a: The same name on DIFFERENT stores is legitimate.
run "duplicate_name_different_stores" {
  command = plan

  variables {
    buckets = {
      a = {
        store   = "lab"
        name    = "tofu-state"
        durable = false
      }
      b = {
        store   = "dr"
        name    = "tofu-state"
        durable = false
      }
    }
  }

  assert {
    condition     = output.buckets_summary.bucket_count == 2
    error_message = "The same bucket name on two different stores must plan"
  }
}

#########################
# Tests: durability
#########################

# Test 12: 'durable' and 'force_destroy' together is rejected rather than
# silently ignored — the durable block hardcodes force_destroy = false.
run "durable_force_destroy_conflict" {
  command = plan

  variables {
    buckets = {
      bad = {
        store         = "lab"
        name          = "lab-state"
        durable       = true
        force_destroy = true
      }
    }
  }

  expect_failures = [var.buckets]
}

#########################
# Tests: policies
#########################

# Test 13: Setting both 'access' and 'policy_json' on one bucket is rejected.
run "access_and_policy_json_conflict" {
  command = plan

  variables {
    buckets = {
      bad = {
        store       = "lab"
        name        = "lab-data"
        durable     = false
        access      = { read = ["arn:aws:iam::123456789012:user/reader"] }
        policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 14: A curated grant to "*" without allow_public is rejected. This is the
# accidentally-world-readable-bucket footgun, found in the prior research report.
run "public_access_without_acknowledgement" {
  command = plan

  variables {
    buckets = {
      bad = {
        store   = "lab"
        name    = "lab-data"
        durable = false
        access  = { read = ["*"] }
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 14a: The same grant WITH allow_public plans, and compiles to a wildcard
# principal.
run "public_access_with_acknowledgement" {
  command = plan

  variables {
    buckets = {
      public = {
        store        = "lab"
        name         = "lab-data"
        durable      = false
        access       = { read = ["*"] }
        allow_public = true
      }
    }
  }

  assert {
    condition     = output.buckets_summary.policy_count == 1
    error_message = "Expected a compiled policy"
  }

  assert {
    condition     = strcontains(output.bucket_policies["public"], "\"Principal\":\"*\"")
    error_message = "An acknowledged wildcard grant must compile to a scalar wildcard principal"
  }
}

# Test 15: A raw 'policy_json' with a scalar Principal of "*" is rejected. The
# escape hatch is where the footgun was actually found, so it is checked too.
run "public_policy_json_scalar" {
  command = plan

  variables {
    buckets = {
      bad = {
        store       = "lab"
        name        = "lab-data"
        durable     = false
        policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::lab-data/*\"}]}"
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 15a: The {"AWS": "*"} spelling of the same thing is also rejected.
run "public_policy_json_aws_scalar" {
  command = plan

  variables {
    buckets = {
      bad = {
        store       = "lab"
        name        = "lab-data"
        durable     = false
        policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"*\"},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::lab-data/*\"}]}"
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 15b: And the {"AWS": ["*"]} list spelling.
run "public_policy_json_aws_list" {
  command = plan

  variables {
    buckets = {
      bad = {
        store       = "lab"
        name        = "lab-data"
        durable     = false
        policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":[\"*\"]},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::lab-data/*\"}]}"
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 15c: A single-object (not list) Statement is still inspected.
run "public_policy_json_single_statement" {
  command = plan

  variables {
    buckets = {
      bad = {
        store       = "lab"
        name        = "lab-data"
        durable     = false
        policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::lab-data/*\"}}"
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 15d: A named-principal 'policy_json' needs no acknowledgement and plans.
run "policy_json_named_principal" {
  command = plan

  variables {
    buckets = {
      data = {
        store       = "lab"
        name        = "lab-data"
        durable     = false
        policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:user/reader\"},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::lab-data/*\"}]}"
      }
    }
  }

  assert {
    condition     = output.buckets_summary.policy_count == 1
    error_message = "Expected the raw policy to be used verbatim"
  }

  assert {
    condition     = output.buckets["data"].policy_source == "policy_json"
    error_message = "Expected the policy source to be reported as the escape hatch"
  }
}

# Test 16: Malformed JSON in the escape hatch fails at plan, not mid-apply.
run "policy_json_not_json" {
  command = plan

  variables {
    buckets = {
      bad = {
        store       = "lab"
        name        = "lab-data"
        durable     = false
        policy_json = "not json at all"
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 17: The curated compiler emits bucket-level and object-level statements
# against the right ARNs.
run "compiled_access_policy" {
  command = plan

  variables {
    buckets = {
      data = {
        store   = "lab"
        name    = "lab-data"
        durable = false
        access = {
          read  = ["arn:aws:iam::123456789012:user/reader"]
          write = ["arn:aws:iam::123456789012:user/writer"]
        }
      }
    }
  }

  assert {
    condition     = strcontains(output.bucket_policies["data"], "\"arn:aws:s3:::lab-data\"")
    error_message = "Expected a bucket-level statement scoped to the bucket ARN"
  }

  assert {
    condition     = strcontains(output.bucket_policies["data"], "\"arn:aws:s3:::lab-data/*\"")
    error_message = "Expected an object-level statement scoped to the object ARN"
  }

  assert {
    condition     = strcontains(output.bucket_policies["data"], "s3:GetObject")
    error_message = "Expected the read grant to compile to s3:GetObject"
  }

  assert {
    condition     = strcontains(output.bucket_policies["data"], "s3:PutObject")
    error_message = "Expected the write grant to compile to s3:PutObject"
  }

  assert {
    condition     = !strcontains(output.bucket_policies["data"], "\"Principal\":\"*\"")
    error_message = "A named grant must not compile to a wildcard principal"
  }
}

#########################
# Tests: lifecycle rules
#########################

# Test 18: A lifecycle rule with no action is rejected — the provider would
# reject it mid-apply.
run "lifecycle_rule_without_action" {
  command = plan

  variables {
    buckets = {
      bad = {
        store           = "lab"
        name            = "lab-data"
        durable         = false
        lifecycle_rules = [{ id = "noop" }]
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 17a: A lifecycle rule with an empty id is rejected.
run "lifecycle_rule_empty_id" {
  command = plan

  variables {
    buckets = {
      bad = {
        store           = "lab"
        name            = "lab-data"
        durable         = false
        lifecycle_rules = [{ id = "  ", expiration_days = 30 }]
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 18a: A rule with a zero-day expiry is rejected.
run "lifecycle_rule_zero_days" {
  command = plan

  variables {
    buckets = {
      bad = {
        store           = "lab"
        name            = "lab-data"
        durable         = false
        lifecycle_rules = [{ id = "zero", expiration_days = 0 }]
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 18b: A real rule plans.
run "valid_lifecycle_rule" {
  command = plan

  variables {
    buckets = {
      logs = {
        store      = "lab"
        name       = "lab-logs"
        durable    = false
        versioning = true
        lifecycle_rules = [{
          id                                     = "expire-logs"
          prefix                                 = "audit/"
          expiration_days                        = 30
          noncurrent_version_expiration_days     = 7
          abort_incomplete_multipart_upload_days = 1
        }]
      }
    }
  }

  assert {
    condition     = output.buckets_summary.lifecycle_count == 1
    error_message = "Expected one bucket with lifecycle rules"
  }
}

#########################
# Tests: Object Lock (WORM)
#########################

# Test 19: GOVERNANCE mode is rejected at plan. Objects implements COMPLIANCE
# only, so leaving this to the apply means a half-created bucket.
run "object_lock_governance_rejected" {
  command = plan

  variables {
    buckets = {
      bad = {
        store      = "lab"
        name       = "lab-worm"
        durable    = true
        versioning = true
        object_lock = {
          mode                     = "GOVERNANCE"
          retention_days           = 30
          acknowledge_irreversible = true
        }
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 20: Object Lock without versioning is rejected — S3 requires versioning.
run "object_lock_without_versioning" {
  command = plan

  variables {
    buckets = {
      bad = {
        store      = "lab"
        name       = "lab-worm"
        durable    = true
        versioning = false
        object_lock = {
          retention_days           = 30
          acknowledge_irreversible = true
        }
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 21: Object Lock without the irreversibility acknowledgement is rejected.
# COMPLIANCE retention cannot be shortened or lifted by anyone.
run "object_lock_without_acknowledgement" {
  command = plan

  variables {
    buckets = {
      bad = {
        store      = "lab"
        name       = "lab-worm"
        durable    = true
        versioning = true
        object_lock = {
          retention_days = 30
        }
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 22: Days and years together is rejected.
run "object_lock_days_and_years" {
  command = plan

  variables {
    buckets = {
      bad = {
        store      = "lab"
        name       = "lab-worm"
        durable    = true
        versioning = true
        object_lock = {
          retention_days           = 30
          retention_years          = 1
          acknowledge_irreversible = true
        }
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 22a: A zero-day retention is rejected.
run "object_lock_zero_retention" {
  command = plan

  variables {
    buckets = {
      bad = {
        store      = "lab"
        name       = "lab-worm"
        durable    = true
        versioning = true
        object_lock = {
          retention_days           = 0
          acknowledge_irreversible = true
        }
      }
    }
  }

  expect_failures = [var.buckets]
}

# Test 23: A fully specified WORM bucket plans, and implies versioning.
run "valid_object_lock" {
  command = plan

  variables {
    buckets = {
      worm = {
        store      = "lab"
        name       = "lab-worm"
        durable    = true
        versioning = true
        object_lock = {
          mode                     = "COMPLIANCE"
          retention_years          = 7
          acknowledge_irreversible = true
        }
      }
    }
  }

  assert {
    condition     = output.buckets_summary.object_lock_count == 1
    error_message = "Expected one Object Lock configuration"
  }

  assert {
    condition     = output.buckets_summary.versioned_count == 1
    error_message = "Object Lock must imply versioning"
  }

  assert {
    condition     = output.buckets["worm"].object_lock
    error_message = "Expected the bucket to report Object Lock enabled"
  }
}
