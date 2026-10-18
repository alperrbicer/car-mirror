#!/bin/sh
set -eu
# Simulator and local Debug tests never upload symbols or require network access.
if [ "${CONFIGURATION:-}" != "Release" ] || [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
    exit 0
fi
: "${MIRIVO_CRASHLYTICS_DIR:?Set the Crashlytics package directory in the build settings.}"
crashlytics_uploader="${MIRIVO_CRASHLYTICS_DIR}/upload-symbols"
if [ ! -f "$crashlytics_uploader" ]; then
    echo "error: Firebase Crashlytics symbol uploader is missing. Resolve the pinned Swift packages."
    exit 1
fi
# These are the same SDK commands used by Crashlytics/run. Keep the upload in
# the foreground so a Release build cannot silently lose its upload error.
"$crashlytics_uploader" --build-phase --validate
"$crashlytics_uploader" --build-phase
