#!/usr/bin/env bash

function fatal() {
	echo "FATAL ERROR: $@"
	exit 1
}

BUILDROOT="${BASEPATH}/buildroot"
CURL=$(which curl 2>/dev/null) || fatal "I need curl!"
MOCK=$(which mock 2>/dev/null) || fatal "I need mock!"
RPMSIGN=$(which rpmsign 2>/dev/null) || fatal "I need rpmsign/rpm-sign!"
DEVS="Alasdair McWilliam <alasdair.mcwilliam@outlook.com>"
MOCK_MANIFEST="mock.manifest"

# Delete any temp files we generate on exit
TMPNAME="mkbld.tmp.XXXXXX"
trap "rm -rf mkbld.tmp.*" EXIT

# Set a default helptext
HELPTEXT="--source <path> --arch <x86_64|aarch64> [--bin] [--sign] [--root <chroot>]"

# Global variables
BUILD_CLEANUP=no
BUILD_SHA=
BUILD_SOURCE=
BUILD_ARCH=
BUILD_BINARIES=no
BUILD_SIGNED=no
BUILD_TS=$(date -u +%y%m%d.%H%M%S)
BUILD_MANIFEST=build_kernel.manifest
BUILD_MOCKROOT=

[ -z "${BASEPKG}" ] && fatal "BASEPKG is undefined"
[ -z "${BASESPEC}" ] && fatal "BASESPEC is undefined"

# Parse args
while (( "$#" )); do
	ARG1=$(echo "${1}" | awk '{$1=$1;print}')
	ARG2=$(echo "${2}" | awk '{$1=$1;print}')
	case "${ARG1}" in
		--clean|--cleanup)
			BUILD_CLEANUP=yes
			shift
			;;
		
		--root)
			[ -z "${ARG2}" ] && fatal "--root needs <root>"
			BUILD_MOCKROOT="${ARG2}"
			shift 2
			;;

		--sha)
			[ -z "${ARG2}" ] && fatal "--sha needs <sha>"
			BUILD_SHA=".${ARG2}"
			shift 2
			;;
			
		--source)
			[ -z "${ARG2}" ] && fatal "--source needs <source path>"
			BUILD_SOURCE="${ARG2}"
			shift 2
			;;

		--arch)
			[ -z "${ARG2}" ] && fatal "--arch needs <arch: x86_64, aarch64>"
			BUILD_ARCH=$(basename "${ARG2}")
			shift 2
			;;
		
		--output)
			[ -z "${ARG2}" ] && fatal "--output needs <manifest_file>"
			BUILD_MANIFEST="${ARG2}"
			shift 2
			;;

		--bin|--binaries)
			BUILD_BINARIES=yes
			shift
			;;
		
		--sign|--signed)
			BUILD_SIGNED=yes
			shift
			;;
		
		-h|--help)
			echo "${BASENAME}: ${HELPTEXT}"
			exit 0
			;;

		*)
			fatal "Unknown argument: ${ARG1}"
			;;
	esac
done

if [ -z "${BUILD_SOURCE}" ] || [ -z "${BUILD_ARCH}" ] || [ -z "${BUILD_MANIFEST}" ]; then
	fatal "Insufficient arguments: ${HELPTEXT}"
fi

#
# Verify our architecture. We don't support cross compiling, so the architecture we're
# being asked to build should match what we're running on.
#

ACTUAL_ARCH=$(uname -m)

case "${ACTUAL_ARCH}" in
	x86_64 | amd64)
		ACTUAL_ARCH=x86_64 ;;
	aarch64 | arm64)
		ACTUAL_ARCH=aarch64 ;;
	*)
		fatal "I cannot build anything on ${ACTUAL_ARCH}!" ;;
esac

[ "${BUILD_ARCH}" == "${ACTUAL_ARCH}" ] || \
    fatal "Architecture mismatch: you want arch:${BUILD_ARCH} but I'm running on arch:${ACTUAL_ARCH}"

#
# Validate we know how to build for the platform.
#

ACTUAL_SOURCE="${BASEPATH}/${BUILD_SOURCE}"
[ -d "${ACTUAL_SOURCE}" ] || fatal "I don't know how to build source:${BUILD_SOURCE}"

#
# Check we have a mock manifest file
#

ACTUAL_MANIFEST=$(dirname $(readlink -f "${ACTUAL_SOURCE}"))"/${MOCK_MANIFEST}"
[ -r "${ACTUAL_MANIFEST}" ] || \
    fatal "I can't read the mock manifest:${ACTUAL_MANIFEST} for source:${BUILD_SOURCE}"


#
# Now check we understand how to build for this architecture.
#

ACTUAL_SOURCES="${ACTUAL_SOURCE}/SOURCES"
ACTUAL_SPECS="${ACTUAL_SOURCE}/SPECS"
ACTUAL_SPEC="${ACTUAL_SPECS}/${BASESPEC}"
[ -r "${ACTUAL_SPEC}" ] || fatal "I don't know how to build source:${BUILD_SOURCE}" \
	" on arch:${BUILD_ARCH} -- spec not found: ${ACTUAL_SPEC}"

#
# See if there's a patch number we need to insert into the build ID
# This will be specified by a file called patchlevel.txt in SOURCES if so.
#

ACTUAL_PATCHLEVEL="${ACTUAL_SOURCES}/patchlevel.txt"
BUILD_PATCHLEVEL=""
if [ -r "${ACTUAL_PATCHLEVEL}" ]; then
	BUILD_PATCHLEVEL=$(head -n 1 "${ACTUAL_PATCHLEVEL}" | sed -e 's/[ \t]/_/g' | tr -cd '[:alnum:].-_')

	# if we have a patch level, prepend with a dot to split it out in version
	[ ! -z "${BUILD_PATCHLEVEL}" ] && BUILD_PATCHLEVEL=".${BUILD_PATCHLEVEL}"
fi

#
# Identify our mock root paths. If we have been given an explicit root, use
# that. Otherwise, calculate it from the manifest file for the platform.
#

if [ ! -z "${BUILD_MOCKROOT}" ]; then
	BUILD_CHROOT="${BUILD_MOCKROOT}"
else
	BUILD_CHROOT=$(cat "${ACTUAL_MANIFEST}")
	[ ! -z "${BUILD_CHROOT}" ] || fatal "No data in ACTUAL_MANIFEST: ${ACTUAL_MANIFEST}"
	BUILD_CHROOT="${BUILD_CHROOT}-${ACTUAL_ARCH}"
fi

#
# Once we have the mock root, if we are in clean-up mode, then...clean up!
#

if [ "${BUILD_CLEANUP}" == "yes" ]; then
	echo "Cleaning up chroot ${BUILD_CHROOT} ..."
	${MOCK} --root "${BUILD_CHROOT}" --clean
	exit 0
fi

