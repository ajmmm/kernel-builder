#!/usr/bin/env bash

function vm_fatal() {
	echo "FATAL ERROR: $@"
	exit 1
}

function vm_info() {
	echo "$@"
}

function vm_step() {
	echo "==> $@"
}

function vm_progress_tick() {
	[ "${VM_DRY_RUN}" = "1" ] && return 0
	printf "."
}

function vm_progress_done() {
	[ "${VM_DRY_RUN}" = "1" ] && return 0
	printf "\n"
}

function vm_debug() {
	[ "${VM_DEBUG}" = "1" ] && echo "DEBUG: $@"
}

function vm_require_cmd() {
	local cmd="${1}"

	command -v "${cmd}" 1>/dev/null 2>&1 || vm_fatal "I need ${cmd}!"
}

function vm_verify_yaml_file() {
	local file_path="${1}"

	vm_require_cmd yq
	yq eval '.' "${file_path}" 1>/dev/null || vm_fatal "Rendered YAML failed to parse: ${file_path}"
}

function vm_verify_json_file() {
	local file_path="${1}"

	vm_require_cmd jq
	jq empty "${file_path}" || vm_fatal "Rendered JSON failed to parse: ${file_path}"
}

function vm_verify_structured_file() {
	local format="${1}"
	local file_path="${2}"

	case "${format}" in
		yaml)
			vm_verify_yaml_file "${file_path}"
			;;
		json)
			vm_verify_json_file "${file_path}"
			;;
		*)
			vm_fatal "Unsupported structured data format: ${format}"
			;;
	esac
}

function vm_quote_cmd() {
	printf "%q " "$@"
}

function vm_run() {
	if [ "${VM_DRY_RUN}" = "1" ] || [ "${VM_VERBOSE}" = "1" ]; then
		vm_quote_cmd "$@"
		printf "\n"
	fi

	[ "${VM_DRY_RUN}" = "1" ] && return 0
	"$@"
}

function vm_prlctl_output_has_error() {
	local output_file="${1}"

	grep -Eq '^(Login failed:|Failed to |Unable to perform the action because )' "${output_file}"
}

function vm_run_quiet() {
	local output_file rc cmd_name

	if [ "${VM_DRY_RUN}" = "1" ] || [ "${VM_VERBOSE}" = "1" ]; then
		vm_run "$@"
		return $?
	fi

	output_file="$(mktemp "${TMPDIR:-/tmp}/builder-cmd.XXXXXX")" || vm_fatal "Failed to create temp file"
	cmd_name="$(basename "$1")"

	if "$@" >"${output_file}" 2>&1; then
		if [ "${cmd_name}" = "prlctl" ] && vm_prlctl_output_has_error "${output_file}"; then
			cat "${output_file}" >&2
			rm -f "${output_file}"
			return 1
		fi
		rm -f "${output_file}"
		return 0
	fi

	rc=$?
	cat "${output_file}" >&2
	rm -f "${output_file}"
	return "${rc}"
}

function vm_try_quiet() {
	local output_file rc cmd_name

	if [ "${VM_DRY_RUN}" = "1" ] || [ "${VM_VERBOSE}" = "1" ]; then
		vm_run "$@"
		return $?
	fi

	output_file="$(mktemp "${TMPDIR:-/tmp}/builder-cmd.XXXXXX")" || vm_fatal "Failed to create temp file"
	cmd_name="$(basename "$1")"

	if "$@" >"${output_file}" 2>&1; then
		if [ "${cmd_name}" = "prlctl" ] && vm_prlctl_output_has_error "${output_file}"; then
			rm -f "${output_file}"
			return 1
		fi
		rm -f "${output_file}"
		return 0
	fi

	rc=$?
	rm -f "${output_file}"
	return "${rc}"
}

function vm_prl_info_json() {
	local prlctl="${1}"

	"${prlctl}" list --info "${VM_NAME}" --json
}

function vm_prl_device_exists() {
	local prlctl="${1}"
	local device="${2}"
	local info_json

	info_json="$(vm_prl_info_json "${prlctl}")" || return 1
	printf "%s\n" "${info_json}" | jq -e --arg device "${device}" '.[0].Hardware[$device] != null' >/dev/null 2>&1
}

function vm_guess_arch() {
	case "$(uname -m)" in
		arm64|aarch64)
			echo "aarch64"
			;;
		x86_64|amd64)
			echo "x86_64"
			;;
		*)
			vm_fatal "Unsupported host architecture: $(uname -m)"
			;;
	esac
}

function vm_default_prl_adaptive_hypervisor() {
	case "${HOST_ARCH}" in
		aarch64|x86_64)
			printf "%s\n" "on"
			;;
		*)
			printf "%s\n" "off"
			;;
	esac
}

function vm_default_prl_nested_virt() {
	case "${HOST_ARCH}" in
		x86_64)
			printf "%s\n" "on"
			;;
		aarch64)
			printf "%s\n" "off"
			;;
		*)
			printf "%s\n" "off"
			;;
	esac
}

function vm_resolve_auto_bool() {
	local value="${1}"
	local default_value="${2}"

	if [ "${value}" = "auto" ]; then
		printf "%s\n" "${default_value}"
	else
		printf "%s\n" "${value}"
	fi
}

function vm_default_target() {
	printf "%s\n" "${VM_DEFAULT_TARGET:-fc43/vm-default}"
}

