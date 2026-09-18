#!/bin/bash
#
# This script generates Swift SDKs for Linux targets using the swift-sdk-generator. Each generated
# Swift SDK will be installed into the local Swift toolchain for use and testing.
#
# Usage:
#   1. Run this script to generate and install the Swift SDKs. This script can be re-run to
#      re-generate Swift SDKs if needed. Old SDKs will be removed before installing newly
#      generated ones.
#

set -e

SWIFT_VERSION=$1
if [ -z "$SWIFT_VERSION" ]; then
   echo "You must provide a Swift version. E.g. 6.4.0"
   exit -1
fi

DISTRO_NAME=$2
if [ -z "$DISTRO_NAME" ]; then
   echo "You must provide a distribution name. E.g. ubuntu"
   exit -1
fi

DISTRO_VERSION=$3
if [ -z "$DISTRO_VERSION" ]; then
   echo "You must provide a distribution version. E.g. noble"
   exit -1
fi

function generate_swift_sdk {
    TARGET_ARCH=$1
    SDK_NAME="${SWIFT_VERSION}-RELEASE_${DISTRO_NAME}_${DISTRO_VERSION}_${TARGET_ARCH}"

    #TMPDIR=$(mktemp -d /tmp/.workingXXXXXX)
    #cd "$TMPDIR"

    # TMP: Skip existing Swift SDKs if they exist
    if [ -d "Bundles/${SDK_NAME}.artifactbundle" ]; then
        echo "Swift SDK for ${TARGET_ARCH} already exists. Skipping generation."
        return
    fi

    echo
    echo "=================================================================================="
    echo "Generating Swift SDK for ${TARGET_ARCH} : ${SWIFT_VERSION} on ${DISTRO_NAME} ${DISTRO_VERSION}..."

    if [ "$TARGET_ARCH" = "armv7" ]; then
        DOWNLOAD_FILENAME=swift-${SWIFT_VERSION}-RELEASE-${DISTRO_NAME}-${DISTRO_VERSION}-armv7-install
        DOWNLOAD_PATH="Artifacts/${DOWNLOAD_FILENAME}"

        echo "Downloading & extracting armv7 runtime..."
        wget -nc -nv https://github.com/swift-embedded-linux/armhf-debian/releases/download/${SWIFT_VERSION}/${DOWNLOAD_FILENAME}.tar.gz -O ${DOWNLOAD_PATH}.tar.gz
        rm -rf "${DOWNLOAD_PATH}" && mkdir "${DOWNLOAD_PATH}" && \
        tar -xf ${DOWNLOAD_PATH}.tar.gz -C "${DOWNLOAD_PATH}"

        ./.build/release/swift-sdk-generator make-linux-sdk \
            --swift-version ${SWIFT_VERSION}-RELEASE \
            --distribution-name ${DISTRO_NAME} \
            --distribution-version ${DISTRO_VERSION} \
            --target armv7-unknown-linux-gnueabihf \
            --target-swift-package-path "${DOWNLOAD_PATH}"
    else
        ./.build/release/swift-sdk-generator make-linux-sdk \
            --swift-version ${SWIFT_VERSION}-RELEASE \
            --distribution-name ${DISTRO_NAME} \
            --distribution-version ${DISTRO_VERSION} \
            --target "${TARGET_ARCH}-unknown-linux-gnu"
    fi

    #swift sdk remove "${SDK_NAME}" &2>/dev/null || true  # ignore error if it doesn't exist
    #swift sdk install "Bundles/${SDK_NAME}.artifactbundle"
}

if [ ! -d swift-sdk-generator ]; then
    echo "swift-sdk-generator not found. Please run build-sdk-generator.sh first."
    exit -1
fi

cd swift-sdk-generator

# Generate SDKs
generate_swift_sdk "x86_64"
generate_swift_sdk "aarch64"
generate_swift_sdk "armv7"

# Test SDKS?
