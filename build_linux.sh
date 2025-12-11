#!/usr/bin/env bash

# Base paths
BASENAME=$(basename "${0}")
BASEPATH=$(dirname "${0}")
CURPATH=$(pwd)

function fatal() {
	echo "FATAL ERROR: $@"
	exit 1
}

# Apps
NPROC=$(which nproc 2>/dev/null) || fatal "I need nproc!"
GIT=$(which git 2>/dev/null) || fatal "I need git!"
MAKE=$(which make 2>/dev/null) || fatal "I need make!"
GRUBBY=$(which grubby 2>/dev/null) || fatal "I need grubby!"

# Process args
MK_HASH=0
MK_PREPARE=0
MK_IMAGE=0
MK_MODULES=0
MK_INSTALL=0
MK_GRUBBY=0
MK_CLEAN=0
MK_PATH="${CURPATH}"
MK_CONFIG=""
MK_NEWDEF=0
MK_DEBUG=0

HELPTEXT=$(cat <<__EOF__
  --hash                Include git hash in build version
  --prepare             Prepare kernel source
  --image               Build kernel image
  --modules             Build kernel modules
  --install             Install kernel object files
  --grubby              Update grubby
  --full                Includes {prepare,image,modules,install,grubby}
  --clean               Clean source tree after build
  --src <path>          Specifies linux src path
  --config <file>       Use file as config for build
  --newdef		Use defaults for new config symbols
  --debug		Enforce debug kernel build
__EOF__
)

while (( "$#" )); do
	ARG1=$(echo "${1}" | awk '{$1=$1;print}')
	ARG2=$(echo "${2}" | awk '{$1=$1;print}')
	case "${ARG1}" in
		--hash)
			MK_HASH=1
			shift ;;

		--prepare)
			MK_PREPARE=1
			shift ;;

		--image)
			MK_IMAGE=1
			shift ;;
		
		--modules)
			MK_MODULES=1
			shift ;;
		
		--install)
			MK_INSTALL=1
			MK_GRUBBY=1
			shift ;;
		
		--grubby)
			MK_GRUBBY=1
			shift ;;

		--full)
			MK_PREPARE=1
			MK_IMAGE=1
			MK_MODULES=1
			MK_INSTALL=1
			MK_GRUBBY=1
			shift ;;
		
		--clean)
			MK_CLEAN=1
			shift ;;
		
		--src)
			[ -z "${ARG2}" ] && fatal "--path requires <path>"
			MK_PATH="${ARG2}"
			shift 2 ;;
		
		--config)
			[ -z "${ARG2}" ] && fatal "--config needs <config>"
			MK_CONFIG=$(readlink -f "${ARG2}")
			[ ! -f "${MK_CONFIG}" ] && fatal "config '${MK_CONFIG}' not file"
			shift 2 ;;
		
		--newdef)
			MK_NEWDEF=1
			shift ;;
		
		--debug)
			MK_DEBUG=1
			shift ;;
		
		--help|-h)
			echo "${HELPTEXT}"
			exit 0 ;;

		*)
			echo "Unknown arg: ${ARG1}"
			echo "${HELPTEXT}"
			fatal "Unknown arg: ${ARG1}"
			;;
	esac
done

function cleanup() {
	popd || exit 1
}

# Setup cleanup handler
trap cleanup EXIT

# Switch to kernel source path (may be pwd)
pushd "${MK_PATH}" || fatal "pushd(${MK_PATH}) failed"

# Defaults
MK_FILE="Makefile"
MK_NPROCS=$(${NPROC} --all)

# Get some version information
GIT_HASH=$(${GIT} show -s --format=%h)
GIT_BRANCH=$(${GIT} branch | sed -n '/\* /s///p')
GIT_DETACHED=$(echo "${GIT_BRANCH}" | grep "detached at" | cut -d "(" -f2 | cut -d ")" -f1 | sed -e 's/[ \/]/_/g')
if [ ! -z "${GIT_DETACHED}" ]; then
	GIT_BRANCH="${GIT_DETACHED}"
