##################################################
# Store selection
##################################################

# Which object store THIS module instance is bound to.
#
# The module receives ONE already-configured 'aws' provider, and one aws
# provider instance can only ever talk to one Objects S3 endpoint. So a
# multi-store estate instantiates this module once per store:
#
#   module "buckets" {
#     for_each  = var.object_stores
#     source    = ".../modules/buckets"
#     providers = { aws = aws.objects[each.key] }
#     store     = each.key
#     buckets   = var.buckets          # the WHOLE map; filtered by 'store'
#   }
#
# Every instance may therefore be handed the same, complete 'buckets' map: an
# instance manages only the entries whose 'store' matches. Leaving this null
# disables filtering and manages every entry, which is only correct for a
# single-store deployment.
variable "store" {
  description = "Key of the object store this module instance manages buckets for. Only var.buckets entries whose 'store' matches are managed. Null manages every entry (single-store deployments only)."
  type        = string
  default     = null
}

##################################################
# Buckets
##################################################

# Buckets to manage on an Objects store over the S3 API, keyed by a logical
# name. The key is a Terraform address, NOT the bucket name — 'name' is the
# wire name and is immutable (S3 has no rename; changing it destroys and
# recreates, which for a durable bucket is refused outright).
variable "buckets" {
  description = "Map of buckets to manage on the Objects S3 endpoint, keyed by a logical name. Entries whose 'store' does not match var.store are ignored."
  type = map(object({
    # Which object store this bucket belongs to. Matched against var.store.
    store = string

    # The S3 bucket name. Immutable after creation.
    name = string

    # Does this bucket have to outlive the cluster? true renders it through a
    # resource block carrying a LITERAL prevent_destroy = true and
    # force_destroy = false. OpenTofu state, the Velero/DR target and the
    # Harbor registry are durable; re-mirroring a registry inside an air gap is
    # the expensive failure this flag exists to prevent. No default — the
    # caller must decide per bucket.
    durable = bool

    # Only honoured for ephemeral buckets. A durable bucket is always
    # force_destroy = false; setting this true alongside durable = true is
    # rejected rather than silently ignored.
    force_destroy = optional(bool, false)

    # S3 object versioning. Required (and forced) when object_lock is set.
    versioning = optional(bool, false)

    # Lifecycle rules. Each rule needs an id and at least one action.
    lifecycle_rules = optional(list(object({
      id      = string
      enabled = optional(bool, true)
      prefix  = optional(string, null)

      # Expire current object versions this many days after creation.
      expiration_days = optional(number, null)

      # Expire non-current versions this many days after they become
      # non-current. Only meaningful on a versioned bucket.
      noncurrent_version_expiration_days = optional(number, null)

      # Abort incomplete multipart uploads after this many days.
      abort_incomplete_multipart_upload_days = optional(number, null)
    })), [])

    # Curated access grants, compiled into an S3 policy document. Principals
    # are S3 principal strings: an ARN, a user name as Objects presents it, or
    # the wildcard (which requires allow_public). Mutually exclusive with
    # policy_json.
    access = optional(object({
      read  = optional(list(string), [])
      write = optional(list(string), [])
    }), null)

    # Escape hatch for anything the curated 'access' block cannot express. A
    # raw S3 policy document. Mutually exclusive with 'access'.
    policy_json = optional(string, null)

    # Explicit acknowledgement that a wildcard principal is intended. Without
    # it, a wildcard Principal — reachable from either 'access' or 'policy_json'
    # — fails the plan. A world-readable bucket must not be a typo.
    allow_public = optional(bool, false)

    # S3 Object Lock (WORM). Objects supports PUT/GET Bucket Object Lock
    # Configuration, Object Retention and Object Legal Hold, but:
    #
    #   - COMPLIANCE mode ONLY. Objects has no governance mode, so GOVERNANCE
    #     is rejected here rather than failing halfway through an apply.
    #   - versioning is mandatory.
    #   - it must be enabled AT BUCKET CREATION and cannot be retrofitted;
    #     adding this to an existing bucket means destroying and recreating it.
    #
    # COMPLIANCE retention is genuinely irreversible: no one, including the
    # storage admin, can delete an object before its retention expires. Hence
    # acknowledge_irreversible, which must be set true explicitly.
    object_lock = optional(object({
      mode                     = optional(string, "COMPLIANCE")
      retention_days           = optional(number, null)
      retention_years          = optional(number, null)
      acknowledge_irreversible = optional(bool, false)
    }), null)
  }))
  default = {}

  ##################################################
  # Naming
  ##################################################

  # The vendor documents 3-64 characters, but 64 is unreachable through this
  # module: hashicorp/aws validates 'bucket' against the AWS S3 limit of 63 and
  # rejects a 64-character name with "expected length of bucket to be in the
  # range (0 - 63)", which says nothing about why. So the effective ceiling is
  # 63, enforced here with the reason rather than left to the provider.
  validation {
    condition = alltrue([
      for k, b in var.buckets : try(length(b.name) >= 3 && length(b.name) <= 63, false)
    ])
    error_message = "Each buckets 'name' must be 3-63 characters long. Nutanix Objects allows up to 64, but the hashicorp/aws provider enforces the AWS S3 limit of 63, so 64 cannot be created through this module."
  }

  # Vendor rule: DNS-compliant — lowercase alphanumeric, dot and hyphen only,
  # beginning with a lowercase letter or number. Ending on an alphanumeric is
  # implied by DNS compliance. No uppercase, no underscores, which catches the
  # instinct to reuse a snake_case map key as the bucket name.
  validation {
    condition = alltrue([
      for k, b in var.buckets : can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", b.name))
    ])
    error_message = "Each buckets 'name' must be DNS-compliant: lowercase letters, digits, dots and hyphens only, beginning and ending with a lowercase letter or digit. No uppercase, no underscores."
  }

  # DNS labels cannot be empty, so '..', '.-', '-.' and a leading/trailing dot
  # are all invalid even though the character-class rule above allows them.
  validation {
    condition = alltrue([
      for k, b in var.buckets : !can(regex("[.][.]|[.][-]|[-][.]", b.name))
    ])
    error_message = "Each buckets 'name' must not contain an empty DNS label ('..', '.-' or '-.')."
  }

  ##################################################
  # Store binding
  ##################################################

  validation {
    condition = alltrue([
      for k, b in var.buckets : b.store != null && trimspace(b.store) != ""
    ])
    error_message = "Each buckets entry must set a non-empty 'store'."
  }

  # Two entries naming the same bucket on the same store are two resources
  # fighting over one bucket. Across DIFFERENT stores a name may legitimately
  # repeat, so uniqueness is checked on the (store, name) pair.
  validation {
    condition     = length(distinct([for k, b in var.buckets : "${b.store}/${b.name}"])) == length(var.buckets)
    error_message = "Two buckets must not share the same 'name' on the same 'store'."
  }

  ##################################################
  # Durability
  ##################################################

  # A durable bucket is rendered by the prevent_destroy block, which hardcodes
  # force_destroy = false. Accepting force_destroy = true there would silently
  # do nothing, so reject the combination instead.
  validation {
    condition = alltrue([
      for k, b in var.buckets : !(b.durable && b.force_destroy)
    ])
    error_message = "A bucket cannot set both 'durable = true' and 'force_destroy = true'. Durable buckets are always force_destroy = false."
  }

  ##################################################
  # Policies
  ##################################################

  # The curated compiler and the raw escape hatch are alternatives, never a
  # merge: two policy documents cannot both be the bucket policy.
  validation {
    condition = alltrue([
      for k, b in var.buckets : !(b.access != null && b.policy_json != null)
    ])
    error_message = "A bucket must set EITHER 'access' (curated grants) OR 'policy_json' (raw document), not both."
  }

  # policy_json must actually be JSON, otherwise the failure surfaces as a
  # provider error mid-apply.
  validation {
    condition = alltrue([
      for k, b in var.buckets : b.policy_json == null || can(jsondecode(b.policy_json))
    ])
    error_message = "When set, 'policy_json' must be a valid JSON document."
  }

  # A wildcard principal in the curated 'access' block needs allow_public.
  validation {
    condition = alltrue([
      for k, b in var.buckets :
      b.allow_public || b.access == null ||
      !contains(concat(coalesce(b.access.read, []), coalesce(b.access.write, [])), "*")
    ])
    error_message = "A bucket granting 'access' to the principal \"*\" must also set 'allow_public = true'. An accidentally world-readable bucket is the exact footgun this refuses."
  }

  # The same rule for the escape hatch, which is where the footgun was actually
  # found. Statement may be a single object or a list; Principal may be "*",
  # {"AWS": "*"} or {"AWS": ["*", ...]}. flatten() collapses all three shapes.
  validation {
    condition = alltrue([
      for k, b in var.buckets :
      b.allow_public || !contains(flatten([
        for st in flatten([try(jsondecode(b.policy_json).Statement, [])]) : [
          for p in [try(st.Principal, null)] :
          p == null ? [] : (can(tostring(p)) ? [tostring(p)] : flatten([for _, v in p : v]))
        ]
      ]), "*")
    ])
    error_message = "A 'policy_json' document with a Principal of \"*\" must also set 'allow_public = true'. An accidentally world-readable bucket is the exact footgun this refuses."
  }

  ##################################################
  # Lifecycle rules
  ##################################################

  validation {
    condition = alltrue(flatten([
      for k, b in var.buckets : [
        for r in b.lifecycle_rules : r.id != null && trimspace(r.id) != ""
      ]
    ]))
    error_message = "Each lifecycle rule must set a non-empty 'id'."
  }

  # A rule with no action is a no-op the provider will reject at apply time.
  validation {
    condition = alltrue(flatten([
      for k, b in var.buckets : [
        for r in b.lifecycle_rules : anytrue([
          r.expiration_days != null,
          r.noncurrent_version_expiration_days != null,
          r.abort_incomplete_multipart_upload_days != null,
        ])
      ]
    ]))
    error_message = "Each lifecycle rule must set at least one of 'expiration_days', 'noncurrent_version_expiration_days' or 'abort_incomplete_multipart_upload_days'."
  }

  validation {
    condition = alltrue(flatten([
      for k, b in var.buckets : [
        for r in b.lifecycle_rules : [
          for d in [r.expiration_days, r.noncurrent_version_expiration_days, r.abort_incomplete_multipart_upload_days] :
          d == null || try(d >= 1, false)
        ]
      ]
    ]))
    error_message = "Lifecycle rule day counts must be >= 1 when set."
  }

  ##################################################
  # Object Lock (WORM)
  ##################################################

  # Objects implements COMPLIANCE only. Fail at plan, not at apply.
  validation {
    condition = alltrue([
      for k, b in var.buckets : b.object_lock == null || b.object_lock.mode == "COMPLIANCE"
    ])
    error_message = "'object_lock.mode' must be \"COMPLIANCE\". Nutanix Objects does not implement GOVERNANCE mode, so a GOVERNANCE configuration fails at apply."
  }

  # S3 Object Lock requires a versioned bucket.
  validation {
    condition = alltrue([
      for k, b in var.buckets : b.object_lock == null || b.versioning
    ])
    error_message = "A bucket with 'object_lock' must also set 'versioning = true'. S3 Object Lock requires versioning."
  }

  # COMPLIANCE retention cannot be shortened, lifted or bypassed by anyone.
  validation {
    condition = alltrue([
      for k, b in var.buckets : b.object_lock == null || b.object_lock.acknowledge_irreversible
    ])
    error_message = "A bucket with 'object_lock' must set 'object_lock.acknowledge_irreversible = true'. COMPLIANCE retention cannot be shortened or removed by anyone, including the storage admin."
  }

  # Retention is expressed in days OR years, never both.
  validation {
    condition = alltrue([
      for k, b in var.buckets :
      b.object_lock == null ||
      !(b.object_lock.retention_days != null && b.object_lock.retention_years != null)
    ])
    error_message = "'object_lock' must set at most one of 'retention_days' or 'retention_years'."
  }

  validation {
    condition = alltrue([
      for k, b in var.buckets :
      b.object_lock == null || alltrue([
        for d in [b.object_lock.retention_days, b.object_lock.retention_years] :
        d == null || try(d >= 1, false)
      ])
    ])
    error_message = "'object_lock' retention, when set, must be >= 1."
  }
}
