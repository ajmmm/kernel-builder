#!/usr/bin/env bash

function fatal() {
	echo "FATAL ERROR: $@"
	exit 1
}

BASENAME=$(basename "${0}")
BASEPATH=$(dirname "${0}")
BUILDROOT="${BASEPATH}/buildroot"
RESULTPATH="${BUILDROOT}/result"
CURL=$(which curl 2>/dev/null) || fatal "I need curl!"
MOCK=$(which mock 2>/dev/null) || fatal "I need mock!"
RPMSIGN=$(which rpmsign 2>/dev/null) || fatal "I need rpmsign/rpm-sign!"
DEVS="Alasdair McWilliam <alasdair.mcwilliam@outlook.com>"
MOCK_MANIFEST="mock.manifest"

# Delete any temp files we generate on exit
TMPNAME="mkkrnl.tmp.XXXXXX"
trap "rm -rf mkkrnl.tmp.*" EXIT

HELPTEXT="--source <path> --arch <x86_64|aarch64> [--bin] [--sign] [--root <chroot>]"

BUILD_CLEANUP=no
BUILD_PACKAGE="kernel-ajm"
BUILD_SHA=
BUILD_SOURCE=
BUILD_ARCH=
BUILD_BINARIES=no
BUILD_SIGNED=no
BUILD_TS=$(date -u +%y%m%d.%H%M%S)
BUILD_MANIFEST=build_kernel.manifest
BUILD_MOCKROOT=

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

		--package)
			[ -z "${ARG2}" ] && fatal "--package needs <string-name>"
			BUILD_PACKAGE="${ARG2}"
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
# Say hello
#

cat <<__EOF__

   __ _                                              _ 
  / /(_)_ __  _   ___  __   /\ /\___ _ __ _ __   ___| |
 / / | | '_ \| | | \ \/ /  / //_/ _ \ '__| '_ \ / _ \ |
/ /__| | | | | |_| |>  <  / __ \  __/ |  | | | |  __/ |
\____/_|_| |_|\__,_/_/\_\ \/  \/\___|_|  |_| |_|\___|_|

======================================== ajm edition ==

__EOF__

#
# Validate the package name makes some sort of sense.
#

[[ "${BUILD_PACKAGE}" =~ ^kernel-.* ]] || \
	fatal "Package name '${BUILD_PACKAGE}' invalid: should begin kernel-xxx e.g. kernel-ajm"

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
# Get the source version number.
#

SOURCE_VERSION=$(basename "${BUILD_SOURCE}" | sed -e 's/linux-//g')

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
# Now check we understand how to build for this architecture.
#

ACTUAL_SOURCES="${ACTUAL_SOURCE}/SOURCES"
ACTUAL_SPECS="${ACTUAL_SOURCE}/SPECS"

#
# Verify we have an RPM spec, so we can extract the actual kernel version.
# From time to time there may be a requirement to patch, so this may end up being
# something like linux-6.6.100p1. Hence we need to grep the upstream version.
#

ACTUAL_SPEC="${ACTUAL_SPECS}/linux.spec"
[ -r "${ACTUAL_SPEC}" ] || fatal "I don't know how to build source:${BUILD_SOURCE}" \
	" on arch:${BUILD_ARCH} -- spec not found: ${ACTUAL_SPEC}"

#
# Calculate the kernel branch we're on and some URLs for things like CDNs.
# We do this by exploding out the version identifiers.
#

KERNEL_VERSION=$(grep " LKAver " "${ACTUAL_SPEC}" | sed -e 's/.*LKAver //g')
KERNEL_MAJOR=$(echo "${KERNEL_VERSION}" | cut -f1 -d.)
KERNEL_MINOR=$(echo "${KERNEL_VERSION}" | cut -f2 -d.)
KERNEL_PATCH=$(echo "${KERNEL_VERSION}" | cut -f3- -d.)

#
# Example versions:
#
# TARGET         |  MAJOR  |  MINOR    | PATCH
# ---------------+---------+-----------+-----------+
# linux-6.0      | "6"     |  "0"      | Nil
# linux-6.1.12   | "6"     |  "1"      | "12"
# linux-6.2-rc1  | "6"     |  "2-rc1"  | Nil
#
# From this we fix up where PATCH is undefined.

[ -z "${KERNEL_PATCH}" ] && KERNEL_PATCH="0"

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

#
# Identify if this is a prerelease by exploding out the minor version.
#

KERNEL_PRERELEASE=$(echo "${KERNEL_MINOR}" | grep "rc")

#
# If the PRERELEASE tag is not empty, this is not a formal released version
#

