#!/usr/bin/env bash

# Name: bootstrap.sh
# Description: Bootstraps a new Terraform module.

set -euo pipefail

#########################
# Variables
#########################

declare MODULE_NAME
declare DRY_RUN=true
declare MODULE_PLACEHOLDER="MODULE_NAME"
declare MODULE_FOLDER="module"
declare TESTS_FOLDER="tests"

#########################
# Functions
#########################

function usage() {
	cat <<-EOF
		Usage: $0 [options]

		The script runs in a dry-run mode by default. In order to make changes, you must pass the execute flag of 'x' or 'execute'.

		Options:
			-x   Run the script making changes.
			-h   Show this help message and exit.
	EOF
}

function header() {
	echo "----------------------------------------"
	echo "$*"
	echo "----------------------------------------"
}

function message() {
	echo "✅ $*"
}

function error() {
	echo "💥 ERROR: $*"
}

function main() {

	# Obtain the current directory name.
	CURRENT_DIR=$(basename "$(pwd)")

	# Try to use readline if available.
	if [[ "${BASH_VERSION}" ]] && command -v bind >/dev/null 2>&1; then
		read -e -i "${CURRENT_DIR}" -rp "💬 Enter the module name [${CURRENT_DIR}]: " MODULE_NAME
	else
		echo "💬 Current directory name: ${CURRENT_DIR}"
		read -rp "💬 Enter the module name (press Enter to use '${CURRENT_DIR}'): " MODULE_NAME
	fi

	# If user just pressed enter without typing anything, use the current directory name as default.
	if [[ ${MODULE_NAME:-EMPTY} == "EMPTY" ]]; then
		MODULE_NAME="${CURRENT_DIR}"
	fi

	# Make sure the module folder exist.
	if [[ ! -d ${MODULE_FOLDER} ]]; then
		error "Module folder ${MODULE_FOLDER} does not exist!"
		return 1
	fi

	# Make sure the tests folder exist.
	if [[ ! -d ${TESTS_FOLDER} ]]; then
		error "Tests folder ${TESTS_FOLDER} does not exist!"
		return 1
	fi

	# Ensure the module name is in lowercase and contains only alphanumeric characters and no spaces.
	# Replace spaces with hyphens.
	MODULE_NAME=$(echo "${MODULE_NAME}" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | tr -cd '[:alnum:]_.-')
	message "Using translated module name: ${MODULE_NAME}"

	# Replace the placeholder text in the main README.md file with the module name.
	if [[ ${DRY_RUN} == true ]]; then
		echo "💬 Would replace placeholder text ${MODULE_PLACEHOLDER} with ${MODULE_NAME} in README.md"
	else
		sed -i "s/${MODULE_PLACEHOLDER}/${MODULE_NAME}/g" README.md || {
			error "Failed to replace placeholder text ${MODULE_PLACEHOLDER} with ${MODULE_NAME} in README.md!"
			return 1
		}
	fi

	# Remove the instructions section from the main README.md file.
	# This is every bit of text between the <!-- INSTRUCTIONS START HERE --> and <!-- INSTRUCTIONS END HERE --> comments.
	if [[ ${DRY_RUN} == true ]]; then
		echo "💬 Would remove instructions section from README.md"
	else
		sed -i -e '/<!-- INSTRUCTIONS START HERE -->/,/<!-- INSTRUCTIONS END HERE -->/d' README.md || {
			error "Failed to remove instructions section from README.md!"
			return 1
		}

		# Trim all double blank lines to single in the README.md file.
		sed -i '/^$/N;/\n$/D' README.md || {
			error "Failed to remove blank line from README.md!"
			return 1
		}
	fi

	# Replace the placeholder text in the module README.md file with the module name.
	if [[ ${DRY_RUN} == true ]]; then
		echo "💬 Would replace placeholder text ${MODULE_PLACEHOLDER} with ${MODULE_NAME} in ${MODULE_FOLDER}/README.md"
	else
		sed -i "s/${MODULE_PLACEHOLDER}/${MODULE_NAME}/g" ${MODULE_FOLDER}/README.md || {
			error "Failed to replace placeholder text ${MODULE_PLACEHOLDER} with ${MODULE_NAME} in ${MODULE_FOLDER}/README.md!"
			return 1
		}
	fi

	# Remove the template roadmap as it is no longer needed.
	if [[ ${DRY_RUN} == true ]]; then
		echo "💬 Would remove template roadmap file docs/roadmap.md"
	else
		rm -rf docs/roadmap.md || {
			error "Failed to remove template roadmap file docs/roadmap.md!"
			return 1
		}
	fi

}

##########################
# Main
##########################

# Process short options.
while getopts "xh" opt; do
	case $opt in
	x) DRY_RUN=false ;;
	h)
		usage
		exit 0
		;;
	*)
		usage
		exit 1
		;;
	esac
done

if [[ $DRY_RUN == true ]]; then
	header "Bootstrapping module (dry-run)..."
else
	header "Bootstrapping module..."
fi

main || {
	error "Failed to bootstrap module!"
	exit 1
}

header "Module bootstrapped successfully!"

message "You can now safely remove this script with 'rm scripts/bootstrap.sh'."
