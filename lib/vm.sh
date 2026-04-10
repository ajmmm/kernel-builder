#!/usr/bin/env bash

function vm_fatal() {
	echo "FATAL ERROR: $@"
	exit 1
}

function vm_require_cmd() {
	local cmd="${1}"

	command -v "${cmd}" 1>/dev/null 2>&1 || vm_fatal "I need ${cmd}!"
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

function vm_default_image_url() {
	local release="${VM_FEDORA_RELEASE}"
	local arch="${VM_ARCH}"

	printf "%s\n" "https://download.fedoraproject.org/pub/fedora/linux/releases/${release}/Cloud/${arch}/images/Fedora-Cloud-Base-Generic.${arch}.qcow2"
}

function vm_target_name() {
	printf "%s\n" "fc${VM_FEDORA_RELEASE}/fedora"
}

function vm_target_dir() {
	printf "%s\n" "${BASEPATH}/${VM_TARGET}"
}

function vm_load_target_config() {
	VM_TARGET_DIR="${VM_TARGET_DIR:-$(vm_target_dir)}"
	VM_CONFIG_FILE="${VM_CONFIG_FILE:-${VM_TARGET_DIR}/vm.conf}"

	if [ -r "${VM_CONFIG_FILE}" ]; then
		. "${VM_CONFIG_FILE}" || vm_fatal "Failed to load target config: ${VM_CONFIG_FILE}"
	fi
}

function vm_init_defaults() {
	[ -n "${BASEPATH}" ] || vm_fatal "BASEPATH is undefined"

	VM_FEDORA_RELEASE="${VM_FEDORA_RELEASE:-43}"
	VM_TARGET="${VM_TARGET:-$(vm_target_name)}"
	vm_load_target_config

	VM_NAME="${VM_NAME:-fedora-dev}"
	VM_HOSTNAME="${VM_HOSTNAME:-${VM_NAME}}"
	VM_FQDN="${VM_FQDN:-${VM_HOSTNAME}.local}"
	VM_USERNAME="${VM_USERNAME:-dev}"
	VM_CPUS="${VM_CPUS:-6}"
	VM_MEMORY_MB="${VM_MEMORY_MB:-12288}"
	VM_DISK_GB="${VM_DISK_GB:-120}"
	VM_TIMEZONE="${VM_TIMEZONE:-Europe/London}"
	VM_KEYBOARD_LAYOUT="${VM_KEYBOARD_LAYOUT:-gb}"
	VM_KEYBOARD_MODEL="${VM_KEYBOARD_MODEL:-pc105}"
	VM_KEYBOARD_VARIANT="${VM_KEYBOARD_VARIANT:-}"
	VM_KEYBOARD_OPTIONS="${VM_KEYBOARD_OPTIONS:-}"
	VM_K8S_CHANNEL="${VM_K8S_CHANNEL:-v1.35}"
	VM_CHRONY_MAKESTEP="${VM_CHRONY_MAKESTEP:-1.0 3}"
	VM_ARCH="${VM_ARCH:-$(vm_guess_arch)}"
	VM_CACHE_DIR="${VM_CACHE_DIR:-${BASEPATH}/.cache}"
	VM_IMAGE_DIR="${VM_IMAGE_DIR:-${VM_CACHE_DIR}/images}"
	VM_SEED_DIR="${VM_SEED_DIR:-${VM_CACHE_DIR}/seed/${VM_NAME}}"
	VM_PARALLELS_DIR="${VM_PARALLELS_DIR:-${VM_CACHE_DIR}/parallels}"
	VM_CLOUD_INIT_DIR="${VM_CLOUD_INIT_DIR:-${VM_TARGET_DIR}/cloud-init}"
	VM_IMAGE_URL="${VM_IMAGE_URL:-$(vm_default_image_url)}"
	VM_IMAGE_FILE="${VM_IMAGE_FILE:-${VM_IMAGE_DIR}/$(basename "${VM_IMAGE_URL}")}"
	VM_SEED_ISO="${VM_SEED_ISO:-${VM_SEED_DIR}/seed.iso}"
	VM_INSTANCE_ID="${VM_INSTANCE_ID:-${VM_NAME}-01}"
	VM_SSH_KEY_PATH="${VM_SSH_KEY_PATH:-${HOME}/.ssh/id_ed25519.pub}"
}

function vm_parse_args() {
	while [ "$#" -gt 0 ]; do
		case "${1}" in
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

			--help|-h)
				printf "%s\n" "help"
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

	if [ "$#" -gt 0 ]; then
		printf "%s\n" "${1}"
	else
		printf "%s\n" "help"
	fi
}

function vm_ensure_dirs() {
	mkdir -p "${VM_CACHE_DIR}" "${VM_IMAGE_DIR}" "${VM_SEED_DIR}" "${VM_PARALLELS_DIR}" \
		|| vm_fatal "Failed to create cache directories"
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

	if [ -f "${VM_IMAGE_FILE}" ]; then
		echo "Image already present: ${VM_IMAGE_FILE}"
		return 0
	fi

	echo "Downloading Fedora cloud image ..."
	echo "URL: ${VM_IMAGE_URL}"

	curl --fail --location --silent --show-error "${VM_IMAGE_URL}" -o "${VM_IMAGE_FILE}" \
		|| vm_fatal "Download failed: ${VM_IMAGE_URL}"

	echo "Saved: ${VM_IMAGE_FILE}"
}

