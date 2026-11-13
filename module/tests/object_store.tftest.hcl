##################################################
# Unit Tests: Object stores
##################################################

#########################
# Provider
#########################

provider "nutanix" {
  username     = "dummy"
  password     = "dummy"
  endpoint     = "dummy.local"
  port         = 9440
  insecure     = true
  wait_timeout = 1
}

#########################
# Mock Data (Nutanix Provider)
#########################

mock_provider "nutanix" {

  # Cluster name -> ext_id lookup (used by the cluster-by-name path).
  mock_data "nutanix_clusters_v2" {
    defaults = {
      cluster_entities = [
        {
          ext_id                   = "00000000-0000-0000-0000-000000000000"
          name                     = "mock-cluster"
          backup_eligibility_score = 0
          categories               = []
          cluster_profile_ext_id   = ""
          container_name           = ""
          expand                   = ""
          inefficient_vm_count     = 0
          links                    = []
          network                  = []
          nodes                    = []
          tenant_id                = ""
          upgrade_status           = ""
          vm_count                 = 0
          config = [
            {
              authorized_public_key_list       = []
              build_info                       = []
              cluster_arch                     = ""
              cluster_function                 = ["AOS"]
              cluster_software_map             = []
              encryption_in_transit_status     = ""
              encryption_option                = []
              encryption_scope                 = []
              fault_tolerance_state            = []
              hypervisor_types                 = ["AHV"]
              incarnation_id                   = 0
              is_available                     = true
              is_lts                           = false
              is_password_remote_login_enabled = false
              is_remote_support_enabled        = false
              operation_mode                   = ""
              pulse_status                     = []
              redundancy_factor                = 2
              timezone                         = ""
            }
          ]
        }
      ]
    }
  }
}

#########################
# Mock Data (Local Provider)
#########################

mock_provider "local" {}

#########################
# Shared defaults
#########################

variables {
  object_stores = {
    lab = {
      name               = "lab-objects"
      description        = "S3-compatible store for backups"
      cluster_ext_id     = "11111111-1111-1111-1111-111111111111"
      num_worker_nodes   = 1
      total_capacity_gib = 20
      domain             = "objects-0.pc.example.com"
    }
  }
}

#########################
# Tests
#########################

# Test 1: A minimal valid store plans cleanly and is summarised.
run "valid_minimal_store" {
  command = plan

  assert {
    condition     = output.objects_summary.object_store_count == 1
    error_message = "Expected exactly one object store"
  }

  assert {
    condition     = output.objects_summary.certificate_count == 0
    error_message = "Expected zero certificates"
  }
}

# Test 2: An empty configuration plans zero object stores.
run "empty_config" {
  command = plan

  variables {
    object_stores = {}
  }

  assert {
    condition     = output.objects_summary.object_store_count == 0
    error_message = "Expected zero object stores for an empty map"
  }
}

# Test 3: An empty name is rejected.
run "invalid_empty_name" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name           = ""
        cluster_ext_id = "11111111-1111-1111-1111-111111111111"
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 3a: A 17-character name is rejected. The product caps store names at 16,
# and any scheme encoding environment plus role will breach it.
run "invalid_name_too_long" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name           = "seventeen-chars-x" # 17
        cluster_ext_id = "11111111-1111-1111-1111-111111111111"
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 3b: Exactly 16 characters is accepted — the boundary is inclusive.
run "valid_name_at_limit" {
  command = plan

  variables {
    object_stores = {
      edge = {
        name           = "sixteen-chars-ok" # 16
        cluster_ext_id = "11111111-1111-1111-1111-111111111111"
      }
    }
  }

  assert {
    condition     = output.objects_summary.object_store_count == 1
    error_message = "A 16-character name is valid and must plan"
  }
}

