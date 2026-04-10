#!/usr/bin/env bash

BASENAME=$(basename "${0}")
BASEPATH=$(cd "$(dirname "${0}")" && pwd)

. "${BASEPATH}/lib/vm.sh"

vm_parse_args "$@"

HELPTEXT=$(cat <<__EOF__
${BASENAME} [--target <path>] --instance <vm-name> [--upgrade|--no-upgrade] [--action <a,b,c>] [--dry-run] [--verbose] [--debug] <command>

Commands:
  image         Download and prepare the Fedora boot image
  seed          Generate cloud-init seed media
  create        Create the Parallels VM
  create-boot   Create and then start the VM
  prl-config    Apply Parallels VM settings to an existing VM
  tools-update  Trigger a manual Parallels Tools install/update
  boot          Start the VM
  reboot        Reboot the guest over SSH and wait for it to return
  down          Stop the VM
  kill          Force-stop the VM
  stop-destroy  Stop and then delete the VM registration
  kill-destroy  Force-stop and then delete the VM registration
  destroy       Delete the VM registration
  full-recycle  Force-stop, delete, create, and start the VM
  wait-ready    Wait for SSH/cloud-init, and for upgrade reboot if enabled
  status        Show VM status
  ssh-config    Install or update the repo-local SSH include file for the VM
  ssh-config-print
                Print ssh config snippet for the VM
  up            Run image, seed, create, and boot
  help          Show this help text

Environment overrides:
  VM_FEDORA_RELEASE     Default: 43
  VM_TARGET             Default: fc43/vm-default
                        Short target names like fc43 resolve to fc43/vm-default
  VM_TARGET_DIR         Default: ./fc43/vm-default
  VM_CONFIG_FILE        Default: ./fc43/vm-default/vm.conf
  PRL_CONFIG_FILE       Default: ./config/parallels.conf
  VM_DRY_RUN            Default: 0
  VM_VERBOSE            Default: 0
  VM_DEBUG              Default: 0
  VM_WAIT_FOR_UPGRADE   Default: 0
  VM_ACTIONS            Comma-separated action list for sequential execution
  VM_NAME               Required, or pass --instance <vm-name>
  VM_LOCAL_DOMAIN       Default: ajm.dev
  VM_HOSTNAME           Derived from VM_NAME
  VM_FQDN               Derived from VM_NAME.VM_LOCAL_DOMAIN
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
  VM_PACKAGE_UPGRADE    Default: from VM_CONFIG_FILE
  VM_PACKAGE_REBOOT_IF_REQUIRED
                        Default: from VM_CONFIG_FILE
  VM_CLOUD_INIT_DIR     Default: ./fc43/vm-default/cloud-init
  VM_SSH_PUBLIC_KEY     Override the SSH key to inject
__EOF__
)

case "${VM_COMMAND}" in
	help|-h|--help)
		echo "${HELPTEXT}"
		exit 0
		;;
esac

vm_init_defaults

[ "${VM_DEBUG}" = "1" ] && set -x

case "${VM_COMMAND}" in
	action-list)
		vm_run_action_list "${VM_ACTIONS}"
		;;

	image)
		vm_dispatch_action image
		;;

	seed)
		vm_dispatch_action seed
		;;

	create)
		vm_dispatch_action create
		;;

	create-boot)
		vm_dispatch_action create-boot
		;;

	prl-config)
		vm_dispatch_action prl-config
		;;

	tools-update|tools-install|install-tools)
		vm_dispatch_action "${VM_COMMAND}"
		;;

	boot|start)
		vm_dispatch_action "${VM_COMMAND}"
		;;

	reboot|restart)
		vm_dispatch_action "${VM_COMMAND}"
		;;

	wait|wait-ready)
		vm_dispatch_action wait-ready
		;;

	down|stop)
		vm_dispatch_action "${VM_COMMAND}"
		;;

	kill|force-stop)
		vm_dispatch_action "${VM_COMMAND}"
		;;

	stop-destroy)
		vm_dispatch_action stop-destroy
		;;

	kill-destroy)
		vm_dispatch_action kill-destroy
		;;

	destroy|delete)
		vm_dispatch_action "${VM_COMMAND}"
		;;

	full-recycle)
		vm_dispatch_action full-recycle
		;;

	status)
		vm_dispatch_action status
		;;

	ssh-config)
		vm_dispatch_action ssh-config
		;;

	ssh-config-print)
		vm_dispatch_action ssh-config-print
		;;

	up)
		vm_dispatch_action up
		;;

	*)
		echo "${HELPTEXT}"
		vm_fatal "Unknown command: ${VM_COMMAND}"
		;;
esac
