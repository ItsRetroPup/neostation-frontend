#!/bin/sh
# Applies `--dart-define=NEOSTATION_FLAVOR=<name>` to the built app's
# Info.plist so a developer build (e.g. `pup`) gets its own bundle ID and name
# and can run next to the release. Runs as the last Runner build phase, before
# Xcode code-signs the bundle. Must match lib/utils/build_flavor.dart.
#
# Flutter exposes dart-defines to Xcode as DART_DEFINES: a comma-separated
# list of base64-encoded `KEY=value` entries.
set -e

flavor=""
old_ifs="$IFS"
IFS=','
for encoded in $DART_DEFINES; do
  decoded=$(printf '%s' "$encoded" | base64 --decode 2>/dev/null || true)
  case "$decoded" in
    NEOSTATION_FLAVOR=*) flavor="${decoded#NEOSTATION_FLAVOR=}" ;;
  esac
done
IFS="$old_ifs"

plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
bundle_id="$PRODUCT_BUNDLE_IDENTIFIER"
name="$PRODUCT_NAME"
if [ -n "$flavor" ]; then
  bundle_id="$bundle_id.$flavor"
  first=$(printf '%s' "$flavor" | cut -c1 | tr '[:lower:]' '[:upper:]')
  name="$name $first$(printf '%s' "$flavor" | cut -c2-)"
fi

# Always write both values so switching back to a release build in the same
# build folder restores the original identity.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName \"$name\"" "$plist"
echo "NeoStation build flavor: '${flavor:-release}' -> $bundle_id"