else
	GIT_BRANCH=${GIT_BRANCH//\//__}
fi

# Check the source tree is initialised, so we can run "make kernelrelease" to get build info.

if ! ${MAKE} -s kernelrelease 1>/dev/null 2>&1; then
	echo "*** Fresh tree, initialising with defconfig..."
	${MAKE} defconfig || fatal "make defconfig failed, please init the tree"
	${MAKE} prepare || fatal "make prepare failed, please init the tree"
fi

echo "--------------------------------------------------------------------------------"

# Generate new version information.

EXTRA_VERSION=$(grep -E "^EXTRAVERSION" "${MK_FILE}" | cut -f2 -d'=' | tr -d '[:space:]')
if [ "${MK_HASH}" -gt 0 ]; then
	EXTRA_VERSION="${EXTRA_VERSION}.${GIT_HASH}.${GIT_BRANCH}"
else
	EXTRA_VERSION="${EXTRA_VERSION}.${GIT_BRANCH}"
fi
if [ "${MK_DEBUG}" -gt 0 ]; then
	EXTRA_VERSION="${EXTRA_VERSION}.dbg"
fi
echo EXTRA_VERSION=${EXTRA_VERSION}

# Ask the tree for the full release string. The kernel build will fail if a version string
# is >64 characters in length, so truncate if we need to.

MK_VERSION=$(${MAKE} -s EXTRAVERSION=${EXTRA_VERSION} kernelrelease)
[ -z "${MK_VERSION}" ] && fatal "make kernelrelease failed"
while [ "${#MK_VERSION}" -gt 63 ]; do
	EXTRA_VERSION="${EXTRA_VERSION:0:64}"
	MK_VERSION=$(${MAKE} -s EXTRAVERSION=${EXTRA_VERSION} kernelrelease)
done

# Do the build
MK_COMMAND="${MAKE} EXTRAVERSION=${EXTRA_VERSION} -j${MK_NPROCS}"

echo "MK_HASH=${MK_HASH} MK_IMAGE=${MK_IMAGE} MK_MODULES=${MK_MODULES} MK_INSTALL=${MK_INSTALL} MK_CLEAN=${MK_CLEAN}"
echo "MK_VERSION=${MK_VERSION} MK_NEWDEF=${MK_NEWDEF} MK_NPROCS=${MK_NPROCS} MK_DEBUG=${MK_DEBUG}"
echo "MK_COMMAND=${MK_COMMAND}"

echo "--------------------------------------------------------------------------------"
sleep 1

# Check we have a config

if [ ! -z "${MK_CONFIG}" ]; then
	echo "*** Copying ${MK_CONFIG} into .config"
	[ -f ".config" ] && mv .config .config.bk
	cp -f "${MK_CONFIG}" .config
	MK_PREPARE=1
fi

if [ "${MK_DEBUG}" -gt 0 ]; then
	declare -A DBG_VALUES=(
		["CONFIG_DEBUG_INFO"]=y
		["CONFIG_DEBUG_INFO_SPLIT"]=n
		["CONFIG_DEBUG_INFO_REDUCED"]=n
		["CONFIG_DEBUG_INFO_DWARF4"]=y
		["CONFIG_DEBUG_INFO_DWARF5"]=y
		["CONFIG_DEBUG_INFO_LEVEL"]=3
		["CONFIG_DEBUG_INFO_BTF"]=y
		["CONFIG_GDB_SCRIPTS"]=y
		["CONFIG_FRAME_POINTER"]=y
		["CONFIG_STRIP_ASM_SYMS"]=n
	)

	CFG_SCRIPT="${MK_PATH}/scripts/config"

	for flag in "${!DBG_VALUES[@]}"; do
		echo "SET-VAL: ${flag}=${DBG_VALUES[$flag]}"
		${CFG_SCRIPT} --set-val ${flag} ${DBG_VALUES[$flag]}
	done
fi

if [ "${MK_PREPARE}" -gt 0 ]; then
	if [ "${MK_NEWDEF}" -gt 0 ]; then
		${MK_COMMAND} olddefconfig || fatal "make olddefconfig failed"
	else
		${MK_COMMAND} oldconfig || fatal "make oldconfig failed"
	fi
	${MK_COMMAND} prepare || fatal "make prepare failed"
fi
if [ "${MK_IMAGE}" -gt 0 ]; then
	${MK_COMMAND} || fatal "make image failed"
fi
if [ "${MK_MODULES}" -gt 0 ]; then
	${MK_COMMAND} modules || fatal "make modules failed"
fi
if [ "${MK_INSTALL}" -gt 0 ]; then
	sudo -E ${MK_COMMAND} modules_install || fatal "make modules_install failed"
	sudo -E ${MK_COMMAND} install || fatal "make install failed"
	sudo -E cp -f ".config" "/boot/config-${MK_VERSION}"
fi
if [ "${MK_GRUBBY}" -gt 0 ]; then
	sudo -E ${GRUBBY} --set-default "/boot/vmlinuz-${MK_VERSION}" || fatal "grubby set-default failed"
fi
if [ "${MK_CLEAN}" -gt 0 ]; then
	${MK_COMMAND} clean || fatal "make clean failed"
fi
