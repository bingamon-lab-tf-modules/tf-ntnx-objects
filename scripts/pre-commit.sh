#!/usr/bin/env bash

# Name: pre-commit.sh
# Description: A poor-man pre-commit hook for the opinionated TF module until a proper setup can be done.
# Install: ln -sf "../../scripts/pre-commit.sh" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

##################################################
# Variables
##################################################

declare MODULE_HOME
declare MODULE_TESTS

MODULE_HOME="$(pwd)/module"

if [[ -d "tests" ]]; then
	MODULE_TESTS="tests"
elif [[ -d "module" ]]; then
	MODULE_TESTS="module"
else
	echo "No module or tests folder found."
	exit 1
fi

# Note for Nix users: nix-shell -p opentofu trivy shellcheck tflint kics terraform-docs
REQUIRED_DEPS=(
	"git"
	#"kics"
	"shellcheck"
	"tflint"
	"tofu"
	"trivy"
	"terraform-docs"
)

##################################################
# Functions
##################################################

function header() {
	echo "----------------------------------------"
	echo "$1"
	echo "----------------------------------------"
}

function info() {
	echo "💬 $1"
}

function error() {
	echo "❌ $1"
}

function success() {
	echo "✅ $1"
}

# Ensure the required dependencies are present.
function check_dependencies() {

	info "Checking dependencies..."
	for DEP in "${REQUIRED_DEPS[@]}"; do
		if ! command -v "${DEP}" &>/dev/null; then
			error "${DEP} is not installed. Please install it before running this script."
			return 1
		fi
	done

	success "All dependencies are installed."
	return 0
}

# Check if the module folder exists.
function check_module_folder() {
	if [[ ! -d ${MODULE_TESTS} ]]; then
		error "The module folder ${MODULE_TESTS} does not exist."
		return 1
	fi

	success "Module folder ${MODULE_TESTS} exists."
	return 0
}

# Check for legacy (non-_v2) nutanix resources and data sources.
function check_legacy_resources() {
	./scripts/check-legacy-resources.sh || {
		error "Legacy nutanix resources or data sources detected."
		return 1
	}

	success "No legacy nutanix resources or data sources found."
	return 0
}

# Format the Terraform code and stage any changes.
function format_terraform_code() {

	# Store a list of all the Terraform files.
	local TF_FILES
	TF_FILES=$(find . -name "*.tf" -type f)

	tofu fmt -recursive -write=true || {
		error "Failed to format the Terraform code."
		return 1
	}

	# Automatically stage any modified Terraform files.
	for TF_FILE in ${TF_FILES}; do
		if git diff --quiet "${TF_FILE}"; then
			continue
		else
			git add "${TF_FILE}"
			info "Changes to the file ${TF_FILE} have been staged."
		fi
	done

	success "Terraform code formatted successfully."
	return 0
}

# Generate the Terraform documentation and stage any changes.
function generate_terraform_docs() {

	# Store a list of all the README.md files.
	local README_FILES
	README_FILES=$(find . -name "README.md" -type f)

	if [[ -f ".terraform-docs.yml" ]]; then
		terraform-docs --config .terraform-docs.yml "${MODULE_HOME}" || {
			error "Failed to generate the Terraform documentation."
			return 1
		}
	else
		error "No configuration file found for Terraform documentation. Please create a .terraform-docs.yml file in the root of the repository."
		return 1
	fi

	# Automatically stage any modified README.md files.
	for README in ${README_FILES}; do
		if git diff --quiet "${README}"; then
			continue
		else
			git add "${README}"
			info "Changes to the file ${README} have been staged."
		fi
	done

	success "Terraform documentation generated successfully."
	return 0
}

# Get the Terraform modules.
function get_terraform_modules() {
	tofu -chdir=${MODULE_TESTS} get || {
		error "Failed to get the Terraform modules."
		return 1
	}

	success "Terraform modules fetched successfully."
	return 0
}

# Initialize the Terraform code.
function init_terraform_code() {
	tofu -chdir=${MODULE_TESTS} init -backend=false || {
		error "Failed to initialize the Terraform code."
		return 1
	}

	success "Terraform code initialized successfully."
	return 0
}

# Validate the Terraform code.
function validate_terraform_code() {
	tofu -chdir=${MODULE_TESTS} validate || {
		error "Failed to validate the Terraform code."
		return 1
	}

	success "Terraform code validated successfully."
	return 0
}

# Lint the Terraform code.
function lint_terraform_code() {
	tflint --format=compact --recursive || {
		error "Failed to lint the Terraform code."
		return 1
	}

	success "Terraform code linted successfully."
	return 0
}

# Scan the Terraform code.
function scan_terraform_code() {
	mkdir -p reports || {
		error "Failed to create the reports directory."
		return 1
	}

	trivy fs \
		--exit-code 1 \
		--severity HIGH,CRITICAL \
		--format table \
		. || {
		error "Failed to scan the Terraform code with Trivy."
		return 1
	}

	#kics scan \
	#    --path "." \
	#    --type "Terraform" \
	#    --exclude-paths "**/.terraform/**,**/examples/**" \
	#    --report-formats "json,sarif" \
	#    --output-path "./reports" \
	#    --output-name "kics-scan-results" \
	#    --fail-on "high,critical" \
	#    --verbose || {
	#        error "Failed to scan the Terraform code with KICS."
	#        return 1
	#    }

	success "Terraform code scanned successfully."
	return 0
}

# Remove the .terraform.lock.hcl file from the module folder.
# The root module should manage the lock files for the sub-modules.
function remove_terraform_lock_file() {
	if [[ -f "${MODULE_TESTS}/.terraform.lock.hcl" ]]; then
		rm -f "${MODULE_TESTS}/.terraform.lock.hcl"
		git add "${MODULE_TESTS}/.terraform.lock.hcl" 2>/dev/null || true
		info "Removed the file .terraform.lock.hcl from the module folder."
	else
		info "The file .terraform.lock.hcl does not exist in the module folder."
		return 0
	fi

	success "Terraform lock file removed successfully."
	return 0
}

##################################################
# Main
##################################################

header "Started running pre-commit hooks..."

# Make sure the dependencies are installed.
check_dependencies || {
	error "Failed to check dependencies."
	exit 1
}

check_module_folder || {
	error "Failed to check the module folder."
	exit 1
}

# Check for legacy nutanix resources and data sources.
check_legacy_resources || {
	error "Failed to check for legacy nutanix resources."
	exit 1
}

# Format the Terraform code.
format_terraform_code || {
	error "Failed to format the Terraform code."
	exit 1
}

# Generate the Terraform documentation.
generate_terraform_docs || {
	error "Failed to generate the Terraform documentation."
	exit 1
}

# Get the Terraform modules.
get_terraform_modules || {
	error "Failed to get the Terraform modules."
	exit 1
}

# Initialize the Terraform code.
init_terraform_code || {
	error "Failed to initialize the Terraform code."
	exit 1
}

# Validate the Terraform code.
validate_terraform_code || {
	error "Failed to validate the Terraform code."
	exit 1
}

# Lint the Terraform code.
lint_terraform_code || {
	error "Failed to lint the Terraform code."
	exit 1
}

# Scan the Terraform code.
scan_terraform_code || {
	error "Failed to scan the Terraform code."
	exit 1
}

# Remove the .terraform.lock.hcl file from the module folder.
remove_terraform_lock_file || {
	error "Failed to remove the .terraform.lock.hcl file from the module folder."
	exit 1
}

header "Finished running pre-commit hooks..."
