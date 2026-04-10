#!/usr/bin/env bash

BASENAME=$(basename "${0}")
BASEPATH=$(cd "$(dirname "${0}")" && pwd)

. "${BASEPATH}/lib/vm.sh"

vm_parse_args "$@"

vm_init_defaults

[ "${VM_DEBUG}" = "1" ] && set -x

HELPTEXT=$(cat <<__EOF__
${BASENAME} [--target <path>] [--dry-run] [--debug] <command>

Commands:
  image         Download and prepare the Fedora boot image
  seed          Generate cloud-init seed media
  create        Create the Parallels VM
  prl-config    Apply Parallels VM settings to an existing VM
  tools-update  Trigger a manual Parallels Tools install/update
  boot          Start the VM
  down          Stop the VM
  kill          Force-stop the VM
  destroy       Delete the VM registration
  status        Show VM status
  ssh-config    Print ssh config snippet for the VM
  up            Run image, seed, create, and boot
  help          Show this help text

Environment overrides:
  VM_FEDORA_RELEASE     Default: 43
  VM_TARGET             Default: fc43/fedora
  VM_TARGET_DIR         Default: ./fc43/fedora
  VM_CONFIG_FILE        Default: ./fc43/fedora/vm.conf
  PRL_CONFIG_FILE       Default: ./config/parallels.conf
  VM_DRY_RUN            Default: 0
  VM_DEBUG              Default: 0
  VM_NAME               Default: from VM_CONFIG_FILE
  VM_HOSTNAME           Default: from VM_CONFIG_FILE
  VM_FQDN               Default: from VM_CONFIG_FILE
  VM_USERNAME           Default: from VM_CONFIG_FILE
  VM_CPUS               Default: from VM_CONFIG_FILE
  VM_MEMORY_MB          Default: from VM_CONFIG_FILE
  VM_DISK_GB            Default: from VM_CONFIG_FILE
  VM_IMAGE_URL          Override the download URL entirely
  VM_TIMEZONE           Default: from VM_CONFIG_FILE
  VM_KEYBOARD_LAYOUT    Default: from VM_CONFIG_FILE
  VM_KEYBOARD_MODEL     Default: from VM_CONFIG_FILE
  VM_KEYBOARD_VARIANT   Default: from VM_CONFIG_FILE
  VM_KEYBOARD_OPTIONS   Default: from VM_CONFIG_FILE
  VM_K8S_CHANNEL        Default: from VM_CONFIG_FILE
  VM_CHRONY_MAKESTEP    Default: from VM_CONFIG_FILE
  VM_CLOUD_INIT_DIR     Default: ./fc43/fedora/cloud-init
  VM_SSH_PUBLIC_KEY     Override the SSH key to inject
__EOF__
)

case "${VM_COMMAND}" in
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

	prl-config)
		vm_apply_prl_config
		;;

	tools-update|tools-install|install-tools)
		vm_tools_update
		;;

	boot|start)
		vm_boot
		;;

	down|stop)
		vm_down
		;;

	kill|force-stop)
		vm_kill
		;;

	destroy|delete)
		vm_destroy
		;;

	status)
		vm_status
		;;

	ssh-config)
		vm_print_ssh_config
		;;

	up)
		vm_download_image
		vm_prepare_boot_disk
		vm_create_seed_iso
		vm_create
		vm_boot
		;;

	help|-h|--help)
		echo "${HELPTEXT}"
		;;

	*)
		echo "${HELPTEXT}"
		vm_fatal "Unknown command: ${VM_COMMAND}"
		;;
esac