function vm_render_template() {
	local template_path="${1}"
	local ssh_key

	[ -r "${template_path}" ] || vm_fatal "Template not readable: ${template_path}"

	ssh_key="$(vm_read_ssh_key)" || exit 1

	sed \
		-e "s|__VM_INSTANCE_ID__|${VM_INSTANCE_ID}|g" \
		-e "s|__VM_HOSTNAME__|${VM_HOSTNAME}|g" \
		-e "s|__VM_FQDN__|${VM_FQDN}|g" \
		-e "s|__VM_TIMEZONE__|${VM_TIMEZONE}|g" \
		-e "s|__VM_USERNAME__|${VM_USERNAME}|g" \
		-e "s|__VM_KEYBOARD_LAYOUT__|${VM_KEYBOARD_LAYOUT}|g" \
		-e "s|__VM_KEYBOARD_MODEL__|${VM_KEYBOARD_MODEL}|g" \
		-e "s|__VM_KEYBOARD_VARIANT__|${VM_KEYBOARD_VARIANT}|g" \
		-e "s|__VM_KEYBOARD_OPTIONS__|${VM_KEYBOARD_OPTIONS}|g" \
		-e "s|__VM_K8S_CHANNEL__|${VM_K8S_CHANNEL}|g" \
		-e "s|__VM_CHRONY_MAKESTEP__|${VM_CHRONY_MAKESTEP}|g" \
		-e "s|__VM_SSH_PUBLIC_KEY__|${ssh_key}|g" \
		"${template_path}" || vm_fatal "Failed to render template: ${template_path}"
}

function vm_create_seed_iso() {
	vm_require_cmd hdiutil
	vm_ensure_dirs

	[ -d "${VM_CLOUD_INIT_DIR}" ] || vm_fatal "cloud-init directory not found: ${VM_CLOUD_INIT_DIR}"
	[ -r "${VM_CLOUD_INIT_DIR}/user-data" ] || vm_fatal "user-data not found: ${VM_CLOUD_INIT_DIR}/user-data"
	[ -r "${VM_CLOUD_INIT_DIR}/meta-data" ] || vm_fatal "meta-data not found: ${VM_CLOUD_INIT_DIR}/meta-data"

	vm_render_template "${VM_CLOUD_INIT_DIR}/user-data" >"${VM_SEED_DIR}/user-data" || vm_fatal "Failed to render user-data"
	vm_render_template "${VM_CLOUD_INIT_DIR}/meta-data" >"${VM_SEED_DIR}/meta-data" || vm_fatal "Failed to render meta-data"

	rm -f "${VM_SEED_ISO}"

	hdiutil makehybrid \
		-quiet \
		-iso \
		-joliet \
		-default-volume-name cidata \
		-o "${VM_SEED_ISO}" \
		"${VM_SEED_DIR}" \
		|| vm_fatal "Failed to create cloud-init seed ISO"

	echo "Created seed ISO: ${VM_SEED_ISO}"
}

function vm_parallels_bin() {
	printf "%s\n" "/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
}

function vm_create() {
	local prlctl

	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	[ -f "${VM_IMAGE_FILE}" ] || vm_fatal "Cloud image not found: ${VM_IMAGE_FILE}"
	[ -f "${VM_SEED_ISO}" ] || vm_fatal "Seed ISO not found: ${VM_SEED_ISO}"

	cat <<__EOF__
Prepared VM assets for ${VM_NAME}.

The Parallels registration step is intentionally isolated here because it needs a
real Parallels session to validate on-host. Use these values when finalising the
create flow:

  VM name:     ${VM_NAME}
  CPUs:        ${VM_CPUS}
  RAM (MB):    ${VM_MEMORY_MB}
  Disk (GB):   ${VM_DISK_GB}
  Image file:  ${VM_IMAGE_FILE}
  Seed ISO:    ${VM_SEED_ISO}
  Host arch:   ${VM_ARCH}
  prlctl bin:  ${prlctl}
__EOF__

	vm_fatal "VM creation is not wired yet. Confirm the preferred prlctl create/set/register sequence on-host and I can finish this function cleanly."
}

function vm_boot() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	"${prlctl}" start "${VM_NAME}" || vm_fatal "Failed to start VM: ${VM_NAME}"
}

function vm_down() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	"${prlctl}" stop "${VM_NAME}" || vm_fatal "Failed to stop VM: ${VM_NAME}"
}

function vm_destroy() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	"${prlctl}" delete "${VM_NAME}" || vm_fatal "Failed to delete VM: ${VM_NAME}"
}

function vm_status() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	"${prlctl}" list --all
}

function vm_print_ssh_config() {
	cat <<__EOF__
Host ${VM_NAME}
    HostName <set-vm-ip-or-dns-name>
    User ${VM_USERNAME}
    IdentityFile ${HOME}/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
__EOF__
}
