#!/usr/bin/env bash

BASENAME=$(basename "${0}")
BASEPATH=$(dirname "${0}")
BASEPKG="kernel-ajm"
BASESPEC="linux.spec"

. "${BASEPATH}/build_lib.sh"

#
# Say hello
#

SOURCE_VERSION=$(basename "${BUILD_SOURCE}" | sed -e 's/linux-//g')

cat <<__EOF__

   __ _                                              _ 
  / /(_)_ __  _   ___  __   /\ /\___ _ __ _ __   ___| |
 / / | | '_ \| | | \ \/ /  / //_/ _ \ '__| '_ \ / _ \ |
/ /__| | | | | |_| |>  <  / __ \  __/ |  | | | |  __/ |
\____/_|_| |_|\__,_/_/\_\ \/  \/\___|_|  |_| |_|\___|_|

======================================== ajm edition ==

 Ver. ${SOURCE_VERSION}
__EOF__

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
BUILD_RESULTPATH="${BUILDROOT}/${BASEPKG}-${KERNEL_VERSION}${BUILD_ID}.${BUILD_CHROOT}"

#
# Now generate a temporary path for doing all our work in
#

TMP_SRCFILE=$(mktemp "${TMPNAME}.bin")
TMP_BUILDROOT=$(mktemp -d "${TMPNAME}.buildroot.${BUILD_TS}")
TMP_BUILDSOURCES="${TMP_BUILDROOT}/SOURCES"
TMP_BUILDSPECS="${TMP_BUILDROOT}/SPECS"
TMP_BUILDSPEC="${TMP_BUILDSPECS}/${BUILD_SPEC}"

#
# Say what we're going to do.
#

cat <<__EOF__

I am going to try and build:

KERNEL_VERSION:    ${KERNEL_VERSION}
KERNEL_PRERELEASE: ${KERNEL_PRERELEASE}
KERNEL_SRCFILE:    ${KERNEL_SRCFILE}
KERNEL_SRCURL:     ${KERNEL_SRCURL}

Build package:     ${BASEPKG}
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
		s/kernel-lt/${BASEPKG}/g;
		s/kernel-ml/${BASEPKG}/g;" \
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
# Kernel ${KERNEL_VERSION} for Enterprise Linux

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

exit 0