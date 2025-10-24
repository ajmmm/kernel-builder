#!/usr/bin/env bash

BASENAME=$(basename "${0}")
BASEPATH=$(dirname "${0}")
BASEPKG="kernel-ajm"
BASE_PKG=$(echo "${BASEPKG}" | sed -e 's/-/_/g')
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
 V. ${SOURCE_VERSION}
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

KERNEL_PRERELEASE=$(echo "${KERNEL_MINOR}" | cut -f2 -d-)

#
# If the PRERELEASE tag is not empty, this is not a formal released version
#

if [ ! -z "${KERNEL_PRERELEASE}" ]; then
	KERNEL_CDN="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/snapshot"
	KERNEL_TAR="linux-${KERNEL_VERSION}.tar"
	KERNEL_TARGZ="${KERNEL_TAR}.gz"

	# Generate a source URL
	KERNEL_SRCURL="${KERNEL_CDN}/${KERNEL_TARGZ}"

	# KERNEL_VERSION will be something like 6.18-rc2, with MAJOR at 6
	# and MINOR at 18-rc2. We need to trasnslate this back to 6.18.0.
	KERNEL_MINOR=$(echo "${KERNEL_MINOR}" | cut -f1 -d-)
	KERNEL_PATCH="0"
	KERNEL_VERSION="${KERNEL_MAJOR}.${KERNEL_MINOR}.${KERNEL_PATCH}"
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
# Get our RESULTPATH
#

BUILD_RESULTPATH=$(get_resultpath "${KERNEL_VERSION}" || exit 1)

#
# Say what we're going to do.
#

cat <<__EOF__

I am going to try and build:

KERNEL_VERSION:    ${KERNEL_VERSION}
KERNEL_PRERELEASE: ${KERNEL_PRERELEASE}
KERNEL_SRCFILE:    ${KERNEL_SRCFILE}
KERNEL_SRCURL:     ${KERNEL_SRCURL}

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
# Prepare the build
#

setup_build "${KERNEL_SRCURL}" "${KERNEL_SRCFILE}"

#
# Render spec
#

echo "Rendering spec files ..."
mkdir -p "${TMP_BUILDSPECS}"
sed -e	"s/^Source0:.*$/Source0: ${KERNEL_SRCFILE}/g;
		s/^NoSource:.*$//g;
		s/^%define sublevel .*/%define sublevel ${KERNEL_PATCH}/g;
		s/^%global pkg_version %{LKAver}$/%global pkg_version ${KERNEL_VERSION}/g;
		s/kernel-lt/${BASEPKG}/g;
		s/kernel-ml/${BASEPKG}/g;
		s/kernel_lt/${BASE_PKG}/g;
		s/kernel_ml/${BASE_PKG}/g;" \
		    "${ACTUAL_SPEC}" >"${TMP_BUILDSPEC}" || \
			fatal "Rendering spec failed: ${ACTUAL_SPEC} > ${TMP_BUILDSPEC}"

echo "Build root prepared -- contents:"

ls -lR "${TMP_BUILDROOT}"

#
# Do build
#

run_build

exit 0
