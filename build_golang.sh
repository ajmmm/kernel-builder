#!/usr/bin/env bash

BASENAME=$(basename "${0}")
BASEPATH=$(dirname "${0}")
BASEPKG="golang-ajm"
BASESPEC="golang.spec"

. "${BASEPATH}/build_lib.sh"

#
# Say hello
#

SOURCE_VERSION=$(basename "${BUILD_SOURCE}" | sed -e 's/linux-//g')

cat <<__EOF__

        ______      __                 
       / ____/___  / /___ _____  ____ _
      / / __/ __ \/ / __ `/ __ \/ __ `/
     / /_/ / /_/ / / /_/ / / / / /_/ / 
     \____/\____/_/\__,_/_/ /_/\__, /  
                              /____/   

========================== ajm edition ==
 V. ${SOURCE_VERSION}
__EOF__

GOLANG_VERSION=$(grep " go_version " "${ACTUAL_SPEC}" | sed -e 's/.*go_version //g')

#
# Get our RESULTPATH
#

BUILD_RESULTPATH=$(get_resultpath "${GOLANG_VERSION}" || exit 1)

#
# Say what we're going to do.
#

cat <<__EOF__

I am going to try and build:

GOLANG_VERSION:    ${GOLANG_VERSION}

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

setup_build

#
# Render spec
#

echo "Rendering spec files ..."
mkdir -p "${TMP_BUILDSPECS}"
sed -e	"s/^NoSource:.*$//g;" "${ACTUAL_SPEC}" >"${TMP_BUILDSPEC}" || \
	fatal "Rendering spec failed: ${ACTUAL_SPEC} > ${TMP_BUILDSPEC}"

echo "Build root prepared -- contents:"

ls -lR "${TMP_BUILDROOT}"

#
# Do build
#

run_build

exit 0