# Test 3c: An underscore is rejected. Reusing a snake_case map key as the store
# name is the obvious mistake, and the vendor allows only hyphens.
run "invalid_name_underscore" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name           = "lab_objects"
        cluster_ext_id = "11111111-1111-1111-1111-111111111111"
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 3d: A name starting with a digit is rejected — must begin with a letter.
run "invalid_name_leading_digit" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name           = "1objects"
        cluster_ext_id = "11111111-1111-1111-1111-111111111111"
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 3e: A trailing hyphen is rejected — must end with a letter or number.
run "invalid_name_trailing_hyphen" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name           = "objects-"
        cluster_ext_id = "11111111-1111-1111-1111-111111111111"
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 4: Setting both 'cluster' and 'cluster_ext_id' is rejected.
run "cluster_and_ext_id_conflict" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name           = "bad"
        cluster        = "mock-cluster"
        cluster_ext_id = "11111111-1111-1111-1111-111111111111"
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 5: Setting neither 'cluster' nor 'cluster_ext_id' is rejected.
run "cluster_missing" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name = "bad"
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 6: Zero worker nodes is rejected.
run "invalid_worker_nodes" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name             = "bad"
        cluster_ext_id   = "11111111-1111-1111-1111-111111111111"
        num_worker_nodes = 0
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 7: A non-FQDN domain is rejected.
run "invalid_domain" {
  command = plan

  variables {
    object_stores = {
      bad = {
        name           = "bad"
        cluster_ext_id = "11111111-1111-1111-1111-111111111111"
        domain         = "nodot"
      }
    }
  }

  expect_failures = [var.object_stores]
}

# Test 8: Resolving the cluster by name plans cleanly (exercises the data lookup).
run "cluster_by_name" {
  command = plan

  variables {
    object_stores = {
      lab = {
        name             = "lab-objects"
        cluster          = "mock-cluster"
        num_worker_nodes = 3
        domain           = "objects-0.pc.example.com"
      }
    }
  }

  assert {
    condition     = contains(output.objects_summary.clusters_referenced, "mock-cluster")
    error_message = "Expected the cluster name to be referenced"
  }
}

# Test 9: A certificate referencing a managed store (via 'path') plans cleanly.
run "certificate_with_path" {
  command = plan

  variables {
    object_store_certificates = {
      lab_cert = {
        object_store_key = "lab"
        path             = "/tmp/lab-cert-bundle.json"
      }
    }
  }

  assert {
    condition     = output.objects_summary.certificate_count == 1
    error_message = "Expected one certificate"
  }

  assert {
    condition     = output.objects_summary.rendered_certificate_count == 0
    error_message = "Expected zero rendered certificates when a path is supplied"
  }
}

# Test 10: An inline certificate bundle is scheduled for rendering.
run "certificate_inline_rendered" {
  command = plan

  variables {
    object_store_certificates = {
      lab_cert = {
        object_store_key = "lab"
      }
    }
    object_store_certificate_bundles = {
      lab_cert = "{\"publicCert\":\"x\",\"privateKey\":\"y\",\"ca\":\"z\"}"
    }
  }

  assert {
    condition     = output.objects_summary.rendered_certificate_count == 1
    error_message = "Expected one rendered certificate for an inline bundle"
  }
}

