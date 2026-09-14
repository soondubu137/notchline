#!/bin/bash
# Builds, signs and packages the checked-out version, and adds it to appcast.xml.
#
#   scripts/release/build-release.sh [--allow-dirty]
#
# Run it on the tagged cut commit. It prints the two publishing steps it does not take itself:
# uploading the archive to the GitHub release, then committing and pushing the feed. Upload first,
# or every copy that checks in between is offered an archive that does not exist yet.

source "$(dirname "$0")/common.sh"

allow_dirty=false
for argument in "$@"; do
    case $argument in
        --allow-dirty) allow_dirty=true ;;
        *) die "unknown argument $argument" ;;
    esac
done

if ! $allow_dirty && [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    die "the working tree has changes; a release is built from the tagged commit (--allow-dirty to rehearse)"
fi
[ -n "$(certificate_sha1)" ] || die "no certificate named \"$IDENTITY_NAME\"; run scripts/release/create-release-identity.sh"

step "Building Release"
xcodebuild build -project "$PROJECT" -scheme Notchline -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    ${EXTRA_BUILD_SETTINGS:-} -quiet
built="$DERIVED_DATA/Build/Products/Release/Notchline.app"

version=$(info_value "$built" CFBundleShortVersionString)
build=$(info_value "$built" CFBundleVersion)
minimum_system_version=$(info_value "$built" LSMinimumSystemVersion)
[ -n "$(info_value "$built" SUPublicEDKey)" ] || die "the build has no SUPublicEDKey"
[ "$(info_value "$built" SUEnableAutomaticChecks)" = YES ] || die "the build does not check automatically"

output="$BUILD_ROOT/$version"
rm -rf "$output"
mkdir -p "$output"
app="$output/Notchline.app"
ditto "$built" "$app"

step "Signing $version ($build) as \"$IDENTITY_NAME\""
sign_app "$app"
verify_requirement "$app"

step "Packaging"
archive_name="Notchline-$version.zip"
archive="$output/$archive_name"
# `--sequesterRsrc --keepParent`: the form Sparkle documents, preserving the bundle's symlinks.
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
signature=$(sign_archive "$archive")

step "Adding it to $(basename "$FEED_FILE")"
tag="v$version"
python3 "$REPO_ROOT/scripts/release/add_feed_item.py" \
    --feed "$FEED_FILE" \
    --changelog "$CHANGELOG_FILE" \
    --version "$version" \
    --build "$build" \
    --minimum-system-version "$minimum_system_version" \
    --archive-url "$DOWNLOAD_URL_PREFIX/$tag/$archive_name" \
    --release-url "$REPOSITORY_URL/releases/tag/$tag" \
    --signature-attributes "$signature"

cat <<EOF

Built $archive
Next:
  gh release upload $tag "$archive"
  git add appcast.xml && git commit -m "Offer $version to the update feed" && git push
EOF
