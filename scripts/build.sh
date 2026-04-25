#!/bin/bash

# Exit on error
set -e


# Build config-api
(
    cd packages/config-api
    npm run build
    npm run generate-types

    # Copy config API to finicky
    cd ../../
    cp packages/config-api/dist/finickyConfigAPI.js apps/finicky/src/assets/finickyConfigAPI.js
)

# Build finicky-ui
(
    cd packages/finicky-ui
    npm run build

    # Copy finicky-ui dist to finicky
    cd ../../

    # Ensure destination directory exists
    mkdir -p apps/finicky/src/assets/templates

    # Copy templates from dist to finicky app
    cp -r packages/finicky-ui/dist/* apps/finicky/src/assets/templates
)

# Get build information (shared across all arch builds)
COMMIT_HASH=$(git rev-parse --short HEAD)
BUILD_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
API_HOST=$(cat .env 2>/dev/null | grep API_HOST | cut -d '=' -f 2 || echo "")

build_arch() {
    local ARCH=$1
    local APP_NAME="Finicky-${ARCH}.app"

    cd apps/finicky
    mkdir -p build/${APP_NAME}/Contents/MacOS
    mkdir -p build/${APP_NAME}/Contents/Resources

    if [ "$ARCH" = "amd64" ]; then
        export GOARCH=amd64
        export CGO_ENABLED=1
        export CC=clang
        export CGO_CFLAGS="-target x86_64-apple-macos12.0"
        export CGO_LDFLAGS="-target x86_64-apple-macos12.0"
    else
        export GOARCH=arm64
        export CGO_ENABLED=1
        export CC=clang
        export CGO_CFLAGS="-mmacosx-version-min=12.0"
        export CGO_LDFLAGS="-mmacosx-version-min=12.0"
    fi

    go build -C src \
        -ldflags \
        "-X 'finicky/version.commitHash=${COMMIT_HASH}' \
        -X 'finicky/version.buildDate=${BUILD_DATE}' \
        -X 'finicky/version.apiHost=${API_HOST}'" \
        -o ../build/${APP_NAME}/Contents/MacOS/Finicky

    cd ../../
}

if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    # Build both architectures and combine with lipo
    build_arch arm64
    build_arch amd64

    APP_NAME="Finicky.app"
    mkdir -p apps/finicky/build/${APP_NAME}/Contents/MacOS
    mkdir -p apps/finicky/build/${APP_NAME}/Contents/Resources

    lipo -create \
        apps/finicky/build/Finicky-arm64.app/Contents/MacOS/Finicky \
        apps/finicky/build/Finicky-amd64.app/Contents/MacOS/Finicky \
        -output apps/finicky/build/${APP_NAME}/Contents/MacOS/Finicky

    lipo -info apps/finicky/build/${APP_NAME}/Contents/MacOS/Finicky

    # Copy static assets into universal app
    cp packages/config-api/dist/finicky.d.ts apps/finicky/build/${APP_NAME}/Contents/Resources/finicky.d.ts
    rsync -a --exclude='menu.iconset' apps/finicky/assets/ apps/finicky/build/${APP_NAME}/Contents/
elif [ -n "$BUILD_TARGET_ARCH" ]; then
    # Single-arch CI build (legacy/fallback)
    APP_NAME="Finicky-${BUILD_TARGET_ARCH}.app"
    build_arch ${BUILD_TARGET_ARCH}

    cp packages/config-api/dist/finicky.d.ts apps/finicky/build/${APP_NAME}/Contents/Resources/finicky.d.ts
    rsync -a --exclude='menu.iconset' apps/finicky/assets/ apps/finicky/build/${APP_NAME}/Contents/
else
    # Local build — native arch only
    APP_NAME="Finicky.app"
    NATIVE_ARCH=$(go env GOARCH)

    cd apps/finicky
    mkdir -p build/${APP_NAME}/Contents/MacOS
    mkdir -p build/${APP_NAME}/Contents/Resources
    export CGO_CFLAGS="-mmacosx-version-min=12.0"
    export CGO_LDFLAGS="-mmacosx-version-min=12.0"
    go build -C src \
        -ldflags \
        "-X 'finicky/version.commitHash=${COMMIT_HASH}' \
        -X 'finicky/version.buildDate=${BUILD_DATE}' \
        -X 'finicky/version.apiHost=${API_HOST}'" \
        -o ../build/${APP_NAME}/Contents/MacOS/Finicky
    cd ../../

    cp packages/config-api/dist/finicky.d.ts apps/finicky/build/${APP_NAME}/Contents/Resources/finicky.d.ts
    rsync -a --exclude='menu.iconset' apps/finicky/assets/ apps/finicky/build/${APP_NAME}/Contents/

    # Replace existing app
    rm -rf /Applications/Finicky.app
    cp -r apps/finicky/build/Finicky.app /Applications/
fi

echo "Build complete ✨"
