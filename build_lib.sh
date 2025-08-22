#!/usr/bin/env bash

function fatal() {
	echo "FATAL ERROR: $@"
	exit 1
}

function sep() {
	echo "==============================================================================="
}

BUILDROOT="${BASEPATH}/buildroot"
CURL=$(which curl 2>/dev/null) || fatal "I need curl!"
SPECTOOL=$(which spectool 2>/dev/null) || fatal "I need spectool!"
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
BUILD_MANIFEST="bld.${BASEPKG}.manifest"
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

BUILD_SPEC=$(basename "${ACTUAL_SPEC}")

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
# Now generate a temporary path for doing all our work in
#

TMP_SRCFILE=$(mktemp "${TMPNAME}.bin")
TMP_BUILDROOT=$(mktemp -d "${TMPNAME}.buildroot.${BUILD_TS}")
TMP_BUILDSOURCES="${TMP_BUILDROOT}/SOURCES"
TMP_BUILDSPECS="${TMP_BUILDROOT}/SPECS"
TMP_BUILDSPEC="${TMP_BUILDSPECS}/${BUILD_SPEC}"

#
# Some cute variables for our hello, as well as the kernel build string.
# This can be used to burn build info into spec files later.
#

BUILD_ID=".ajm${BUILD_PATCHLEVEL}${BUILD_SHA}.${BUILD_TS}"

#
# Hacky function to produce a full result path
#

function get_resultpath() {

	local basever="${1}"

	[ -z "${basever}" ] && fatal "get_resultpath: No basever"
	[ -z "${BUILDROOT}" ] && fatal "get_resultpath: No BUILDROOT"

	local resultpath="${BUILDROOT}/${BASEPKG}-${basever}${BUILD_ID}.${BUILD_CHROOT}"

	echo "${resultpath}"
}

#
# Setup builds
#

function setup_build() {

	local basesrcurl="${1}"
	local basesrctar="${2}"

	sep

	echo "* Copying local sources into place ..."
	cp -rf "${ACTUAL_SOURCES}" "${TMP_BUILDSOURCES}" || fatal "Copy SOURCES failed"

	if [ -z "${basesrcurl}" ] && [ -z "${basesrctar}" ]; then

		echo " * Running spectool on ${TMP_BUILDSPEC} ..."

		${SPECTOOL} --get-files --sources --directory "${TMP_BUILDSOURCES}" "${ACTUAL_SPEC}" \
			|| fatal "spectool failed"
	
	else

		echo "* Downloading ${basesrcurl}..."
		${CURL} "${basesrcurl}" -o "${TMP_SRCFILE}" --fail --silent --show-error \
			|| fatal "Curling the source failed: ${basesrcurl}"

		echo "* Moving downloaded source into ${basesrctar} ..."
		mv -f "${TMP_SRCFILE}" "${TMP_BUILDSOURCES}/${basesrctar}" || fatal "Move TAR failed"

	fi

	echo "Build prepared!"
	echo ""
}

#
# Run build
#

function run_build() {

	sep

	echo "Here we go..."

	echo "* Initialising chroot: ${BUILD_CHROOT} ..."
	${MOCK} --root "${BUILD_CHROOT}" --init --quiet || fatal "Mock init failed"

	echo "* Building src.rpm ..."
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

		echo "* Identifying compiled binaries ..."

		for f in "${BUILD_RESULTPATH}"/*"${BUILD_ID}"*.rpm; do
			BUILD_RESULTS+=( "${f}" )
		done

	else

		echo "* Skipping binary build ..."

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

	BUILD_STRING=$(basename "${SOURCE_RPM}" | sed -e "s|${BASEPKG}-||g;s|.src.rpm||g")
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
# ${BASEPKG} for Enterprise Linux

This build of ${BASEPKG} did not have any internal Change Log.

Package name:  ${BASEPKG}
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
}