# Test 11: Populated v2.5.1 data lookups (existing stores list, single store by ext_id, cluster management_server.type string).
run "populated_data_lookups_v2_5_1" {
  command = plan

  override_data {
    target = data.nutanix_clusters_v2.clusters[0]
    values = {
      cluster_entities = [
        {
          ext_id                   = "00000000-0000-0000-0000-000000000000"
          name                     = "mock-cluster"
          backup_eligibility_score = 0
          categories               = []
          cluster_profile_ext_id   = ""
          container_name           = ""
          expand                   = ""
          inefficient_vm_count     = 0
          links                    = []
          nodes                    = []
          tenant_id                = ""
          upgrade_status           = ""
          vm_count                 = 0
          network = [
            {
              backplane                  = []
              external_address           = []
              external_data_services_ip  = []
              external_subnet            = ""
              fqdn                       = ""
              http_proxy_list            = []
              http_proxy_white_list      = []
              internal_subnet            = ""
              key_management_server_type = ""
              masquerading_ip            = []
              masquerading_port          = ""
              name_server_ip_list        = []
              nfs_subnet_white_list      = []
              ntp_server_ip_list         = []
              smtp_server                = []
              management_server = [
                {
                  ip             = []
                  is_drs_enabled = false
                  is_in_use      = true
                  is_registered  = true
                  type           = "VCENTER"
                }
              ]
            }
          ]
          config = [
            {
              authorized_public_key_list       = []
              build_info                       = []
              cluster_arch                     = ""
              cluster_function                 = ["AOS"]
              cluster_software_map             = []
              encryption_in_transit_status     = ""
              encryption_option                = []
              encryption_scope                 = []
              fault_tolerance_state            = []
              hypervisor_types                 = ["AHV"]
              incarnation_id                   = 0
              is_available                     = true
              is_lts                           = false
              is_password_remote_login_enabled = false
              is_remote_support_enabled        = false
              operation_mode                   = ""
              pulse_status                     = []
              redundancy_factor                = 2
              timezone                         = ""
            }
          ]
        }
      ]
    }
  }

  override_data {
    target = data.nutanix_object_stores_v2.existing[0]
    values = {
      object_stores = [
        {
          certificate_ext_ids       = ["33333333-3333-3333-3333-333333333333"]
          cluster_ext_id            = "00000000-0000-0000-0000-000000000000"
          creation_time             = "2026-01-01T00:00:00Z"
          deployment_version        = "5.1.1"
          description               = "Existing object store"
          domain                    = "objects-existing.pc.example.com"
          ext_id                    = "22222222-2222-2222-2222-222222222222"
          last_update_time          = "2026-01-01T00:00:00Z"
          links                     = []
          metadata                  = []
          name                      = "existing-store"
          num_worker_nodes          = 1
          public_network_ips        = []
          public_network_reference  = "57c4caf1-67e3-457e-8265-6d872f2a3135"
          region                    = "us-east-1"
          state                     = "OBJECT_STORE_AVAILABLE"
          storage_network_dns_ip    = []
          storage_network_reference = "57c4caf1-67e3-457e-8265-6d872f2a3135"
          storage_network_vip       = []
          tenant_id                 = ""
          total_capacity_gib        = 20
        }
      ]
    }
  }

  override_data {
    target = data.nutanix_object_store_v2.by_ext_id["existing_lab"]
    values = {
      certificate_ext_ids       = ["33333333-3333-3333-3333-333333333333"]
      cluster_ext_id            = "00000000-0000-0000-0000-000000000000"
      creation_time             = "2026-01-01T00:00:00Z"
      deployment_version        = "5.1.1"
      description               = "Existing object store"
      domain                    = "objects-existing.pc.example.com"
      last_update_time          = "2026-01-01T00:00:00Z"
      links                     = []
      metadata                  = []
      name                      = "existing-store"
      num_worker_nodes          = 1
      public_network_ips        = []
      public_network_reference  = "57c4caf1-67e3-457e-8265-6d872f2a3135"
      region                    = "us-east-1"
      state                     = "OBJECT_STORE_AVAILABLE"
      storage_network_dns_ip    = []
      storage_network_reference = "57c4caf1-67e3-457e-8265-6d872f2a3135"
      storage_network_vip       = []
      tenant_id                 = ""
      total_capacity_gib        = 20
    }
  }

  variables {
    lookup_existing_object_stores = true
    object_store_lookup_ext_ids = {
      existing_lab = "22222222-2222-2222-2222-222222222222"
    }
    object_stores = {
      lab = {
        name             = "lab-objects"
        cluster          = "mock-cluster"
        num_worker_nodes = 1
        domain           = "objects-0.pc.example.com"
      }
    }
  }

  assert {
    condition     = length(output.existing_object_stores) == 1 && output.existing_object_stores[0].name == "existing-store"
    error_message = "Expected existing_object_stores to return the populated v2.5.1 store"
  }

  assert {
    condition     = output.looked_up_object_stores["existing_lab"].state == "OBJECT_STORE_AVAILABLE"
    error_message = "Expected looked_up_object_stores to return the singular v2.5.1 lookup result"
  }

  assert {
    condition     = output.object_stores["lab"].cluster_ext_id == "00000000-0000-0000-0000-000000000000"
    error_message = "Expected cluster-by-name lookup to resolve mock-cluster ext_id"
  }
}