function vm_normalize_target() {
	local target="${1%/}"

	case "${target}" in
		*/*)
			printf "%s\n" "${target}"
			;;
		*)
			printf "%s/vm-default\n" "${target}"
			;;
	esac
}

function vm_target_dir() {
	printf "%s\n" "${BASEPATH}/${VM_TARGET}"
}

function vm_target_slug() {
	printf "%s\n" "${VM_TARGET}" | tr '/:' '__'
}

function vm_arch_url_var_name() {
	case "${VM_ARCH}" in
		aarch64)
			printf "%s\n" "VM_IMAGE_ARTIFACTS_URL_ARM64"
			;;
		x86_64)
			printf "%s\n" "VM_IMAGE_ARTIFACTS_URL_AMD64"
			;;
		*)
			vm_fatal "Unsupported guest architecture for image URL resolution: ${VM_ARCH}"
			;;
	esac
}

function vm_load_target_config() {
	VM_TARGET_DIR="${VM_TARGET_DIR:-$(vm_target_dir)}"
	VM_CONFIG_FILE="${VM_CONFIG_FILE:-${VM_TARGET_DIR}/vm.conf}"

	if [ -r "${VM_CONFIG_FILE}" ]; then
		. "${VM_CONFIG_FILE}" || vm_fatal "Failed to load target config: ${VM_CONFIG_FILE}"
	fi
}

function vm_load_parallels_config() {
	PRL_CONFIG_FILE="${PRL_CONFIG_FILE:-${BASEPATH}/config/parallels.conf}"

	if [ -r "${PRL_CONFIG_FILE}" ]; then
		. "${PRL_CONFIG_FILE}" || vm_fatal "Failed to load Parallels config: ${PRL_CONFIG_FILE}"
	fi
}

function vm_resolve_vm_defaults() {
	[ -n "${VM_NAME:-}" ] || vm_fatal "VM instance is required. Pass --instance <vm-name>."
	VM_LOCAL_DOMAIN="${VM_LOCAL_DOMAIN:-ajm.dev}"
	VM_HOSTNAME="${VM_NAME}"
	VM_FQDN="${VM_HOSTNAME}.${VM_LOCAL_DOMAIN}"
	VM_USERNAME="${VM_USERNAME:-dev}"
	VM_CPUS="${VM_CPUS:-6}"
	VM_MEMORY_MB="${VM_MEMORY_MB:-12288}"
	VM_DISK_GB="${VM_DISK_GB:-120}"
	VM_TIMEZONE="${VM_TIMEZONE:-Europe/London}"
	VM_KEYBOARD_LAYOUT="${VM_KEYBOARD_LAYOUT:-gb}"
	VM_KEYBOARD_MODEL="${VM_KEYBOARD_MODEL:-pc105}"
	VM_KEYBOARD_VARIANT="${VM_KEYBOARD_VARIANT:-}"
	VM_KEYBOARD_OPTIONS="${VM_KEYBOARD_OPTIONS:-}"
	VM_KEYBOARD_VC_KEYMAP="${VM_KEYBOARD_VC_KEYMAP:-gb}"
	VM_K8S_CHANNEL="${VM_K8S_CHANNEL:-v1.35}"
	VM_CHRONY_MAKESTEP="${VM_CHRONY_MAKESTEP:-1.0 3}"
	VM_PACKAGE_UPGRADE="${VM_PACKAGE_UPGRADE:-true}"
	VM_PACKAGE_REBOOT_IF_REQUIRED="${VM_PACKAGE_REBOOT_IF_REQUIRED:-true}"
	[ -n "${VM_BOOT_PARTITION_GB+x}" ] || VM_BOOT_PARTITION_GB="8"
	VM_IMAGE_PREP_TARGET="${VM_IMAGE_PREP_TARGET:-fc43/vm-builder}"
	VM_KEEP_BUILDER="${VM_KEEP_BUILDER:-0}"
	VM_BOOT_PARTITION_DEVICE="${VM_BOOT_PARTITION_DEVICE:-/dev/sda2}"
	VM_ROOT_PARTITION_DEVICE="${VM_ROOT_PARTITION_DEVICE:-/dev/sda3}"
	VM_WAIT_FOR_UPGRADE="${VM_WAIT_FOR_UPGRADE:-0}"
	VM_DISABLE_FIREWALLD="${VM_DISABLE_FIREWALLD:-true}"
	VM_PRL_DISTRIBUTION="${VM_PRL_DISTRIBUTION:-linux}"
	HOST_ARCH="${HOST_ARCH:-$(vm_guess_arch)}"
	VM_ARCH="${VM_ARCH:-${HOST_ARCH}}"
	VM_TARGET_SLUG="${VM_TARGET_SLUG:-$(vm_target_slug)}"
	VM_CACHE_DIR="${VM_CACHE_DIR:-${BASEPATH}/.cache}"
	VM_IMAGE_DIR="${VM_IMAGE_DIR:-${VM_CACHE_DIR}/images}"
	VM_INSTANCE_DIR="${VM_INSTANCE_DIR:-${VM_CACHE_DIR}/instances}"
	VM_SEED_DIR="${VM_SEED_DIR:-${VM_CACHE_DIR}/seed/${VM_TARGET_SLUG}/${VM_NAME}}"
	VM_HOME_BASE="${VM_HOME_BASE:-${HOME}/Parallels}"
	VM_PARALLELS_DIR="${VM_PARALLELS_DIR:-${VM_HOME_BASE}}"
	VM_BUNDLE_PATH="${VM_BUNDLE_PATH:-${VM_PARALLELS_DIR}/${VM_NAME}.pvm}"
	VM_VM_DISK_PATH="${VM_VM_DISK_PATH:-${VM_BUNDLE_PATH}/${VM_NAME}.hdd}"
	VM_CLOUD_INIT_DIR="${VM_CLOUD_INIT_DIR:-${VM_TARGET_DIR}/cloud-init}"
	VM_CLOUD_INIT_SHARED_DIR="${VM_CLOUD_INIT_SHARED_DIR:-${BASEPATH}/config/cloud-init}"
	if [ -z "${VM_IMAGE_ARTIFACTS_URL}" ]; then
		local arch_url_var
		arch_url_var="$(vm_arch_url_var_name)"
		VM_IMAGE_ARTIFACTS_URL="${!arch_url_var:-${VM_IMAGE_ARTIFACTS_URL:-}}"
	fi
	if [ -n "${VM_IMAGE_FILE:-}" ]; then
		VM_IMAGE_NAME="${VM_IMAGE_NAME:-$(basename "${VM_IMAGE_FILE}")}"
	else
		[ -n "${VM_IMAGE_ARTIFACTS_URL}" ] || vm_fatal "VM_IMAGE_ARTIFACTS_URL is not set for ${VM_TARGET} (${VM_ARCH})"
		[ -n "${VM_IMAGE_NAME_REGEX}" ] || vm_fatal "VM_IMAGE_NAME_REGEX is not set for ${VM_TARGET}"
		[ -n "${VM_CHECKSUM_NAME_REGEX}" ] || vm_fatal "VM_CHECKSUM_NAME_REGEX is not set for ${VM_TARGET}"
	fi
	VM_SEED_ISO="${VM_SEED_ISO:-${VM_SEED_DIR}/seed.iso}"
	VM_INSTANCE_ID="${VM_INSTANCE_ID:-${VM_NAME}-01}"
	VM_SSH_KEY_PATH="${VM_SSH_KEY_PATH:-${HOME}/.ssh/id_rsa.pub}"
	VM_SSH_HOST_ALIAS="${VM_SSH_HOST_ALIAS:-${VM_NAME}}"
	VM_SSH_HOSTNAME="${VM_SSH_HOSTNAME:-${VM_NET_0_IPV4_ADDRESS%%/*}}"
	VM_INSTALL_SSH_CONFIG="${VM_INSTALL_SSH_CONFIG:-true}"
	VM_SSH_CONFIG_DIR="${VM_SSH_CONFIG_DIR:-${VM_CACHE_DIR}/ssh-config.d}"
	VM_SSH_CONFIG_BASENAME="${VM_SSH_CONFIG_BASENAME:-${VM_SSH_HOST_ALIAS}.conf}"
	VM_SSH_CONFIG_PATH="${VM_SSH_CONFIG_PATH:-${VM_SSH_CONFIG_DIR}/${VM_SSH_CONFIG_BASENAME}}"
	VM_SSH_KNOWN_HOSTS_BASENAME="${VM_SSH_KNOWN_HOSTS_BASENAME:-${VM_SSH_HOST_ALIAS}.known_hosts}"
	VM_SSH_KNOWN_HOSTS_PATH="${VM_SSH_KNOWN_HOSTS_PATH:-${VM_SSH_CONFIG_DIR}/${VM_SSH_KNOWN_HOSTS_BASENAME}}"
	VM_INSTANCE_STATE_PATH="${VM_INSTANCE_STATE_PATH:-${VM_INSTANCE_DIR}/${VM_NAME}.env}"
	VM_CONVERTED_DIR="${VM_CONVERTED_DIR:-${VM_IMAGE_DIR}/converted}"
	VM_IMAGE_SOURCE_FORMAT="${VM_IMAGE_SOURCE_FORMAT:-qcow2}"
	VM_RECREATE="${VM_RECREATE:-0}"
}

function vm_resolve_prl_defaults() {
	PRL_AUTOSTART="${PRL_AUTOSTART:-off}"
	PRL_AUTOSTOP="${PRL_AUTOSTOP:-stop}"
	PRL_STARTUP_VIEW="${PRL_STARTUP_VIEW:-same}"
	PRL_ON_SHUTDOWN="${PRL_ON_SHUTDOWN:-close}"
	PRL_ON_WINDOW_CLOSE="${PRL_ON_WINDOW_CLOSE:-keep-running}"
	PRL_PAUSE_IDLE="${PRL_PAUSE_IDLE:-off}"
	PRL_ADAPTIVE_HYPERVISOR="${PRL_ADAPTIVE_HYPERVISOR:-auto}"
	PRL_NESTED_VIRT="${PRL_NESTED_VIRT:-auto}"
	PRL_SHARED_PROFILE="${PRL_SHARED_PROFILE:-off}"
	PRL_SMART_MOUNT="${PRL_SMART_MOUNT:-off}"
	PRL_SHARE_HOST_FOLDERS="${PRL_SHARE_HOST_FOLDERS:-on}"
	PRL_SHARE_HOST_FOLDERS_AUTOMOUNT="${PRL_SHARE_HOST_FOLDERS_AUTOMOUNT:-on}"
	PRL_SHARE_HOST_FOLDERS_DEFINED="${PRL_SHARE_HOST_FOLDERS_DEFINED:-}"
	PRL_SHARE_HOST_FOLDER_DOWNLOADS="${PRL_SHARE_HOST_FOLDER_DOWNLOADS:-on}"
	PRL_SHARE_HOST_FOLDER_DOWNLOADS_NAME="${PRL_SHARE_HOST_FOLDER_DOWNLOADS_NAME:-Downloads}"
	PRL_SHARE_HOST_FOLDER_DOWNLOADS_PATH="${PRL_SHARE_HOST_FOLDER_DOWNLOADS_PATH:-${HOME}/Downloads}"
	PRL_SHARE_HOST_FOLDER_DEVELOP="${PRL_SHARE_HOST_FOLDER_DEVELOP:-off}"
	PRL_SHARE_HOST_FOLDER_DEVELOP_NAME="${PRL_SHARE_HOST_FOLDER_DEVELOP_NAME:-Develop}"
	PRL_SHARE_HOST_FOLDER_DEVELOP_PATH="${PRL_SHARE_HOST_FOLDER_DEVELOP_PATH:-${HOME}/Develop}"
	PRL_SHARE_GUEST_FOLDERS="${PRL_SHARE_GUEST_FOLDERS:-off}"
	PRL_SHARED_CLIPBOARD="${PRL_SHARED_CLIPBOARD:-on}"
	PRL_TIME_SYNC="${PRL_TIME_SYNC:-on}"
	PRL_HDD_ONLINE_COMPACT="${PRL_HDD_ONLINE_COMPACT:-on}"
	PRL_SHARED_CLOUD="${PRL_SHARED_CLOUD:-off}"
	PRL_SYNC_HOST_PRINTERS="${PRL_SYNC_HOST_PRINTERS:-off}"
	PRL_SYNC_DEFAULT_PRINTER="${PRL_SYNC_DEFAULT_PRINTER:-off}"
	PRL_SHOW_HOST_PRINTER_UI="${PRL_SHOW_HOST_PRINTER_UI:-off}"
	PRL_SOUND="${PRL_SOUND:-off}"
	PRL_MICROPHONE="${PRL_MICROPHONE:-off}"
	PRL_AUTO_SHARE_CAMERA="${PRL_AUTO_SHARE_CAMERA:-off}"
	PRL_FULL_SCREEN_USE_ALL_DISPLAYS="${PRL_FULL_SCREEN_USE_ALL_DISPLAYS:-off}"
	PRL_COHERENCE_AUTO_SWITCH_FULLSCREEN="${PRL_COHERENCE_AUTO_SWITCH_FULLSCREEN:-off}"
	PRL_SHOW_GUEST_NOTIFICATIONS="${PRL_SHOW_GUEST_NOTIFICATIONS:-off}"
	PRL_SHOW_GUEST_APP_FOLDER_IN_DOCK="${PRL_SHOW_GUEST_APP_FOLDER_IN_DOCK:-off}"
	PRL_BOUNCE_DOCK_ICON_WHEN_APP_FLASHES="${PRL_BOUNCE_DOCK_ICON_WHEN_APP_FLASHES:-off}"
	PRL_SH_APP_HOST_TO_GUEST="${PRL_SH_APP_HOST_TO_GUEST:-off}"
	PRL_SH_APP_GUEST_TO_HOST="${PRL_SH_APP_GUEST_TO_HOST:-off}"
	PRL_WINSYSTRAY_IN_MACMENU="${PRL_WINSYSTRAY_IN_MACMENU:-off}"
	PRL_PICTURE_IN_PICTURE="${PRL_PICTURE_IN_PICTURE:-off}"
	PRL_TRAVEL_MODE_ENTER="${PRL_TRAVEL_MODE_ENTER:-never}"
	PRL_TRAVEL_MODE_QUIT="${PRL_TRAVEL_MODE_QUIT:-never}"
	PRL_AUTO_UPDATE_TOOLS="${PRL_AUTO_UPDATE_TOOLS:-on}"

	PRL_ADAPTIVE_HYPERVISOR="$(vm_resolve_auto_bool "${PRL_ADAPTIVE_HYPERVISOR}" "$(vm_default_prl_adaptive_hypervisor)")"
	PRL_NESTED_VIRT="$(vm_resolve_auto_bool "${PRL_NESTED_VIRT}" "$(vm_default_prl_nested_virt)")"
}

function vm_init_defaults() {
	[ -n "${BASEPATH}" ] || vm_fatal "BASEPATH is undefined"

	VM_DRY_RUN="${VM_DRY_RUN:-${VM_DRY_RUN_DEFAULT:-0}}"
	VM_VERBOSE="${VM_VERBOSE:-${VM_VERBOSE_DEFAULT:-0}}"
	VM_DEBUG="${VM_DEBUG:-${VM_DEBUG_DEFAULT:-0}}"
	VM_TARGET="${VM_TARGET:-$(vm_default_target)}"
	VM_TARGET="$(vm_normalize_target "${VM_TARGET}")"
	HOST_ARCH="${HOST_ARCH:-$(vm_guess_arch)}"
	VM_ARCH="${VM_ARCH:-${HOST_ARCH}}"

	vm_load_target_config
	vm_load_parallels_config
	vm_resolve_vm_defaults
	vm_resolve_prl_defaults
}

function vm_parse_args() {
	VM_COMMAND="help"
	VM_ACTIONS=""

	while [ "$#" -gt 0 ]; do
		case "${1}" in
			--action|--actions)
				[ -n "${2}" ] || vm_fatal "${1} requires a value"
				VM_ACTIONS="${2}"
				shift 2
				;;

			--instance|--instance-name|--name)
				[ -n "${2}" ] || vm_fatal "${1} requires a value"
				VM_NAME="${2}"
				shift 2
				;;

			--target)
				[ -n "${2}" ] || vm_fatal "--target requires a value"
				VM_TARGET="${2}"
				shift 2
				;;

			--target-dir)
				[ -n "${2}" ] || vm_fatal "--target-dir requires a value"
				VM_TARGET_DIR="${2}"
				shift 2
				;;

			--config|--config-file)
				[ -n "${2}" ] || vm_fatal "${1} requires a value"
				VM_CONFIG_FILE="${2}"
				shift 2
				;;

			--prl-config|--parallels-config)
				[ -n "${2}" ] || vm_fatal "${1} requires a value"
				PRL_CONFIG_FILE="${2}"
				shift 2
				;;

			--dry-run)
				VM_DRY_RUN=1
				shift
				;;

			--debug)
				VM_DEBUG=1
				shift
				;;

			--verbose|-v)
				VM_VERBOSE=1
				shift
				;;

			--upgrade)
				VM_PACKAGE_UPGRADE=true
				VM_PACKAGE_REBOOT_IF_REQUIRED=true
				VM_WAIT_FOR_UPGRADE=1
				shift
				;;

			--no-upgrade)
				VM_PACKAGE_UPGRADE=false
				VM_PACKAGE_REBOOT_IF_REQUIRED=false
				VM_WAIT_FOR_UPGRADE=0
				shift
				;;

			--help|-h)
				VM_COMMAND="help"
				return 0
				;;

			--)
				shift
				break
				;;

			-*)
				vm_fatal "Unknown option: ${1}"
				;;

			*)
				break
				;;
		esac
	done

	if [ -n "${VM_ACTIONS}" ]; then
		VM_COMMAND="action-list"
	elif [ "$#" -gt 0 ]; then
		VM_COMMAND="${1}"
	else
		VM_COMMAND="help"
	fi
}

function vm_ensure_dirs() {
	mkdir -p "${VM_CACHE_DIR}" "${VM_IMAGE_DIR}" "${VM_CONVERTED_DIR}" "${VM_SEED_DIR}" "${VM_PARALLELS_DIR}" \
		|| vm_fatal "Failed to create cache directories"
}

function vm_image_stem() {
	local name="${VM_IMAGE_NAME}"

	name="${name%.qcow2}"
	printf "%s\n" "${name}"
}

function vm_checksum_cache_name() {
	printf "%s\n" "${VM_TARGET_SLUG}-$(basename "${VM_CHECKSUM_NAME}")"
}

function vm_select_latest_match() {
	if [ "$#" -eq 0 ]; then
		return 1
	fi

	printf "%s\n" "$@" | sort -V | tail -n1
}

function vm_find_local_image_name() {
	find "${VM_IMAGE_DIR}" -maxdepth 1 -type f -print 2>/dev/null | \
		awk -F/ '{print $NF}' | grep -E "${VM_IMAGE_NAME_REGEX}" | sort -V | tail -n1
}

function vm_find_local_checksum_name() {
	find "${VM_IMAGE_DIR}" -maxdepth 1 -type f -print 2>/dev/null | \
		awk -F/ '{print $NF}' | grep -E "^${VM_TARGET_SLUG}-" | sed "s/^${VM_TARGET_SLUG}-//" | \
		grep -E "${VM_CHECKSUM_NAME_REGEX}" | sort -V | tail -n1
}

function vm_fetch_image_index() {
	vm_require_cmd curl
	curl --fail --location --silent --show-error "${VM_IMAGE_ARTIFACTS_URL}" \
		|| vm_fatal "Failed to fetch image index: ${VM_IMAGE_ARTIFACTS_URL}"
}

function vm_resolve_remote_image_name() {
	local index_html

	index_html="$(vm_fetch_image_index)" || exit 1
	printf "%s\n" "${index_html}" | grep -Eo "${VM_IMAGE_NAME_REGEX}" | \
		sort -V | tail -n1
}

function vm_resolve_remote_checksum_name() {
	local index_html

	index_html="$(vm_fetch_image_index)" || exit 1
	printf "%s\n" "${index_html}" | grep -Eo "${VM_CHECKSUM_NAME_REGEX}" | \
		sort -V | tail -n1
}

function vm_resolve_image_artifacts() {
	if [ -n "${VM_IMAGE_FILE:-}" ] && [ -n "${VM_IMAGE_NAME:-}" ] && { [ -n "${VM_CHECKSUM_FILE:-}" ] || [ ! -n "${VM_IMAGE_ARTIFACTS_URL:-}" ]; }; then
		return 0
	fi

	if [ -n "${VM_IMAGE_FILE:-}" ] && [ -n "${VM_IMAGE_NAME:-}" ]; then
		return 0
	fi

	if [ -n "${VM_IMAGE_URL}" ] && [ -z "${VM_IMAGE_BASEURL}" ]; then
		VM_IMAGE_NAME="${VM_IMAGE_NAME:-$(basename "${VM_IMAGE_URL}")}"
		VM_IMAGE_FILE="${VM_IMAGE_FILE:-${VM_IMAGE_DIR}/${VM_IMAGE_NAME}}"
		return 0
	fi

	VM_IMAGE_NAME="${VM_IMAGE_NAME:-$(vm_find_local_image_name)}"
	VM_CHECKSUM_NAME="${VM_CHECKSUM_NAME:-$(vm_find_local_checksum_name)}"

	if [ -z "${VM_IMAGE_NAME}" ]; then
		VM_IMAGE_NAME="$(vm_resolve_remote_image_name)" || exit 1
	fi

	if [ -z "${VM_CHECKSUM_NAME}" ]; then
		VM_CHECKSUM_NAME="$(vm_resolve_remote_checksum_name)" || exit 1
	fi

	[ -n "${VM_IMAGE_NAME}" ] || vm_fatal "Unable to resolve image filename from ${VM_IMAGE_ARTIFACTS_URL}"
	[ -n "${VM_CHECKSUM_NAME}" ] || vm_fatal "Unable to resolve checksum filename from ${VM_IMAGE_ARTIFACTS_URL}"

	VM_IMAGE_URL="${VM_IMAGE_URL:-${VM_IMAGE_ARTIFACTS_URL}${VM_IMAGE_NAME}}"
	VM_CHECKSUM_URL="${VM_CHECKSUM_URL:-${VM_IMAGE_ARTIFACTS_URL}${VM_CHECKSUM_NAME}}"
	VM_IMAGE_FILE="${VM_IMAGE_FILE:-${VM_IMAGE_DIR}/${VM_IMAGE_NAME}}"
	VM_CHECKSUM_FILE="${VM_CHECKSUM_FILE:-${VM_IMAGE_DIR}/$(vm_checksum_cache_name)}"
}

function vm_extract_checksum() {
	local checksum_file="${1}"
	local image_name="${2}"

	awk -v image_name="${image_name}" '
		index($0, image_name) {
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^[A-Fa-f0-9]{64}$/) {
					print $i
					exit
				}
			}
		}
	' "${checksum_file}"
}

function vm_verify_downloaded_image() {
	local expected actual

	vm_require_cmd shasum
	[ -r "${VM_CHECKSUM_FILE}" ] || vm_fatal "Checksum file not found: ${VM_CHECKSUM_FILE}"
	[ -r "${VM_IMAGE_FILE}" ] || vm_fatal "Image file not found: ${VM_IMAGE_FILE}"

	expected="$(vm_extract_checksum "${VM_CHECKSUM_FILE}" "${VM_IMAGE_NAME}")"
	[ -n "${expected}" ] || vm_fatal "Unable to find checksum for ${VM_IMAGE_NAME} in ${VM_CHECKSUM_FILE}"

	actual="$(shasum -a 256 "${VM_IMAGE_FILE}" | awk '{print $1}')"
	[ "${actual}" = "${expected}" ] || vm_fatal "Checksum mismatch for ${VM_IMAGE_NAME}"

	vm_info "Checksum verified for ${VM_IMAGE_NAME}"
}

function vm_read_ssh_key() {
	if [ -n "${VM_SSH_PUBLIC_KEY}" ]; then
		printf "%s\n" "${VM_SSH_PUBLIC_KEY}"
		return 0
	fi

	[ -r "${VM_SSH_KEY_PATH}" ] || vm_fatal "SSH public key not found: ${VM_SSH_KEY_PATH}"
	cat "${VM_SSH_KEY_PATH}"
}

function vm_download_image() {
	vm_require_cmd curl
	vm_ensure_dirs
	vm_step "Resolving VM image artifacts"
	vm_resolve_image_artifacts

	if [ -f "${VM_IMAGE_FILE}" ] && [ -z "${VM_CHECKSUM_FILE:-}" ]; then
		echo "Image already present: ${VM_IMAGE_FILE}"
		return 0
	fi

	if [ -f "${VM_IMAGE_FILE}" ] && [ -f "${VM_CHECKSUM_FILE}" ]; then
		vm_verify_downloaded_image
		echo "Image already present: ${VM_IMAGE_FILE}"
		return 0
	fi

	vm_step "Downloading VM cloud image"
	vm_debug "Image URL: ${VM_IMAGE_URL}"
	vm_debug "Checksum URL: ${VM_CHECKSUM_URL}"

	vm_run curl --fail --location --silent --show-error "${VM_IMAGE_URL}" -o "${VM_IMAGE_FILE}" \
		|| vm_fatal "Download failed: ${VM_IMAGE_URL}"
	vm_run curl --fail --location --silent --show-error "${VM_CHECKSUM_URL}" -o "${VM_CHECKSUM_FILE}" \
		|| vm_fatal "Download failed: ${VM_CHECKSUM_URL}"

	[ "${VM_DRY_RUN}" = "1" ] || vm_verify_downloaded_image

	vm_info "Saved image: ${VM_IMAGE_FILE}"
}

function vm_hdd_payload_file() {
	local hdd_dir="${1}"

	find "${hdd_dir}" -maxdepth 1 -type f -name "*.hds" -print | sort | head -n1
}

function vm_prepare_boot_disk_paths() {
	local image_stem disk_suffix

	vm_resolve_image_artifacts
	image_stem="$(vm_image_stem)"
	disk_suffix="${image_stem}-${VM_DISK_GB}g"

	VM_IMPORT_QCOW2_FILE="${VM_IMPORT_QCOW2_FILE:-${VM_CONVERTED_DIR}/${disk_suffix}.qcow2}"
	VM_IMPORT_RAW_FILE="${VM_IMPORT_RAW_FILE:-${VM_CONVERTED_DIR}/${disk_suffix}.raw}"
	VM_IMPORT_HDS_FILE="${VM_IMPORT_HDS_FILE:-${VM_CONVERTED_DIR}/${disk_suffix}.hds}"
	VM_BOOT_IMAGE_FILE="${VM_BOOT_IMAGE_FILE:-${VM_CONVERTED_DIR}/${disk_suffix}.hdd}"
	VM_BOOT_IMAGE_CHECKSUM_FILE="${VM_BOOT_IMAGE_CHECKSUM_FILE:-${VM_CONVERTED_DIR}/${disk_suffix}.sha256}"
	VM_BOOT_IMAGE_METADATA_FILE="${VM_BOOT_IMAGE_METADATA_FILE:-${VM_CONVERTED_DIR}/${disk_suffix}.metadata}"
}

function vm_cleanup_import_intermediates() {
	rm -f "${VM_IMPORT_QCOW2_FILE}" "${VM_IMPORT_RAW_FILE}" "${VM_IMPORT_HDS_FILE}"
}

function vm_expand_boot_image_archive() {
	[ -n "${VM_BOOT_IMAGE_ARCHIVE:-}" ] || return 1
	[ -f "${VM_BOOT_IMAGE_ARCHIVE}" ] || return 1

	vm_require_cmd tar
	vm_require_cmd zstd
	vm_ensure_dirs

	vm_step "Expanding cached boot disk archive"
	vm_run rm -rf "${VM_BOOT_IMAGE_FILE}" "${VM_BOOT_IMAGE_CHECKSUM_FILE}" "${VM_BOOT_IMAGE_METADATA_FILE}" \
		|| vm_fatal "Failed to clear stale boot disk artifacts before archive expansion"

	(
		cd "${VM_CONVERTED_DIR}" || exit 1
		zstd -dc "${VM_BOOT_IMAGE_ARCHIVE}" | tar -xf -
	) || vm_fatal "Failed to expand boot disk archive: ${VM_BOOT_IMAGE_ARCHIVE}"
}

function vm_write_boot_disk_checksum() {
	(
		cd "${VM_BOOT_IMAGE_FILE}" || exit 1
		find . -maxdepth 1 -type f -print | sort | while IFS= read -r file; do
			shasum -a 256 "${file#./}"
		done > "${VM_BOOT_IMAGE_CHECKSUM_FILE}"
	) || vm_fatal "Failed to write boot disk checksum: ${VM_BOOT_IMAGE_CHECKSUM_FILE}"
}

function vm_write_boot_disk_metadata() {
	cat >"${VM_BOOT_IMAGE_METADATA_FILE}" <<__EOF__ || vm_fatal "Failed to write boot disk metadata: ${VM_BOOT_IMAGE_METADATA_FILE}"
BOOT_IMAGE_FORMAT_VERSION=4
BOOT_IMAGE_NAME=${VM_IMAGE_NAME}
BOOT_DISK_GB=${VM_DISK_GB}
BOOT_VM_ARCH=${VM_ARCH}
BOOT_PARTITION_GB=${VM_BOOT_PARTITION_GB}
__EOF__
}

function vm_verify_boot_disk_metadata() {
	[ -f "${VM_BOOT_IMAGE_METADATA_FILE}" ] || return 1

	local metadata_version=""
	local metadata_image_name=""
	local metadata_disk_gb=""
	local metadata_arch=""
	local metadata_boot_partition_gb=""

	# shellcheck disable=SC1090
	. "${VM_BOOT_IMAGE_METADATA_FILE}" || return 1

	metadata_version="${BOOT_IMAGE_FORMAT_VERSION:-}"
	metadata_image_name="${BOOT_IMAGE_NAME:-}"
	metadata_disk_gb="${BOOT_DISK_GB:-}"
	metadata_arch="${BOOT_VM_ARCH:-}"
	metadata_boot_partition_gb="${BOOT_PARTITION_GB:-}"

	[ "${metadata_version}" = "4" ] || return 1
	[ "${metadata_image_name}" = "${VM_IMAGE_NAME}" ] || return 1
	[ "${metadata_disk_gb}" = "${VM_DISK_GB}" ] || return 1
	[ "${metadata_arch}" = "${VM_ARCH}" ] || return 1
	[ "${metadata_boot_partition_gb}" = "${VM_BOOT_PARTITION_GB}" ] || return 1
}

function vm_verify_boot_disk_checksum() {
	[ -d "${VM_BOOT_IMAGE_FILE}" ] || return 1
	[ -f "${VM_BOOT_IMAGE_CHECKSUM_FILE}" ] || return 1

	(
		cd "${VM_BOOT_IMAGE_FILE}" || exit 1
		shasum -a 256 -c "${VM_BOOT_IMAGE_CHECKSUM_FILE}"
	) 1>/dev/null 2>&1
}

function vm_needs_image_builder() {
	[ -n "${VM_BOOT_PARTITION_GB}" ]
}

function vm_random_suffix() {
	LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6
}

function vm_builder_instance_name() {
	printf "builder-%s\n" "$(vm_random_suffix)"
}

function vm_builder_known_hosts_path() {
	local instance_name="${1}"
	printf "%s/%s.known_hosts\n" "${VM_CACHE_DIR}/ssh-config.d" "${instance_name}"
}

function vm_builder_ssh_args() {
	local known_hosts_path="${1}"
	printf "%s\n" \
		"-F" "/dev/null" \
		"-o" "BatchMode=yes" \
		"-o" "StrictHostKeyChecking=accept-new" \
		"-o" "UserKnownHostsFile=${known_hosts_path}" \
		"-o" "ConnectTimeout=5"
}

function vm_prl_vm_ipv4() {
	local instance_name="${1}"
	local prlctl info_json

	prlctl="$(vm_parallels_bin)"
	info_json="$("${prlctl}" list --info "${instance_name}" --json)" || return 1
	printf "%s\n" "${info_json}" | jq -r '.[0].Network.ipAddresses[]? | select(.type=="ipv4") | .ip' | head -n1
}

function vm_wait_for_builder_ssh() {
	local host_ip="${1}"
	local known_hosts_path="${2}"
	local deadline=$((SECONDS + 300))
	local ssh_args=()

	while IFS= read -r arg; do
		ssh_args+=("${arg}")
	done < <(vm_builder_ssh_args "${known_hosts_path}")

	echo "Waiting for builder SSH on ${host_ip}..."
	while [ "${SECONDS}" -lt "${deadline}" ]; do
		if ssh "${ssh_args[@]}" "ajm@${host_ip}" true 1>/dev/null 2>&1; then
			vm_progress_done
			return 0
		fi
		vm_progress_tick
		sleep 2
	done

	vm_progress_done
	return 1
}

function vm_wait_for_builder_ready() {
	local host_ip="${1}"
	local known_hosts_path="${2}"
	local deadline=$((SECONDS + 1800))
	local ssh_args=()

	while IFS= read -r arg; do
		ssh_args+=("${arg}")
	done < <(vm_builder_ssh_args "${known_hosts_path}")

	echo "Waiting for builder cloud-init to finish on ${host_ip}..."
	while [ "${SECONDS}" -lt "${deadline}" ]; do
		if ssh "${ssh_args[@]}" "ajm@${host_ip}" "test -f /var/lib/cloud/instance/devbox-ready" 1>/dev/null 2>&1; then
			vm_progress_done
			return 0
		fi
		vm_progress_tick
		sleep 5
	done

	vm_progress_done
	return 1
}

function vm_wait_for_builder_ip() {
	local instance_name="${1}"
	local deadline=$((SECONDS + 300))
	local ip=""

	printf "Waiting for builder IP on %s...\n" "${instance_name}" >&2
	while [ "${SECONDS}" -lt "${deadline}" ]; do
		ip="$(vm_prl_vm_ipv4 "${instance_name}")"
		if [ -n "${ip}" ]; then
			printf "\n" >&2
			printf "%s\n" "${ip}"
			return 0
		fi
		printf "." >&2
		sleep 2
	done

	printf "\n" >&2
	return 1
}

function vm_builder_copy_in() {
	local host_ip="${1}"
	local known_hosts_path="${2}"
	local local_path="${3}"
	local remote_path="${4}"
	local scp_args=()

	while IFS= read -r arg; do
		scp_args+=("${arg}")
	done < <(vm_builder_ssh_args "${known_hosts_path}")

	vm_run scp "${scp_args[@]}" "${local_path}" "ajm@${host_ip}:${remote_path}" \
		|| vm_fatal "Failed to copy file into builder VM: ${local_path}"
}

function vm_builder_copy_out() {
	local host_ip="${1}"
	local known_hosts_path="${2}"
	local remote_path="${3}"
	local local_path="${4}"
	local scp_args=()

	while IFS= read -r arg; do
		scp_args+=("${arg}")
	done < <(vm_builder_ssh_args "${known_hosts_path}")

	vm_run scp "${scp_args[@]}" "ajm@${host_ip}:${remote_path}" "${local_path}" \
		|| vm_fatal "Failed to copy file out of builder VM: ${remote_path}"
}

function vm_builder_run() {
	local host_ip="${1}"
	local known_hosts_path="${2}"
	local remote_cmd="${3}"
	local ssh_args=()

	while IFS= read -r arg; do
		ssh_args+=("${arg}")
	done < <(vm_builder_ssh_args "${known_hosts_path}")

	vm_run ssh "${ssh_args[@]}" "ajm@${host_ip}" "${remote_cmd}" \
		|| vm_fatal "Builder command failed: ${remote_cmd}"
}

function vm_cleanup_builder_instance() {
	local instance_name="${1}"

	[ "${VM_KEEP_BUILDER}" = "1" ] && {
		vm_info "Keeping builder VM for debugging: ${instance_name}"
		return 0
	}

	"${BASEPATH}/build_vm.sh" --target "${VM_IMAGE_PREP_TARGET}" --instance "${instance_name}" kill-destroy 1>/dev/null 2>&1 || true
}

function vm_prepare_image_with_builder_vm() {
	local builder_instance builder_known_hosts builder_ip
	local remote_input="/home/ajm/source.qcow2"
	local remote_output="/home/ajm/prepared.hds"
	local remote_script="/home/ajm/prepare-image.sh"

	builder_instance="$(vm_builder_instance_name)"
	builder_known_hosts="$(vm_builder_known_hosts_path "${builder_instance}")"

	vm_info "Preparing image with ephemeral builder VM: ${builder_instance}"

	if [ "${VM_DRY_RUN}" = "1" ]; then
		vm_run "${BASEPATH}/build_vm.sh" --target "${VM_IMAGE_PREP_TARGET}" --instance "${builder_instance}" --action seed,create,boot
		vm_info "Would wait for builder SSH and run image prep inside ${builder_instance}"
		return 0
	fi

	"${BASEPATH}/build_vm.sh" --target "${VM_IMAGE_PREP_TARGET}" --instance "${builder_instance}" --action seed,create,boot \
		|| vm_fatal "Failed to prepare builder VM: ${builder_instance}"

	builder_ip="$(vm_wait_for_builder_ip "${builder_instance}")"
	[ -n "${builder_ip}" ] || {
		vm_cleanup_builder_instance "${builder_instance}"
		vm_fatal "Failed to determine builder VM IP address: ${builder_instance}"
	}

	vm_wait_for_builder_ssh "${builder_ip}" "${builder_known_hosts}" || {
		vm_cleanup_builder_instance "${builder_instance}"
		vm_fatal "Timed out waiting for builder SSH: ${builder_instance}"
	}
	vm_wait_for_builder_ready "${builder_ip}" "${builder_known_hosts}" || {
		vm_cleanup_builder_instance "${builder_instance}"
		vm_fatal "Timed out waiting for builder cloud-init completion: ${builder_instance}"
	}

	vm_builder_copy_in "${builder_ip}" "${builder_known_hosts}" "${VM_IMAGE_FILE}" "${remote_input}"
	vm_builder_copy_in "${builder_ip}" "${builder_known_hosts}" "${BASEPATH}/config/vm-builder/prepare-image.sh" "${remote_script}"

	vm_builder_run "${builder_ip}" "${builder_known_hosts}" \
		"chmod +x ${remote_script} && sudo ${remote_script} ${remote_input} ${remote_output} ${VM_DISK_GB} ${VM_BOOT_PARTITION_GB} ${VM_BOOT_PARTITION_DEVICE} ${VM_ROOT_PARTITION_DEVICE}"

	vm_builder_copy_out "${builder_ip}" "${builder_known_hosts}" "${remote_output}" "${VM_IMPORT_HDS_FILE}"
	vm_cleanup_builder_instance "${builder_instance}"
}

function vm_prepare_boot_disk() {
	local payload_file
	local disk_size="${VM_DISK_GB}G"

	vm_require_cmd cp
	vm_require_cmd rm
	vm_require_cmd find
	vm_require_cmd prlctl
	vm_ensure_dirs
	vm_resolve_image_artifacts
	vm_prepare_boot_disk_paths

	if [ -d "${VM_BOOT_IMAGE_FILE}" ]; then
		if vm_verify_boot_disk_metadata && vm_verify_boot_disk_checksum; then
			vm_info "Verified cached Parallels boot disk: ${VM_BOOT_IMAGE_FILE}"
			return 0
		fi

		echo "Cached Parallels boot disk failed validation; rebuilding."
		[ "${VM_DRY_RUN}" = "1" ] || rm -rf "${VM_BOOT_IMAGE_FILE}" "${VM_BOOT_IMAGE_CHECKSUM_FILE}" "${VM_BOOT_IMAGE_METADATA_FILE}"
	fi

	if [ ! -d "${VM_BOOT_IMAGE_FILE}" ] && [ -n "${VM_BOOT_IMAGE_ARCHIVE:-}" ] && [ -f "${VM_BOOT_IMAGE_ARCHIVE}" ]; then
		vm_expand_boot_image_archive
		if vm_verify_boot_disk_metadata && vm_verify_boot_disk_checksum; then
			vm_info "Restored cached Parallels boot disk from archive: ${VM_BOOT_IMAGE_FILE}"
			return 0
		fi

		echo "Expanded boot disk archive failed validation; rebuilding."
		[ "${VM_DRY_RUN}" = "1" ] || rm -rf "${VM_BOOT_IMAGE_FILE}" "${VM_BOOT_IMAGE_CHECKSUM_FILE}" "${VM_BOOT_IMAGE_METADATA_FILE}"
	fi

	if [ ! -f "${VM_IMAGE_FILE}" ]; then
		vm_download_image
	fi

	vm_step "Preparing reusable Parallels boot disk"
	vm_debug "Source image: ${VM_IMAGE_FILE}"
	vm_debug "Disk size: ${disk_size}"
	vm_debug "Target disk: ${VM_BOOT_IMAGE_FILE}"

	if [ "${VM_IMAGE_SOURCE_FORMAT}" = "parallels-payload" ]; then
		vm_run cp "${VM_IMAGE_FILE}" "${VM_IMPORT_HDS_FILE}" \
			|| vm_fatal "Failed to stage Parallels payload image: ${VM_IMPORT_HDS_FILE}"
	elif vm_needs_image_builder; then
		vm_prepare_image_with_builder_vm
	else
		vm_require_cmd qemu-img
		vm_run cp "${VM_IMAGE_FILE}" "${VM_IMPORT_QCOW2_FILE}" \
			|| vm_fatal "Failed to stage qcow2 for import: ${VM_IMPORT_QCOW2_FILE}"
		vm_run qemu-img resize -f qcow2 "${VM_IMPORT_QCOW2_FILE}" "${disk_size}" \
			|| vm_fatal "Failed to resize qcow2 image: ${VM_IMPORT_QCOW2_FILE}"
		vm_run qemu-img convert -f qcow2 -O raw "${VM_IMPORT_QCOW2_FILE}" "${VM_IMPORT_RAW_FILE}" \
			|| vm_fatal "Failed to convert qcow2 to raw: ${VM_IMPORT_RAW_FILE}"
		vm_run qemu-img convert -f raw -O parallels "${VM_IMPORT_RAW_FILE}" "${VM_IMPORT_HDS_FILE}" \
			|| vm_fatal "Failed to convert raw image to Parallels payload: ${VM_IMPORT_HDS_FILE}"
	fi

	[ "${VM_DRY_RUN}" = "1" ] || rm -rf "${VM_BOOT_IMAGE_FILE}"
	vm_run "/Applications/Parallels Desktop.app/Contents/MacOS/prl_disk_tool" create \
		--hdd "${VM_BOOT_IMAGE_FILE}" \
		--size "${disk_size}" \
		--expanding \
		|| vm_fatal "Failed to create Parallels disk package: ${VM_BOOT_IMAGE_FILE}"

	payload_file="$(vm_hdd_payload_file "${VM_BOOT_IMAGE_FILE}")"
	[ -n "${payload_file}" ] || vm_fatal "Failed to locate payload file in ${VM_BOOT_IMAGE_FILE}"

	vm_run cp "${VM_IMPORT_HDS_FILE}" "${payload_file}" \
		|| vm_fatal "Failed to populate Parallels disk payload: ${payload_file}"

	[ "${VM_DRY_RUN}" = "1" ] || vm_write_boot_disk_checksum
	[ "${VM_DRY_RUN}" = "1" ] || vm_write_boot_disk_metadata
	[ "${VM_DRY_RUN}" = "1" ] || vm_cleanup_import_intermediates

	vm_info "Prepared Parallels boot disk: ${VM_BOOT_IMAGE_FILE}"
}

function vm_clone_boot_disk() {
	vm_require_cmd cp
	vm_require_cmd rm

	vm_step "Cloning VM boot disk"
	vm_prepare_boot_disk_paths
	[ -d "${VM_BOOT_IMAGE_FILE}" ] || vm_fatal "Base boot disk not found: ${VM_BOOT_IMAGE_FILE}"
	if [ "${VM_DRY_RUN}" != "1" ]; then
		[ -d "${VM_BUNDLE_PATH}" ] || vm_fatal "VM bundle path not found: ${VM_BUNDLE_PATH}"
	fi

	[ "${VM_DRY_RUN}" = "1" ] || rm -rf "${VM_VM_DISK_PATH}"
	vm_run cp -R "${VM_BOOT_IMAGE_FILE}" "${VM_VM_DISK_PATH}" \
		|| vm_fatal "Failed to clone base boot disk into VM bundle: ${VM_VM_DISK_PATH}"

	vm_info "Cloned VM boot disk: ${VM_VM_DISK_PATH}"
}

function vm_render_keyboard_block() {
	cat <<__EOF__
keyboard:
  layout: ${VM_KEYBOARD_LAYOUT}
  model: ${VM_KEYBOARD_MODEL}
__EOF__

	[ -n "${VM_KEYBOARD_VARIANT}" ] && printf "  variant: %s\n" "${VM_KEYBOARD_VARIANT}"
	[ -n "${VM_KEYBOARD_OPTIONS}" ] && printf "  options: %s\n" "${VM_KEYBOARD_OPTIONS}"
}

function vm_render_localectl_x11_cmd() {
	local parts=("${VM_KEYBOARD_LAYOUT}" "${VM_KEYBOARD_MODEL}")

	[ -n "${VM_KEYBOARD_VARIANT}" ] && parts+=("${VM_KEYBOARD_VARIANT}")
	[ -n "${VM_KEYBOARD_OPTIONS}" ] && parts+=("${VM_KEYBOARD_OPTIONS}")

	printf "  - [ localectl, set-x11-keymap"
	for part in "${parts[@]}"; do
		printf ", %s" "${part}"
	done
	printf " ]\n"
}

function vm_get_cfg() {
	local key="${1}"
	printf "%s\n" "${!key}"
}

function vm_normalize_mac() {
	local mac="${1}"

	mac="$(printf "%s" "${mac}" | tr '[:upper:]' '[:lower:]' | tr -d ':')"
	printf "%s:%s:%s:%s:%s:%s\n" \
		"${mac:0:2}" "${mac:2:2}" "${mac:4:2}" \
		"${mac:6:2}" "${mac:8:2}" "${mac:10:2}"
}

function vm_ssh_identity_file() {
	case "${VM_SSH_KEY_PATH}" in
		*.pub)
			printf "%s\n" "${VM_SSH_KEY_PATH%.pub}"
			;;
		*)
			printf "%s\n" "${VM_SSH_KEY_PATH}"
			;;
	esac
}

function vm_ssh_base_args() {
	printf "%s\n" \
		"-F" "/dev/null" \
		"-o" "BatchMode=yes" \
		"-o" "StrictHostKeyChecking=accept-new" \
		"-o" "UserKnownHostsFile=${VM_SSH_KNOWN_HOSTS_PATH}" \
		"-o" "ConnectTimeout=5"
}

function vm_ssh_run() {
	local remote_cmd="${1}"
	local ssh_args=()

	while IFS= read -r arg; do
		ssh_args+=("${arg}")
	done < <(vm_ssh_base_args)

	vm_run ssh "${ssh_args[@]}" "${VM_USERNAME}@${VM_SSH_HOSTNAME}" "${remote_cmd}"
}

function vm_wait_for_ssh_up() {
	local ssh_args=()
	local deadline=$((SECONDS + 300))

	while IFS= read -r arg; do
		ssh_args+=("${arg}")
	done < <(vm_ssh_base_args)

	while [ "${SECONDS}" -lt "${deadline}" ]; do
		if ssh "${ssh_args[@]}" "${VM_USERNAME}@${VM_SSH_HOSTNAME}" true 1>/dev/null 2>&1; then
			vm_progress_done
			return 0
		fi
		vm_progress_tick
		sleep 2
	done

	vm_progress_done
	return 1
}

function vm_wait_for_ssh_down() {
	local ssh_args=()
	local deadline=$((SECONDS + 180))

	while IFS= read -r arg; do
		ssh_args+=("${arg}")
	done < <(vm_ssh_base_args)

	while [ "${SECONDS}" -lt "${deadline}" ]; do
		if ! ssh "${ssh_args[@]}" "${VM_USERNAME}@${VM_SSH_HOSTNAME}" true 1>/dev/null 2>&1; then
			vm_progress_done
			return 0
		fi
		vm_progress_tick
		sleep 2
	done

	vm_progress_done
	return 1
}

function vm_wait_for_guest_ready() {
	local deadline=$((SECONDS + 1800))
	local ssh_args=()

	while IFS= read -r arg; do
		ssh_args+=("${arg}")
	done < <(vm_ssh_base_args)

	vm_wait_for_ssh_up || return 1

	while [ "${SECONDS}" -lt "${deadline}" ]; do
		if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${VM_SSH_KNOWN_HOSTS_PATH}" -o ConnectTimeout=5 \
			"${VM_USERNAME}@${VM_SSH_HOSTNAME}" \
			"test -f /var/lib/cloud/instance/devbox-ready" 1>/dev/null 2>&1; then
			vm_progress_done
			return 0
		fi

		if ! ssh "${ssh_args[@]}" "${VM_USERNAME}@${VM_SSH_HOSTNAME}" true 1>/dev/null 2>&1; then
			vm_progress_done
			return 1
		fi
		vm_progress_tick
		sleep 5
	done

	vm_progress_done
	return 1
}

function vm_running_kernel_release() {
	ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${VM_SSH_KNOWN_HOSTS_PATH}" -o ConnectTimeout=5 \
		"${VM_USERNAME}@${VM_SSH_HOSTNAME}" "uname -r" 2>/dev/null
}

function vm_default_kernel_release() {
	ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${VM_SSH_KNOWN_HOSTS_PATH}" -o ConnectTimeout=5 \
		"${VM_USERNAME}@${VM_SSH_HOSTNAME}" "basename \"\$(sudo grubby --default-kernel)\" | sed 's/^vmlinuz-//'" 2>/dev/null
}

function vm_guest_reboot() {
	vm_run ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${VM_SSH_KNOWN_HOSTS_PATH}" -o ConnectTimeout=5 \
		"${VM_USERNAME}@${VM_SSH_HOSTNAME}" "sudo shutdown -r now" || true
}

function vm_wait_for_upgrade_cycle() {
	local running_kernel default_kernel

	[ "${VM_DRY_RUN}" = "1" ] && return 0

	running_kernel="$(vm_running_kernel_release)"
	default_kernel="$(vm_default_kernel_release)"

	if [ -n "${running_kernel}" ] && [ -n "${default_kernel}" ] && [ "${running_kernel}" != "${default_kernel}" ]; then
		echo "Guest upgrade installed a new default kernel (${default_kernel}); rebooting ${VM_NAME}."
		vm_guest_reboot
		vm_wait_for_ssh_down || vm_fatal "Timed out waiting for ${VM_NAME} to begin rebooting"
		vm_wait_for_ssh_up || vm_fatal "Timed out waiting for ${VM_NAME} to come back after reboot"
		running_kernel="$(vm_running_kernel_release)"
		[ "${running_kernel}" = "${default_kernel}" ] || vm_fatal "Guest reboot completed but kernel is still ${running_kernel}, expected ${default_kernel}"
	fi
}

function vm_wait_ready() {
	[ "${VM_DRY_RUN}" = "1" ] && {
		vm_info "Would wait for SSH and cloud-init completion on ${VM_SSH_HOSTNAME}"
		vm_info "Would also wait through any required kernel reboot cycle"
		return 0
	}

	echo "Waiting for guest SSH on ${VM_SSH_HOSTNAME}..."
	vm_wait_for_ssh_up || vm_fatal "Timed out waiting for SSH on ${VM_SSH_HOSTNAME}"

	echo "Waiting for cloud-init to finish inside ${VM_NAME}..."
	vm_wait_for_guest_ready || vm_fatal "Timed out waiting for cloud-init completion in ${VM_NAME}"

	vm_wait_for_upgrade_cycle
}

function vm_network_dns_count() {
	local value="${1}"

	[ -n "${value}" ] || {
		printf "0\n"
		return 0
	}

	printf "%s\n" "${value}" | awk -F',' '{print NF}'
}

function vm_render_network_block() {
	local idx="${1}"
	local prefix="VM_NET_${idx}"
	local name type mac method address gateway dns metric never_default iface
	local dns_entry

	name="$(vm_get_cfg "${prefix}_NAME")"
	type="$(vm_get_cfg "${prefix}_TYPE")"
	mac="$(vm_normalize_mac "$(vm_get_cfg "${prefix}_MAC")")"
	method="$(vm_get_cfg "${prefix}_IPV4_METHOD")"
	address="$(vm_get_cfg "${prefix}_IPV4_ADDRESS")"
	gateway="$(vm_get_cfg "${prefix}_IPV4_GATEWAY")"
	dns="$(vm_get_cfg "${prefix}_IPV4_DNS")"
	metric="$(vm_get_cfg "${prefix}_ROUTE_METRIC")"
	never_default="$(vm_get_cfg "${prefix}_NEVER_DEFAULT")"
	iface="$(vm_get_cfg "${prefix}_PRL_IFACE")"

	printf "  %s:\n" "${name}"
	printf "    match:\n"
	printf "      macaddress: \"%s\"\n" "${mac}"
	printf "    set-name: %s\n" "${name}"
	printf "    dhcp4: false\n"
	printf "    dhcp6: false\n"

	if [ "${method}" = "static" ]; then
		printf "    addresses:\n"
		printf "      - %s\n" "${address}"

		if [ "${never_default}" != "yes" ] && [ -n "${gateway}" ]; then
			printf "    gateway4: %s\n" "${gateway}"
		fi

		if [ -n "${dns}" ]; then
			printf "    nameservers:\n"
			printf "      addresses:\n"
			IFS=',' read -r -a dns_entries <<< "${dns}"
			for dns_entry in "${dns_entries[@]}"; do
				printf "        - %s\n" "${dns_entry}"
			done
		fi
	elif [ "${method}" = "disabled" ]; then
		printf "    link-local: []\n"
	fi

	printf "    optional: true\n"
}

function vm_render_network_config() {
	local idx count

	count="${VM_NET_COUNT:-0}"
	for ((idx = 0; idx < count; idx++)); do
		vm_render_network_block "${idx}"
	done
}

function vm_render_nmconnection_ipv4_block() {
	local method="${1}"
	local address="${2}"
	local gateway="${3}"
	local dns="${4}"
	local metric="${5}"
	local never_default="${6}"

	printf "[ipv4]\n"
	case "${method}" in
		static)
			printf "method=manual\n"
			if [ -n "${gateway}" ]; then
				printf "address1=%s,%s\n" "${address}" "${gateway}"
			else
				printf "address1=%s\n" "${address}"
			fi
			[ -n "${dns}" ] && printf "dns=%s;\n" "${dns}"
			[ -n "${metric}" ] && printf "route-metric=%s\n" "${metric}"
			[ "${never_default}" = "yes" ] && printf "never-default=true\n"
			;;
		disabled)
			printf "method=disabled\n"
			;;
		*)
			printf "method=auto\n"
			;;
	esac
}

function vm_render_nmconnection_content() {
	local idx="${1}"
	local prefix="VM_NET_${idx}"
	local name mac method address gateway dns metric never_default

	name="$(vm_get_cfg "${prefix}_NAME")"
	mac="$(vm_normalize_mac "$(vm_get_cfg "${prefix}_MAC")")"
	method="$(vm_get_cfg "${prefix}_IPV4_METHOD")"
	address="$(vm_get_cfg "${prefix}_IPV4_ADDRESS")"
	gateway="$(vm_get_cfg "${prefix}_IPV4_GATEWAY")"
	dns="$(vm_get_cfg "${prefix}_IPV4_DNS")"
	metric="$(vm_get_cfg "${prefix}_ROUTE_METRIC")"
	never_default="$(vm_get_cfg "${prefix}_NEVER_DEFAULT")"

	printf "[connection]\n"
	printf "id=%s\n" "${name}"
	printf "type=ethernet\n"
	printf "autoconnect=true\n"
	printf "interface-name=%s\n" "${name}"
	printf "\n[ethernet]\n"
	printf "mac-address=%s\n" "${mac}"
	printf "\n"
	vm_render_nmconnection_ipv4_block "${method}" "${address}" "${gateway}" "${dns}" "${metric}" "${never_default}"
	printf "\n[ipv6]\n"
	printf "method=ignore\n"
}

function vm_render_nmconnection_files() {
	local idx count name

	count="${VM_NET_COUNT:-0}"
	for ((idx = 0; idx < count; idx++)); do
		name="$(vm_get_cfg "VM_NET_${idx}_NAME")"
		printf "  - path: /etc/NetworkManager/system-connections/%s.nmconnection\n" "${name}"
		printf "    permissions: \"0600\"\n"
		printf "    owner: root:root\n"
		printf "    content: |\n"
		vm_render_nmconnection_content "${idx}" | sed 's/^/      /'
	done
}

function vm_render_nmcli_apply_cmds() {
	local idx count name

	printf "  - [ sh, -c, \"nmcli connection reload || true\" ]\n"

	count="${VM_NET_COUNT:-0}"
	for ((idx = 0; idx < count; idx++)); do
		name="$(vm_get_cfg "VM_NET_${idx}_NAME")"
		printf "  - [ sh, -c, \"nmcli connection up '%s' || true\" ]\n" "${name}"
	done

	printf "  - [ sh, -c, \"nmcli connection delete 'cloud-init enp0s5' || true\" ]\n"
	printf "  - [ sh, -c, \"nmcli connection delete 'Wired connection 1' || true\" ]\n"
	printf "  - [ sh, -c, \"nmcli connection delete 'Wired connection 2' || true\" ]\n"
	printf "  - [ sh, -c, \"nmcli connection delete 'Wired connection 3' || true\" ]\n"
}

function vm_render_firewalld_runcmd() {
	[ "${VM_DISABLE_FIREWALLD}" = "true" ] || return 0
	printf "  - [ sh, -c, \"systemctl stop firewalld || true\" ]\n"
}

function vm_render_common_service_runcmd() {
	printf "  - [ systemctl, enable, --now, chronyd ]\n"
	printf "  - [ systemctl, enable, --now, containerd ]\n"
	printf "  - [ systemctl, enable, --now, docker ]\n"
	printf "  - [ systemctl, enable, kubelet ]\n"
	printf "  - [ systemctl, enable, --now, fstrim.timer ]\n"
	printf "  - [ systemctl, enable, --now, sshd ]\n"
	printf "  - [ sh, -c, \"echo 'done' > /var/lib/cloud/instance/devbox-ready\" ]\n"
}

function vm_write_instance_state() {
	[ "${VM_DRY_RUN}" = "1" ] && {
		vm_info "Would write instance state: ${VM_INSTANCE_STATE_PATH}"
		return 0
	}

	mkdir -p "${VM_INSTANCE_DIR}" || vm_fatal "Failed to create instance state directory: ${VM_INSTANCE_DIR}"
	cat >"${VM_INSTANCE_STATE_PATH}" <<__EOF__ || vm_fatal "Failed to write instance state: ${VM_INSTANCE_STATE_PATH}"
VM_NAME=${VM_NAME}
VM_TARGET=${VM_TARGET}
VM_HOSTNAME=${VM_HOSTNAME}
VM_FQDN=${VM_FQDN}
VM_USERNAME=${VM_USERNAME}
VM_SSH_HOST_ALIAS=${VM_SSH_HOST_ALIAS}
VM_SSH_HOSTNAME=${VM_SSH_HOSTNAME}
VM_SSH_CONFIG_PATH=${VM_SSH_CONFIG_PATH}
VM_SSH_KNOWN_HOSTS_PATH=${VM_SSH_KNOWN_HOSTS_PATH}
VM_PACKAGE_UPGRADE=${VM_PACKAGE_UPGRADE}
VM_PACKAGE_REBOOT_IF_REQUIRED=${VM_PACKAGE_REBOOT_IF_REQUIRED}
VM_BUNDLE_PATH=${VM_BUNDLE_PATH}
__EOF__
	chmod 600 "${VM_INSTANCE_STATE_PATH}" || vm_fatal "Failed to set permissions on ${VM_INSTANCE_STATE_PATH}"
	vm_info "Updated instance state: ${VM_INSTANCE_STATE_PATH}"
}

function vm_remove_instance_state() {
	if [ "${VM_DRY_RUN}" = "1" ]; then
		vm_info "Would remove instance state: ${VM_INSTANCE_STATE_PATH}"
		return 0
	fi

	if [ -f "${VM_INSTANCE_STATE_PATH}" ]; then
		rm -f "${VM_INSTANCE_STATE_PATH}" || vm_fatal "Failed to remove instance state: ${VM_INSTANCE_STATE_PATH}"
		vm_info "Removed instance state: ${VM_INSTANCE_STATE_PATH}"
	fi
}

function vm_cloud_init_template_path() {
	local filename="${1}"

	if [ -r "${VM_CLOUD_INIT_DIR}/${filename}" ]; then
		printf "%s\n" "${VM_CLOUD_INIT_DIR}/${filename}"
		return 0
	fi

	if [ -r "${VM_CLOUD_INIT_SHARED_DIR}/${filename}" ]; then
		printf "%s\n" "${VM_CLOUD_INIT_SHARED_DIR}/${filename}"
		return 0
	fi

	return 1
}

function vm_expand_template() {
	local template_path="${1}"
	local ssh_key="${2}"
	local line

	while IFS= read -r line || [ -n "${line}" ]; do
		case "${line}" in
			"__VM_KEYBOARD_BLOCK__")
				vm_render_keyboard_block
				continue
				;;
			"__VM_LOCALectl_X11_CMD__")
				vm_render_localectl_x11_cmd
				continue
				;;
			"__VM_NETWORK_CONFIG__")
				vm_render_network_config
				continue
				;;
			"__VM_NMCONNECTION_FILES__")
				vm_render_nmconnection_files
				continue
				;;
			"__VM_NMCLI_APPLY_CMDS__")
				vm_render_nmcli_apply_cmds
				continue
				;;
			"__VM_FIREWALLD_RUNCMD__")
				vm_render_firewalld_runcmd
				continue
				;;
			"__VM_COMMON_SERVICE_RUNCMD__")
				vm_render_common_service_runcmd
				continue
				;;
		esac

		line="${line//__VM_INSTANCE_ID__/${VM_INSTANCE_ID}}"
		line="${line//__VM_HOSTNAME__/${VM_HOSTNAME}}"
		line="${line//__VM_FQDN__/${VM_FQDN}}"
		line="${line//__VM_TIMEZONE__/${VM_TIMEZONE}}"
		line="${line//__VM_USERNAME__/${VM_USERNAME}}"
		line="${line//__VM_KEYBOARD_VC_KEYMAP__/${VM_KEYBOARD_VC_KEYMAP}}"
		line="${line//__VM_K8S_CHANNEL__/${VM_K8S_CHANNEL}}"
		line="${line//__VM_CHRONY_MAKESTEP__/${VM_CHRONY_MAKESTEP}}"
		line="${line//__VM_PACKAGE_UPGRADE__/${VM_PACKAGE_UPGRADE}}"
		line="${line//__VM_PACKAGE_REBOOT_IF_REQUIRED__/${VM_PACKAGE_REBOOT_IF_REQUIRED}}"
		line="${line//__VM_SSH_PUBLIC_KEY__/${ssh_key}}"
		printf "%s\n" "${line}"
	done <"${template_path}"
}

function vm_render_template() {
	local template_path="${1}"
	local ssh_key

	[ -r "${template_path}" ] || vm_fatal "Template not readable: ${template_path}"

	ssh_key="$(vm_read_ssh_key)" || exit 1
	vm_expand_template "${template_path}" "${ssh_key}" || vm_fatal "Failed to render template: ${template_path}"
}

function vm_create_seed_iso() {
	local user_data_template meta_data_template network_config_template

	vm_step "Rendering cloud-init seed"
	vm_require_cmd hdiutil
	vm_ensure_dirs

	[ -d "${VM_CLOUD_INIT_DIR}" ] || vm_fatal "cloud-init directory not found: ${VM_CLOUD_INIT_DIR}"
	user_data_template="$(vm_cloud_init_template_path user-data)" || vm_fatal "user-data template not found for ${VM_TARGET}"
	meta_data_template="$(vm_cloud_init_template_path meta-data)" || vm_fatal "meta-data template not found for ${VM_TARGET}"
	network_config_template="$(vm_cloud_init_template_path network-config || true)"

	vm_render_template "${user_data_template}" >"${VM_SEED_DIR}/user-data" || vm_fatal "Failed to render user-data"
	vm_render_template "${meta_data_template}" >"${VM_SEED_DIR}/meta-data" || vm_fatal "Failed to render meta-data"
	vm_verify_structured_file yaml "${VM_SEED_DIR}/user-data"
	vm_verify_structured_file yaml "${VM_SEED_DIR}/meta-data"

	if [ -n "${network_config_template}" ]; then
		vm_render_template "${network_config_template}" >"${VM_SEED_DIR}/network-config" \
			|| vm_fatal "Failed to render network-config"
		vm_verify_structured_file yaml "${VM_SEED_DIR}/network-config"
	else
		[ "${VM_DRY_RUN}" = "1" ] || rm -f "${VM_SEED_DIR}/network-config"
	fi

	[ "${VM_DRY_RUN}" = "1" ] || rm -f "${VM_SEED_ISO}"

	vm_run hdiutil makehybrid \
		-quiet \
		-iso \
		-joliet \
		-default-volume-name cidata \
		-o "${VM_SEED_ISO}" \
		"${VM_SEED_DIR}" \
		|| vm_fatal "Failed to create cloud-init seed ISO"

	vm_info "Created seed ISO: ${VM_SEED_ISO}"
}

function vm_kill_destroy() {
	vm_kill
	vm_destroy
}

function vm_stop_destroy() {
	vm_down
	vm_destroy
}

function vm_create_boot() {
	vm_create
	vm_boot
	vm_wait_ready
}

function vm_full_recycle() {
	vm_kill
	vm_destroy
	vm_create
	vm_boot
	vm_wait_ready
}

function vm_parallels_bin() {
	printf "%s\n" "/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
}

function vm_prl_list_names() {
	local prlctl

	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	"${prlctl}" list --all -o name 2>/dev/null
}

function vm_exists() {
	vm_prl_list_names | awk 'NR > 1 {print}' | grep -Fx "${VM_NAME}" 1>/dev/null 2>&1
}

function vm_current_state() {
	local prlctl

	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	"${prlctl}" list --all -o name,status 2>/dev/null | awk -v name="${VM_NAME}" 'NR > 1 && $1 == name {print $2; exit}'
}

function vm_is_running() {
	local state

	state="$(vm_current_state)"
	[ -n "${state}" ] || return 1

	case "${state}" in
		stopped|suspended)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

function vm_existing_home_path() {
	local prlctl

	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	"${prlctl}" list --info "${VM_NAME}" 2>/dev/null | awk -F': ' '/^Home path:/ {print $2; exit}'
}

function vm_prl_set() {
	local prlctl="${1}"
	shift
	vm_run_quiet "${prlctl}" set "${VM_NAME}" "$@" || vm_fatal "prlctl set failed: ${VM_NAME} $*"
}

function vm_prl_ensure_share() {
	local prlctl="${1}"
	local name="${2}"
	local path="${3}"
	local mode="${4:-rw}"

	if [ ! -d "${path}" ]; then
		echo "Skipping shared folder ${name}, path not found: ${path}"
		return 0
	fi

	if [ "${VM_DRY_RUN}" = "1" ]; then
		vm_run "${prlctl}" set "${VM_NAME}" --shf-host-set "${name}" --path "${path}" --mode "${mode}" --enable
		return 0
	fi

	if ! vm_try_quiet "${prlctl}" set "${VM_NAME}" --shf-host-set "${name}" --path "${path}" --mode "${mode}" --enable; then
		vm_run_quiet "${prlctl}" set "${VM_NAME}" --shf-host-add "${name}" --path "${path}" --mode "${mode}" --enable \
			|| vm_fatal "Failed to add shared folder ${name}: ${path}"
	fi

	vm_info "Configured shared folder: ${name}"
}

function vm_apply_prl_config() {
	local prlctl
	local nested_status
	local sound_status
	local prl_args

	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"

	prl_args=(
		--autostart "${PRL_AUTOSTART}"
		--autostop "${PRL_AUTOSTOP}"
		--startup-view "${PRL_STARTUP_VIEW}"
		--on-shutdown "${PRL_ON_SHUTDOWN}"
		--on-window-close "${PRL_ON_WINDOW_CLOSE}"
		--pause-idle "${PRL_PAUSE_IDLE}"
		--adaptive-hypervisor "${PRL_ADAPTIVE_HYPERVISOR}"
		--shared-profile "${PRL_SHARED_PROFILE}"
		--smart-mount "${PRL_SMART_MOUNT}"
		--shf-host "${PRL_SHARE_HOST_FOLDERS}"
		--shf-host-automount "${PRL_SHARE_HOST_FOLDERS_AUTOMOUNT}"
		--shf-guest "${PRL_SHARE_GUEST_FOLDERS}"
		--fullscreen-use-all-displays "${PRL_FULL_SCREEN_USE_ALL_DISPLAYS}"
		--auto-switch-fullscreen "${PRL_COHERENCE_AUTO_SWITCH_FULLSCREEN}"
		--show-guest-notifications "${PRL_SHOW_GUEST_NOTIFICATIONS}"
		--show-guest-app-folder-in-dock "${PRL_SHOW_GUEST_APP_FOLDER_IN_DOCK}"
		--bounce-dock-icon-when-app-flashes "${PRL_BOUNCE_DOCK_ICON_WHEN_APP_FLASHES}"
		--sh-app-host-to-guest "${PRL_SH_APP_HOST_TO_GUEST}"
		--sh-app-guest-to-host "${PRL_SH_APP_GUEST_TO_HOST}"
		--winsystray-in-macmenu "${PRL_WINSYSTRAY_IN_MACMENU}"
		--shared-clipboard "${PRL_SHARED_CLIPBOARD}"
		--time-sync "${PRL_TIME_SYNC}"
		--shared-cloud "${PRL_SHARED_CLOUD}"
		--sync-host-printers "${PRL_SYNC_HOST_PRINTERS}"
		--sync-default-printer "${PRL_SYNC_DEFAULT_PRINTER}"
		--show-host-printer-ui "${PRL_SHOW_HOST_PRINTER_UI}"
		--auto-share-camera "${PRL_AUTO_SHARE_CAMERA}"
	)

	[ -n "${PRL_SHARE_HOST_FOLDERS_DEFINED}" ] && prl_args+=(--shf-host-defined "${PRL_SHARE_HOST_FOLDERS_DEFINED}")

	vm_prl_set "${prlctl}" "${prl_args[@]}"

	if [ "${HOST_ARCH}" = "x86_64" ]; then
		vm_prl_set "${prlctl}" --nested-virt "${PRL_NESTED_VIRT}"
		nested_status="Applied nested virtualization: ${PRL_NESTED_VIRT}"
	else
		nested_status="Skipped nested virtualization on ${HOST_ARCH}; Parallels documents nested virtualization as Intel-only."
	fi

	if [ "${PRL_SOUND}" = "off" ] && [ "${PRL_MICROPHONE}" = "off" ]; then
		if [ "${VM_DRY_RUN}" = "1" ]; then
			vm_run "${prlctl}" set "${VM_NAME}" --device-del sound0
			sound_status="Would remove VM sound device to disable sound output and microphone."
		elif "${prlctl}" set "${VM_NAME}" --device-del sound0 1>/dev/null 2>&1; then
			sound_status="Removed VM sound device to disable sound output and microphone."
		else
			sound_status="Unable to remove sound device automatically; GUI check may still be needed."
		fi
	else
		sound_status="Sound device left unchanged because PRL_SOUND/PRL_MICROPHONE are not both off."
	fi

	if [ "${PRL_SHARE_HOST_FOLDERS}" = "on" ]; then
		if [ "${PRL_SHARE_HOST_FOLDER_DOWNLOADS}" = "on" ]; then
			vm_prl_ensure_share "${prlctl}" \
				"${PRL_SHARE_HOST_FOLDER_DOWNLOADS_NAME}" \
				"${PRL_SHARE_HOST_FOLDER_DOWNLOADS_PATH}" \
				"rw"
		fi

		if [ "${PRL_SHARE_HOST_FOLDER_DEVELOP}" = "on" ]; then
			vm_prl_ensure_share "${prlctl}" \
				"${PRL_SHARE_HOST_FOLDER_DEVELOP_NAME}" \
				"${PRL_SHARE_HOST_FOLDER_DEVELOP_PATH}" \
				"rw"
		fi
	fi

	cat <<__EOF__
Applied Parallels CLI-backed settings for ${VM_NAME}.

  Adaptive hypervisor:          ${PRL_ADAPTIVE_HYPERVISOR}
  ${nested_status}
  Camera sharing:               ${PRL_AUTO_SHARE_CAMERA}
  ${sound_status}

Not applied from CLI yet and may require GUI verification:
  Picture in Picture:          ${PRL_PICTURE_IN_PICTURE}
  Travel mode enter:           ${PRL_TRAVEL_MODE_ENTER}
  Travel mode quit:            ${PRL_TRAVEL_MODE_QUIT}
  Auto-update Parallels Tools: ${PRL_AUTO_UPDATE_TOOLS}
__EOF__
}

function vm_prl_ensure_net() {
	local prlctl="${1}"
	local index="${2}"
	local prefix="VM_NET_${index}"
	local device="net${index}"
	local add_device="net"
	local type iface mac
	local args

	type="$(vm_get_cfg "${prefix}_TYPE")"
	iface="$(vm_get_cfg "${prefix}_PRL_IFACE")"
	mac="$(vm_get_cfg "${prefix}_MAC")"

	if [ "${VM_DRY_RUN}" = "1" ]; then
		args=("${prlctl}" set "${VM_NAME}" --device-set "${device}" --type "${type}")
		[ -n "${iface}" ] && args+=(--iface "${iface}")
		[ -n "${mac}" ] && args+=(--mac "${mac}")
		args+=(--dhcp no --dhcp6 no --configure no --adapter-type virtio)
		vm_run "${args[@]}"
		return 0
	fi

	if vm_prl_device_exists "${prlctl}" "${device}"; then
		args=("${prlctl}" set "${VM_NAME}" --device-set "${device}" --type "${type}")
		[ -n "${iface}" ] && args+=(--iface "${iface}")
		[ -n "${mac}" ] && args+=(--mac "${mac}")
		args+=(--dhcp no --dhcp6 no --configure no --adapter-type virtio)
		vm_run_quiet "${args[@]}" || vm_fatal "Failed to configure network adapter ${device}"
	else
		args=("${prlctl}" set "${VM_NAME}" --device-add "${add_device}" --type "${type}")
		[ -n "${iface}" ] && args+=(--iface "${iface}")
		[ -n "${mac}" ] && args+=(--mac "${mac}")
		args+=(--dhcp no --dhcp6 no --configure no --adapter-type virtio)
		vm_run_quiet "${args[@]}" || vm_fatal "Failed to add network adapter ${device}"
	fi

	vm_info "Configured device: ${device} (${type})"
}

function vm_attach_network_adapters() {
	local prlctl="${1}"
	local idx count

	count="${VM_NET_COUNT:-0}"
	for ((idx = 0; idx < count; idx++)); do
		vm_prl_ensure_net "${prlctl}" "${idx}"
	done
}

function vm_create_vm_shell() {
	local prlctl="${1}"
	local existing_home

	vm_run mkdir -p "${VM_PARALLELS_DIR}" || vm_fatal "Failed to create Parallels directory"

	if [ "${VM_DRY_RUN}" != "1" ] && vm_exists; then
		existing_home="$(vm_existing_home_path)"

		if [ "${VM_RECREATE}" = "1" ]; then
			vm_info "Recreating existing VM: ${VM_NAME}"
			vm_destroy
		else
			cat <<__EOF__
VM already exists in Parallels: ${VM_NAME}
Existing home path: ${existing_home}
Expected home path: ${VM_BUNDLE_PATH}/config.pvs

Refusing to reuse an existing registration automatically because stale device
state can cause misleading 'invalid image' errors.

Use one of:
  VM_RECREATE=1 ./build_vm.sh --target ${VM_TARGET} create
  ./build_vm.sh --target ${VM_TARGET} destroy
__EOF__
			exit 1
		fi
	fi

	vm_run_quiet "${prlctl}" create "${VM_NAME}" --distribution "${VM_PRL_DISTRIBUTION}" --dst "${VM_PARALLELS_DIR}" \
		|| vm_fatal "Failed to create VM shell: ${VM_NAME}"
	vm_info "Created VM shell: ${VM_NAME}"
}

function vm_attach_boot_media() {
	local prlctl="${1}"

	vm_prepare_boot_disk_paths
	vm_prl_set "${prlctl}" --cpus "${VM_CPUS}" --memsize "${VM_MEMORY_MB}" --efi-boot on
	vm_info "Configured VM hardware: ${VM_CPUS} CPU / ${VM_MEMORY_MB} MB RAM"
	vm_attach_network_adapters "${prlctl}"
	vm_prl_set "${prlctl}" --device-set hdd0 --image "${VM_VM_DISK_PATH}" --online-compact "${PRL_HDD_ONLINE_COMPACT}"
	vm_info "Configured device: hdd0"
	vm_prl_set "${prlctl}" --device-set cdrom0 --image "${VM_SEED_ISO}" --connect
	vm_info "Configured device: cdrom0"
}

function vm_create() {
	local prlctl

	vm_step "Creating VM ${VM_NAME}"
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	vm_resolve_image_artifacts
	vm_prepare_boot_disk_paths
	if [ "${VM_DRY_RUN}" != "1" ]; then
		[ -f "${VM_IMAGE_FILE}" ] || vm_fatal "Cloud image not found: ${VM_IMAGE_FILE}"
		[ -d "${VM_BOOT_IMAGE_FILE}" ] || vm_prepare_boot_disk
		[ -f "${VM_SEED_ISO}" ] || vm_fatal "Seed ISO not found: ${VM_SEED_ISO}"
	fi
	vm_create_vm_shell "${prlctl}"
	vm_clone_boot_disk
	vm_attach_boot_media "${prlctl}"
	vm_apply_prl_config
	vm_install_ssh_config
	vm_write_instance_state

	cat <<__EOF__
VM prepared: ${VM_NAME}

  Target:      ${VM_TARGET}
  Host arch:   ${HOST_ARCH}
  Guest arch:  ${VM_ARCH}
  CPUs:        ${VM_CPUS}
  RAM (MB):    ${VM_MEMORY_MB}
  Image file:  ${VM_IMAGE_FILE}
  Base disk:   ${VM_BOOT_IMAGE_FILE}
  VM disk:     ${VM_VM_DISK_PATH}
  Seed ISO:    ${VM_SEED_ISO}
  VM bundle:   ${VM_BUNDLE_PATH}
__EOF__
}

function vm_boot() {
	local prlctl
	vm_step "Starting VM ${VM_NAME}"
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	vm_run_quiet "${prlctl}" start "${VM_NAME}" || vm_fatal "Failed to start VM: ${VM_NAME}"
	vm_info "Started VM: ${VM_NAME}"
}

function vm_reboot() {
	[ "${VM_DRY_RUN}" = "1" ] && {
		vm_step "Requesting guest reboot for ${VM_NAME}"
		vm_run ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${VM_SSH_KNOWN_HOSTS_PATH}" -o ConnectTimeout=5 \
			"${VM_USERNAME}@${VM_SSH_HOSTNAME}" "sudo systemctl reboot"
		return 0
	}

	vm_step "Requesting guest reboot for ${VM_NAME}"
	if ! vm_wait_for_ssh_up; then
		vm_fatal "SSH is not reachable for ${VM_NAME}; use kill if you need to force-stop it."
	fi

	vm_run ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${VM_SSH_KNOWN_HOSTS_PATH}" -o ConnectTimeout=5 \
		"${VM_USERNAME}@${VM_SSH_HOSTNAME}" "sudo systemctl reboot" \
		|| vm_fatal "Failed to request guest reboot for ${VM_NAME}"

	vm_wait_for_ssh_down || vm_fatal "Timed out waiting for ${VM_NAME} to begin rebooting"
	vm_wait_for_ssh_up || vm_fatal "Timed out waiting for ${VM_NAME} to come back after reboot"
}

function vm_tools_update() {
	local prlctl

	vm_step "Triggering Parallels Tools update for ${VM_NAME}"
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"

	if [ "${VM_DRY_RUN}" != "1" ] && ! vm_exists; then
		vm_fatal "VM is not registered in Parallels: ${VM_NAME}"
	fi

	vm_run_quiet "${prlctl}" installtools "${VM_NAME}" \
		|| vm_fatal "Failed to trigger Parallels Tools install/update for ${VM_NAME}"

	cat <<__EOF__
Triggered Parallels Tools install/update for ${VM_NAME}.

Notes:
  - The VM must be running for this to work.
  - This is intended as a manual maintenance step after kernel upgrades.
  - Linux guests typically need a reboot after Tools are installed or updated.
__EOF__
}

function vm_down() {
	[ "${VM_DRY_RUN}" = "1" ] && {
		vm_step "Requesting guest shutdown for ${VM_NAME}"
		vm_run ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${VM_SSH_KNOWN_HOSTS_PATH}" -o ConnectTimeout=5 \
			"${VM_USERNAME}@${VM_SSH_HOSTNAME}" "sudo shutdown -P now"
		return 0
	}

	vm_step "Requesting guest shutdown for ${VM_NAME}"
	if ! vm_wait_for_ssh_up; then
		vm_fatal "SSH is not reachable for ${VM_NAME}; use kill if you need to force-stop it."
	fi

	vm_run ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${VM_SSH_KNOWN_HOSTS_PATH}" -o ConnectTimeout=5 \
		"${VM_USERNAME}@${VM_SSH_HOSTNAME}" "sudo shutdown -P now" \
		|| vm_fatal "Failed to request guest poweroff for ${VM_NAME}"

	vm_wait_for_ssh_down || vm_fatal "Timed out waiting for ${VM_NAME} to power off"
}

function vm_kill() {
	local prlctl
	vm_step "Force-stopping VM ${VM_NAME}"
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	vm_run_quiet "${prlctl}" stop "${VM_NAME}" --kill || vm_fatal "Failed to force-stop VM: ${VM_NAME}"
	vm_info "Force-stopped VM: ${VM_NAME}"
}

function vm_destroy() {
	local prlctl state
	vm_step "Deleting VM ${VM_NAME}"
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"

	if [ "${VM_DRY_RUN}" != "1" ] && vm_is_running; then
		state="$(vm_current_state)"
		vm_fatal "Refusing to destroy ${VM_NAME} while it is ${state}. Use down or kill first."
	fi

	vm_run_quiet "${prlctl}" delete "${VM_NAME}" || vm_fatal "Failed to delete VM: ${VM_NAME}"
	vm_info "Deleted VM: ${VM_NAME}"
	vm_remove_ssh_config
	vm_remove_instance_state
}

function vm_status() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	vm_run "${prlctl}" list --all
}

function vm_print_ssh_config() {
	cat <<__EOF__
Host ${VM_SSH_HOST_ALIAS}
    HostName ${VM_SSH_HOSTNAME}
    User ${VM_USERNAME}
    IdentityFile $(vm_ssh_identity_file)
    UserKnownHostsFile ${VM_SSH_KNOWN_HOSTS_PATH}
    StrictHostKeyChecking accept-new
__EOF__
}

function vm_install_ssh_config() {
	local config_dir managed_begin managed_end temp_file

	[ "${VM_INSTALL_SSH_CONFIG}" = "true" ] || return 0

	vm_step "Writing repo-local SSH config include"
	config_dir="$(dirname "${VM_SSH_CONFIG_PATH}")"
	managed_begin="# builder-vm:${VM_TARGET}:${VM_SSH_HOST_ALIAS}:begin"
	managed_end="# builder-vm:${VM_TARGET}:${VM_SSH_HOST_ALIAS}:end"

	[ "${VM_DRY_RUN}" = "1" ] && {
		vm_info "Would install SSH config block into ${VM_SSH_CONFIG_PATH}:"
		printf "%s\n" "${managed_begin}"
		vm_print_ssh_config
		printf "%s\n" "${managed_end}"
		printf "\nAdd this to ~/.ssh/config if you have not already:\n"
		printf "Include %s/*.conf\n" "${VM_SSH_CONFIG_DIR}"
		return 0
	}

	mkdir -p "${config_dir}" || vm_fatal "Failed to create SSH config directory: ${config_dir}"
	[ -f "${VM_SSH_CONFIG_PATH}" ] || : >"${VM_SSH_CONFIG_PATH}"
	[ -f "${VM_SSH_KNOWN_HOSTS_PATH}" ] || : >"${VM_SSH_KNOWN_HOSTS_PATH}"
	chmod 700 "${config_dir}" || vm_fatal "Failed to set permissions on ${config_dir}"
	chmod 600 "${VM_SSH_CONFIG_PATH}" || vm_fatal "Failed to set permissions on ${VM_SSH_CONFIG_PATH}"
	chmod 600 "${VM_SSH_KNOWN_HOSTS_PATH}" || vm_fatal "Failed to set permissions on ${VM_SSH_KNOWN_HOSTS_PATH}"

	temp_file="$(mktemp "${TMPDIR:-/tmp}/builder-ssh-config.XXXXXX")" || vm_fatal "Failed to create temp file"

	awk -v begin="${managed_begin}" -v end="${managed_end}" '
		$0 == begin { skip=1; next }
		$0 == end { skip=0; next }
		skip != 1 { print }
	' "${VM_SSH_CONFIG_PATH}" >"${temp_file}" || {
		rm -f "${temp_file}"
		vm_fatal "Failed to rewrite ${VM_SSH_CONFIG_PATH}"
	}

	{
		cat "${temp_file}"
		[ -s "${temp_file}" ] && printf "\n"
		printf "%s\n" "${managed_begin}"
		vm_print_ssh_config
		printf "%s\n" "${managed_end}"
	} >"${VM_SSH_CONFIG_PATH}" || {
		rm -f "${temp_file}"
		vm_fatal "Failed to update ${VM_SSH_CONFIG_PATH}"
	}

	rm -f "${temp_file}"
	vm_info "Updated SSH config: ${VM_SSH_CONFIG_PATH}"
	vm_info "Add this to ~/.ssh/config if you have not already:"
	vm_info "Include ${VM_SSH_CONFIG_DIR}/*.conf"
}

function vm_remove_ssh_config() {
	if [ "${VM_DRY_RUN}" = "1" ]; then
		vm_info "Would remove SSH config: ${VM_SSH_CONFIG_PATH}"
		vm_info "Would remove known hosts: ${VM_SSH_KNOWN_HOSTS_PATH}"
		return 0
	fi

	if [ -f "${VM_SSH_CONFIG_PATH}" ]; then
		rm -f "${VM_SSH_CONFIG_PATH}" || vm_fatal "Failed to remove SSH config: ${VM_SSH_CONFIG_PATH}"
		vm_info "Removed SSH config: ${VM_SSH_CONFIG_PATH}"
	fi

	if [ -f "${VM_SSH_KNOWN_HOSTS_PATH}" ]; then
		rm -f "${VM_SSH_KNOWN_HOSTS_PATH}" || vm_fatal "Failed to remove known hosts: ${VM_SSH_KNOWN_HOSTS_PATH}"
		vm_info "Removed known hosts: ${VM_SSH_KNOWN_HOSTS_PATH}"
	fi
}

function vm_dispatch_action() {
	local action="${1}"

	case "${action}" in
		image)
			vm_download_image
			vm_prepare_boot_disk
			;;
		seed)
			vm_create_seed_iso
			;;
		create)
			vm_create
			;;
		create-boot)
			vm_create_boot
			;;
		prl-config)
			vm_apply_prl_config
			;;
		tools-update|tools-install|install-tools)
			vm_tools_update
			;;
		boot|start)
			vm_boot
			;;
		reboot|restart)
			vm_reboot
			;;
		wait|wait-ready)
			vm_wait_ready
			;;
		down|stop)
			vm_down
			;;
		kill|force-stop)
			vm_kill
			;;
		stop-destroy)
			vm_stop_destroy
			;;
		kill-destroy)
			vm_kill_destroy
			;;
		destroy|delete)
			vm_destroy
			;;
		full-recycle)
			vm_full_recycle
			;;
		status)
			vm_status
			;;
		ssh-config)
			vm_install_ssh_config
			;;
		ssh-config-print)
			vm_print_ssh_config
			;;
		up)
			vm_download_image
			vm_prepare_boot_disk
			vm_create_seed_iso
			vm_create
			vm_boot
			vm_wait_for_upgrade_cycle
			;;
		help|-h|--help)
			return 2
			;;
		*)
			vm_fatal "Unknown action: ${action}"
			;;
	esac
}

function vm_run_action_list() {
	local actions_csv="${1}"
	local action
	local old_ifs="${IFS}"

	IFS=','
	for action in ${actions_csv}; do
		action="$(printf "%s" "${action}" | awk '{$1=$1; print}')"
		[ -n "${action}" ] || continue
		vm_dispatch_action "${action}"
	done
	IFS="${old_ifs}"
}