if [ ! -z "${KERNEL_PRERELEASE}" ]; then
	KERNEL_CDN="https://git.kernel.org/torvalds/t"
	KERNEL_TAR="linux-${KERNEL_VERSION}.tar"
	KERNEL_TARGZ="${KERNEL_TAR}.gz"

	# Generate a source URL
	KERNEL_SRCURL="${KERNEL_CDN}/${KERNEL_TARGZ}"
else
	KERNEL_PRERELEASE="no"
	KERNEL_CDN="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x"
	KERNEL_TAR="linux-${KERNEL_VERSION}.tar"
	KERNEL_TARXZ="${KERNEL_TAR}.xz"

	# Generate a source URL
	KERNEL_SRCURL="${KERNEL_CDN}/${KERNEL_TARXZ}"
fi

#
# Check what file we ended up with in the source URL
#

KERNEL_SRCFILE=${KERNEL_SRCURL##*/}

#
# Some cute variables for our hello, as well as the kernel build string.
# This will get burned into the spec later.
#

BUILD_SPEC=$(basename "${ACTUAL_SPEC}")
BUILD_ID=".ajm${BUILD_PATCHLEVEL}${BUILD_SHA}.${BUILD_TS}"
BUILD_RESULTPATH="${RESULTPATH}.${BUILD_CHROOT}${BUILD_ID}"

#
# Now generate a temporary path for doing all our work in
#

TMP_SRCFILE=$(mktemp "${TMPNAME}.bin")
TMP_BUILDROOT=$(mktemp -d "${TMPNAME}.buildroot.${BUILD_TS}")
TMP_BUILDSOURCES="${TMP_BUILDROOT}/SOURCES"
TMP_BUILDSPECS="${TMP_BUILDROOT}/SPECS"
TMP_BUILDSPEC="${TMP_BUILDSPECS}/${BUILD_SPEC}"

#
# Say hello.
#

cat <<__EOF__

I am going to try and build:

SOURCE_VERSION:    ${SOURCE_VERSION}

KERNEL_VERSION:    ${KERNEL_VERSION}
KERNEL_PRERELEASE: ${KERNEL_PRERELEASE}
KERNEL_SRCFILE:    ${KERNEL_SRCFILE}
KERNEL_SRCURL:     ${KERNEL_SRCURL}

Build package:     ${BUILD_PACKAGE}
Build source:      ${BUILD_SOURCE}
Build arch:        ${BUILD_ARCH}
Build chroot:      ${BUILD_CHROOT}
Build spec:        ${BUILD_SPEC}
Build patchlevel:  ${BUILD_PATCHLEVEL}
Build ID:          ${BUILD_ID}

Binary build:      ${BUILD_BINARIES}
Signed build:      ${BUILD_SIGNED}

Working path:      ${TMP_BUILDROOT}
Results path:      ${BUILD_RESULTPATH}
Manifest output:   ${BUILD_MANIFEST}

__EOF__

#
# Download ...
#

echo "Downloading ..."
${CURL} "${KERNEL_SRCURL}" -o "${TMP_SRCFILE}" --fail --silent --show-error \
	|| fatal "Curling the source failed: ${KERNEL_SRCURL}"

#
# Setup a temporary SOURCES path and copy files into place
#

echo "Copying local sources into place ..."
cp -rf "${ACTUAL_SOURCES}" "${TMP_BUILDSOURCES}" || fatal "Copy SOURCES failed"

echo "Moving kernel source into place ..."
mv -f "${TMP_SRCFILE}" "${TMP_BUILDSOURCES}/${KERNEL_SRCFILE}" || fatal "Move TAR failed"

echo "Rendering spec files ..."
mkdir -p "${TMP_BUILDSPECS}"
sed -e	"s/^Source0:.*$/Source0: ${KERNEL_SRCFILE}/g;
		s/^NoSource:.*$//g;
		s/kernel-lt/${BUILD_PACKAGE}/g;
		s/kernel-ml/${BUILD_PACKAGE}/g;" \
		    "${ACTUAL_SPEC}" >"${TMP_BUILDSPEC}" || \
			fatal "Rendering spec failed: ${ACTUAL_SPEC} > ${TMP_BUILDSPEC}"

echo "Build root prepared -- contents:"

ls -lR "${TMP_BUILDROOT}"

echo ""
echo "Here we go..."
echo ""
echo "==============================================================================="

echo "Initialising chroot: ${BUILD_CHROOT} ..."
${MOCK} --root "${BUILD_CHROOT}" --init --quiet || fatal "Mock init failed"

echo "Building src.rpm ..."
${MOCK} --root "${BUILD_CHROOT}" \
 		--buildsrpm \
 		--spec="${TMP_BUILDSPEC}" \
 		--sources="${TMP_BUILDSOURCES}" \
		--define "buildid ${BUILD_ID}" \
 		--resultdir="${BUILD_RESULTPATH}" \
 		|| fatal "Mock build src.rpm failed"

#
# Get a list of all the Source RPMs we just built based on the BUILD ID.
#

SOURCE_RPM=$(find "${BUILD_RESULTPATH}" -name "*.src.rpm" -type f -print 2>/dev/null)
[ -f "${SOURCE_RPM}" ] || fatal "Cannot find source RPM: ${SOURCE_RPM}"

#
# Declare an array of all output files
#

BUILD_RESULTS=( "${SOURCE_RPM}" )

#
# Do we need to do a binary build?
#

if [ "${BUILD_BINARIES}" == "yes" ]; then

	echo "Building bin.rpm for ${ACTUAL_ARCH} ..."
	${MOCK} --root "${BUILD_CHROOT}" \
		--rebuild "${SOURCE_RPM}" \
		--define "buildid ${BUILD_ID}" \
 		--resultdir="${BUILD_RESULTPATH}" \
 		|| fatal "Mock build-rpm (bin.rpm) failed"
	
	#
	# Get a list of every compiled binary we just produced and stuff it into
	# our BUILD_RESULTS array
	#

	echo "Identifying compiled binaries ..."

	for f in "${BUILD_RESULTPATH}"/*"${BUILD_ID}"*.rpm; do
		BUILD_RESULTS+=( "${f}" )
	done

else

	echo "Skipping binary build ..."

fi

#
# Tell the user how many things we built.
#

echo "Files built: ${#BUILD_RESULTS[@]}"
for f in ${BUILD_RESULTS[@]}; do
	echo "File: ${f}"
done

#
# Sign what we need to sign
#

if [ "${BUILD_SIGNED}" == "yes" ]; then

	echo "Signing files..."

	for f in ${BUILD_RESULTS[@]}; do
		${RPMSIGN} --addsign \
			--define "_gpg_name ${DEVS}" "${f}" 1>/dev/null \
			|| fatal "rpmsign failed on file: ${f}"
	done

else

	echo "Skipping signing ..."

fi

#
# Dump a list of what we've built
#

echo "Build is complete!"

ls -lhR "${BUILD_RESULTPATH}"

#
# Extract the full build string from the source RPM. Note, because the source
# RPM won't have our architecutre on, we append that ourselves.
#

BUILD_STRING=$(basename "${SOURCE_RPM}" | sed -e "s|${BUILD_PACKAGE}-||g;s|.src.rpm||g")
BUILD_STRING="${BUILD_STRING}.${BUILD_ARCH}"
printf "%s\n" "${BUILD_STRING}" >BuildString.txt

#
# Look for build.log and rename it to something that includes the build string,
# so people know where this log file came from.
#

if [ -f "${BUILD_RESULTPATH}/build.log" ]; then
	echo "Found build log, renaming it ..."

	NEW_BUILDLOG="build-${BUILD_STRING}.log"

	mv -f "${BUILD_RESULTPATH}/build.log" "${BUILD_RESULTPATH}/${NEW_BUILDLOG}" \
		|| fatal "move build log failed"

	BUILD_RESULTS+=( "${BUILD_RESULTPATH}/${NEW_BUILDLOG}" )
fi

#
# Look for a ChangeLog in the sources. If it exists, just copy it across into
# the outputs to be picked if we're running in a pipeline one day.
#

BUILD_CL="${TMP_BUILDSOURCES}/ChangeLog.md"
if [ -r "${BUILD_CL}" ]; then

	echo "Found change log in sources, copying it into the build ..."

	NEW_CHANGELOG="ChangeLog-${BUILD_STRING}.md"

	cp -f "${BUILD_CL}" "${BUILD_RESULTPATH}/${NEW_CHANGELOG}" \
		|| fatal "copy change log failed"
	
	BUILD_RESULTS+=( "${BUILD_RESULTPATH}/${NEW_CHANGELOG}" )

else

	echo "No change log found in sources, generating a dummy log ..."

	DUMMY_CHANGELOG="${BUILD_RESULTPATH}/ChangeLog-${BUILD_STRING}.md"

	cat <<__EOF__ >"${DUMMY_CHANGELOG}"
# Kernel ${KERNEL_VERSION} for Enterprise Linux

This build of ${BUILD_PACKAGE} did not have any internal Change Log.

Package name:  ${BUILD_PACKAGE}
Package build: ${BUILD_STRING}
Binary build:  ${BUILD_BINARIES}
Signed build:  ${BUILD_SIGNED}

__EOF__

	BUILD_RESULTS+=( "${DUMMY_CHANGELOG}" )

fi

#
# Now print a list of all files we've built into our build manifest
#

printf "%s\n" "${BUILD_RESULTS[@]}" >"${BUILD_MANIFEST}"

exit 0