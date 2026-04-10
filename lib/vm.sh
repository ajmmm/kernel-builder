#!/usr/bin/env bash

function vm_fatal() {
	echo "FATAL ERROR: $@"
	exit 1
}

function vm_info() {
	echo "$@"
}

function vm_debug() {
	[ "${VM_DEBUG}" = "1" ] && echo "DEBUG: $@"
}

function vm_require_cmd() {
	local cmd="${1}"

	command -v "${cmd}" 1>/dev/null 2>&1 || vm_fatal "I need ${cmd}!"
}

function vm_quote_cmd() {
	printf "%q " "$@"
}

function vm_run() {
	vm_quote_cmd "$@"
	printf "\n"

	[ "${VM_DRY_RUN}" = "1" ] && return 0
	"$@"
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

function vm_target_slug() {
	printf "%s\n" "${VM_TARGET}" | tr '/:' '__'
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
	VM_KEYBOARD_VC_KEYMAP="${VM_KEYBOARD_VC_KEYMAP:-gb}"
	VM_K8S_CHANNEL="${VM_K8S_CHANNEL:-v1.35}"
	VM_CHRONY_MAKESTEP="${VM_CHRONY_MAKESTEP:-1.0 3}"
	VM_PRL_DISTRIBUTION="${VM_PRL_DISTRIBUTION:-fedora}"
	HOST_ARCH="${HOST_ARCH:-$(vm_guess_arch)}"
	VM_ARCH="${VM_ARCH:-${HOST_ARCH}}"
	VM_TARGET_SLUG="${VM_TARGET_SLUG:-$(vm_target_slug)}"
	VM_CACHE_DIR="${VM_CACHE_DIR:-${BASEPATH}/.cache}"
	VM_IMAGE_DIR="${VM_IMAGE_DIR:-${VM_CACHE_DIR}/images}"
	VM_SEED_DIR="${VM_SEED_DIR:-${VM_CACHE_DIR}/seed/${VM_TARGET_SLUG}/${VM_NAME}}"
	VM_PARALLELS_DIR="${VM_PARALLELS_DIR:-${VM_CACHE_DIR}/parallels/${VM_TARGET_SLUG}}"
	VM_BUNDLE_PATH="${VM_BUNDLE_PATH:-${VM_PARALLELS_DIR}/${VM_NAME}.pvm}"
	VM_CLOUD_INIT_DIR="${VM_CLOUD_INIT_DIR:-${VM_TARGET_DIR}/cloud-init}"
	VM_IMAGE_URL="${VM_IMAGE_URL:-$(vm_default_image_url)}"
	VM_IMAGE_FILE="${VM_IMAGE_FILE:-${VM_IMAGE_DIR}/$(basename "${VM_IMAGE_URL}")}"
	VM_SEED_ISO="${VM_SEED_ISO:-${VM_SEED_DIR}/seed.iso}"
	VM_INSTANCE_ID="${VM_INSTANCE_ID:-${VM_NAME}-01}"
	VM_SSH_KEY_PATH="${VM_SSH_KEY_PATH:-${HOME}/.ssh/id_ed25519.pub}"
}

function vm_resolve_prl_defaults() {
	PRL_AUTOSTART="${PRL_AUTOSTART:-off}"
	PRL_AUTOSTOP="${PRL_AUTOSTOP:-shutdown}"
	PRL_PAUSE_IDLE="${PRL_PAUSE_IDLE:-off}"
	PRL_ADAPTIVE_HYPERVISOR="${PRL_ADAPTIVE_HYPERVISOR:-auto}"
	PRL_NESTED_VIRT="${PRL_NESTED_VIRT:-auto}"
	PRL_SHARED_PROFILE="${PRL_SHARED_PROFILE:-off}"
	PRL_SMART_MOUNT="${PRL_SMART_MOUNT:-off}"
	PRL_SHARE_HOST_FOLDERS="${PRL_SHARE_HOST_FOLDERS:-on}"
	PRL_SHARE_HOST_FOLDERS_DEFINED="${PRL_SHARE_HOST_FOLDERS_DEFINED:-off}"
	PRL_SHARE_HOST_FOLDER_DOWNLOADS="${PRL_SHARE_HOST_FOLDER_DOWNLOADS:-on}"
	PRL_SHARE_HOST_FOLDER_DOWNLOADS_NAME="${PRL_SHARE_HOST_FOLDER_DOWNLOADS_NAME:-Downloads}"
	PRL_SHARE_HOST_FOLDER_DOWNLOADS_PATH="${PRL_SHARE_HOST_FOLDER_DOWNLOADS_PATH:-${HOME}/Downloads}"
	PRL_SHARE_HOST_FOLDER_DEVELOP="${PRL_SHARE_HOST_FOLDER_DEVELOP:-off}"
	PRL_SHARE_HOST_FOLDER_DEVELOP_NAME="${PRL_SHARE_HOST_FOLDER_DEVELOP_NAME:-Develop}"
	PRL_SHARE_HOST_FOLDER_DEVELOP_PATH="${PRL_SHARE_HOST_FOLDER_DEVELOP_PATH:-${HOME}/Develop}"
	PRL_SHARE_GUEST_FOLDERS="${PRL_SHARE_GUEST_FOLDERS:-off}"
	PRL_SHARED_CLIPBOARD="${PRL_SHARED_CLIPBOARD:-on}"
	PRL_TIME_SYNC="${PRL_TIME_SYNC:-on}"
	PRL_SOUND="${PRL_SOUND:-off}"
	PRL_MICROPHONE="${PRL_MICROPHONE:-off}"
	PRL_AUTO_SHARE_CAMERA="${PRL_AUTO_SHARE_CAMERA:-off}"
	PRL_FULL_SCREEN_USE_ALL_DISPLAYS="${PRL_FULL_SCREEN_USE_ALL_DISPLAYS:-off}"
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
	VM_DEBUG="${VM_DEBUG:-${VM_DEBUG_DEFAULT:-0}}"
	VM_FEDORA_RELEASE="${VM_FEDORA_RELEASE:-43}"
	VM_TARGET="${VM_TARGET:-$(vm_target_name)}"

	vm_load_target_config
	vm_load_parallels_config
	vm_resolve_vm_defaults
	vm_resolve_prl_defaults
}

function vm_parse_args() {
	VM_COMMAND="help"

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

	if [ "$#" -gt 0 ]; then
		VM_COMMAND="${1}"
	else
		VM_COMMAND="help"
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

	vm_run curl --fail --location --silent --show-error "${VM_IMAGE_URL}" -o "${VM_IMAGE_FILE}" \
		|| vm_fatal "Download failed: ${VM_IMAGE_URL}"

	echo "Saved: ${VM_IMAGE_FILE}"
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
		esac

		line="${line//__VM_INSTANCE_ID__/${VM_INSTANCE_ID}}"
		line="${line//__VM_HOSTNAME__/${VM_HOSTNAME}}"
		line="${line//__VM_FQDN__/${VM_FQDN}}"
		line="${line//__VM_TIMEZONE__/${VM_TIMEZONE}}"
		line="${line//__VM_USERNAME__/${VM_USERNAME}}"
		line="${line//__VM_KEYBOARD_VC_KEYMAP__/${VM_KEYBOARD_VC_KEYMAP}}"
		line="${line//__VM_K8S_CHANNEL__/${VM_K8S_CHANNEL}}"
		line="${line//__VM_CHRONY_MAKESTEP__/${VM_CHRONY_MAKESTEP}}"
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
	vm_require_cmd hdiutil
	vm_ensure_dirs

	[ -d "${VM_CLOUD_INIT_DIR}" ] || vm_fatal "cloud-init directory not found: ${VM_CLOUD_INIT_DIR}"
	[ -r "${VM_CLOUD_INIT_DIR}/user-data" ] || vm_fatal "user-data not found: ${VM_CLOUD_INIT_DIR}/user-data"
	[ -r "${VM_CLOUD_INIT_DIR}/meta-data" ] || vm_fatal "meta-data not found: ${VM_CLOUD_INIT_DIR}/meta-data"

	vm_render_template "${VM_CLOUD_INIT_DIR}/user-data" >"${VM_SEED_DIR}/user-data" || vm_fatal "Failed to render user-data"
	vm_render_template "${VM_CLOUD_INIT_DIR}/meta-data" >"${VM_SEED_DIR}/meta-data" || vm_fatal "Failed to render meta-data"

	[ "${VM_DRY_RUN}" = "1" ] || rm -f "${VM_SEED_ISO}"

	vm_run hdiutil makehybrid \
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

function vm_prl_list_names() {
	local prlctl

	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	"${prlctl}" list --all -o name 2>/dev/null
}

function vm_exists() {
	vm_prl_list_names | awk 'NR > 1 {print}' | grep -Fx "${VM_NAME}" 1>/dev/null 2>&1
}

function vm_prl_set() {
	local prlctl="${1}"
	shift
	vm_run "${prlctl}" set "${VM_NAME}" "$@" || vm_fatal "prlctl set failed: ${VM_NAME} $*"
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

	if ! "${prlctl}" set "${VM_NAME}" --shf-host-set "${name}" --path "${path}" --mode "${mode}" --enable 1>/dev/null 2>&1; then
		vm_run "${prlctl}" set "${VM_NAME}" --shf-host-add "${name}" --path "${path}" --mode "${mode}" --enable \
			|| vm_fatal "Failed to add shared folder ${name}: ${path}"
	fi
}

function vm_apply_prl_config() {
	local prlctl
	local nested_status
	local sound_status

	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"

	vm_prl_set "${prlctl}" \
		--autostart "${PRL_AUTOSTART}" \
		--autostop "${PRL_AUTOSTOP}" \
		--pause-idle "${PRL_PAUSE_IDLE}" \
		--adaptive-hypervisor "${PRL_ADAPTIVE_HYPERVISOR}" \
		--shared-profile "${PRL_SHARED_PROFILE}" \
		--smart-mount "${PRL_SMART_MOUNT}" \
		--shf-host "${PRL_SHARE_HOST_FOLDERS}" \
		--shf-host-defined "${PRL_SHARE_HOST_FOLDERS_DEFINED}" \
		--shf-guest "${PRL_SHARE_GUEST_FOLDERS}" \
		--shared-clipboard "${PRL_SHARED_CLIPBOARD}" \
		--time-sync "${PRL_TIME_SYNC}" \
		--auto-share-camera "${PRL_AUTO_SHARE_CAMERA}"

	if [ "${HOST_ARCH}" = "x86_64" ]; then
		vm_prl_set "${prlctl}" --nested-virt "${PRL_NESTED_VIRT}"
		nested_status="Applied nested virtualization: ${PRL_NESTED_VIRT}"
	else
		nested_status="Skipped nested virtualization on ${HOST_ARCH}; Parallels documents nested virtualization as Intel-only."
	fi

	if [ "${PRL_SOUND}" = "off" ] && [ "${PRL_MICROPHONE}" = "off" ]; then
		if [ "${VM_DRY_RUN}" = "1" ]; then
			vm_run "${prlctl}" set "${VM_NAME}" --device-del sound
			sound_status="Would remove VM sound device to disable sound output and microphone."
		elif "${prlctl}" set "${VM_NAME}" --device-del sound 1>/dev/null 2>&1; then
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
  Full screen use all displays: ${PRL_FULL_SCREEN_USE_ALL_DISPLAYS}
  Picture in Picture:          ${PRL_PICTURE_IN_PICTURE}
  Travel mode enter:           ${PRL_TRAVEL_MODE_ENTER}
  Travel mode quit:            ${PRL_TRAVEL_MODE_QUIT}
  Auto-update Parallels Tools: ${PRL_AUTO_UPDATE_TOOLS}
__EOF__
}

function vm_create_vm_shell() {
	local prlctl="${1}"

	vm_run mkdir -p "${VM_PARALLELS_DIR}" || vm_fatal "Failed to create Parallels directory"

	if [ "${VM_DRY_RUN}" != "1" ] && vm_exists; then
		vm_info "VM already exists in Parallels: ${VM_NAME}"
		return 0
	fi

	vm_run "${prlctl}" create "${VM_NAME}" --distribution "${VM_PRL_DISTRIBUTION}" --dst "${VM_PARALLELS_DIR}" \
		|| vm_fatal "Failed to create VM shell: ${VM_NAME}"
}

function vm_attach_boot_media() {
	local prlctl="${1}"

	vm_prl_set "${prlctl}" --cpus "${VM_CPUS}" --memsize "${VM_MEMORY_MB}" --efi-boot on
	vm_prl_set "${prlctl}" --device-set net0 --type shared --adapter-type virtio
	vm_prl_set "${prlctl}" --device-set hdd0 --image "${VM_IMAGE_FILE}"
	vm_prl_set "${prlctl}" --device-set cdrom0 --image "${VM_SEED_ISO}" --connect
}

function vm_create() {
	local prlctl

	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	if [ "${VM_DRY_RUN}" != "1" ]; then
		[ -f "${VM_IMAGE_FILE}" ] || vm_fatal "Cloud image not found: ${VM_IMAGE_FILE}"
		[ -f "${VM_SEED_ISO}" ] || vm_fatal "Seed ISO not found: ${VM_SEED_ISO}"
	fi
	vm_create_vm_shell "${prlctl}"
	vm_attach_boot_media "${prlctl}"
	vm_apply_prl_config

	cat <<__EOF__
VM prepared: ${VM_NAME}

  Target:      ${VM_TARGET}
  Host arch:   ${HOST_ARCH}
  Guest arch:  ${VM_ARCH}
  CPUs:        ${VM_CPUS}
  RAM (MB):    ${VM_MEMORY_MB}
  Image file:  ${VM_IMAGE_FILE}
  Seed ISO:    ${VM_SEED_ISO}
  VM bundle:   ${VM_BUNDLE_PATH}
__EOF__
}

function vm_boot() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	vm_run "${prlctl}" start "${VM_NAME}" || vm_fatal "Failed to start VM: ${VM_NAME}"
}

function vm_down() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	vm_run "${prlctl}" stop "${VM_NAME}" || vm_fatal "Failed to stop VM: ${VM_NAME}"
}

function vm_destroy() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	vm_run "${prlctl}" delete "${VM_NAME}" || vm_fatal "Failed to delete VM: ${VM_NAME}"
}

function vm_status() {
	local prlctl
	prlctl="$(vm_parallels_bin)"
	[ -x "${prlctl}" ] || vm_fatal "Parallels CLI not found: ${prlctl}"
	vm_run "${prlctl}" list --all
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
