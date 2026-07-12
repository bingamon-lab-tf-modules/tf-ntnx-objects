#!/usr/bin/env bash
# Fail if any legacy (non-_v2) nutanix resource OR data source is declared outside the
# allowlists. Allowlist = product-API families with no v2 replacement (reviewed each
# provider release). protection_rule is deliberately NOT allowlisted (v2 pair exists;
# migrated by issue 555).
set -euo pipefail

RESOURCE_ALLOW='^nutanix_(ndb_|karbon_|foundation_|self_service_|recovery_plan$|project$)'
DATA_ALLOW='^nutanix_(ndb_|karbon_|foundation_|self_service_|blueprint_|recovery_plans?$|projects?$)'

resource_violations=$(grep -rhoE '^\s*resource\s+"nutanix_[a-z0-9_]+"' \
	--include='*.tf' \
	--exclude-dir='.terraform' \
	. 2>/dev/null |
	sed -E 's/.*resource\s+"([a-z0-9_]+)".*/\1/' |
	sort -u |
	grep -Ev '_v2$' |
	grep -Ev "${RESOURCE_ALLOW}" || true)

data_violations=$(grep -rhoE '^\s*data\s+"nutanix_[a-z0-9_]+"' \
	--include='*.tf' \
	--exclude-dir='.terraform' \
	. 2>/dev/null |
	sed -E 's/.*data\s+"([a-z0-9_]+)".*/\1/' |
	sort -u |
	grep -Ev '_v2$' |
	grep -Ev "${DATA_ALLOW}" || true)

if [[ -n ${resource_violations} || -n ${data_violations} ]]; then
	echo "ERROR: legacy (non-_v2) nutanix usage found — deprecated Q4-CY2026:" >&2
	[[ -n ${resource_violations} ]] && {
		echo "resources:" >&2
		echo "${resource_violations}" >&2
	}
	[[ -n ${data_violations} ]] && {
		echo "data sources:" >&2
		echo "${data_violations}" >&2
	}
	echo "Migrate to the _v2 equivalent or (only if NO v2 exists) extend the allowlist via review." >&2
	exit 1
fi
echo "OK: no disallowed legacy nutanix resources or data sources."
