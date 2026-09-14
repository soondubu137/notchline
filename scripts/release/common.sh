# Shared by the release scripts. Source it; do not run it.
#
# Every setting can be overridden from the environment, which is how a rehearsal signs with a
# throwaway certificate and key instead of the release ones.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PROJECT="$REPO_ROOT/Notchline/Notchline.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
BUNDLE_ID=com.yinfenglu.Notchline
REPOSITORY_URL=https://github.com/soondubu137/notchline

: "${IDENTITY_NAME:=Notchline Release}"
: "${KEYCHAIN:=$HOME/Library/Keychains/login.keychain-db}"
# The Keychain account `generate_keys` stores the private EdDSA key under.
: "${SPARKLE_ACCOUNT:=$BUNDLE_ID}"
# A private key file used instead of the Keychain entry. Rehearsals only.
: "${SPARKLE_KEY_FILE:=}"
: "${DR_FILE:=$REPO_ROOT/scripts/release/designated-requirement.txt}"
: "${FEED_FILE:=$REPO_ROOT/appcast.xml}"
: "${BUILD_ROOT:=$REPO_ROOT/build/release}"
: "${DERIVED_DATA:=$BUILD_ROOT/DerivedData}"
: "${DOWNLOAD_URL_PREFIX:=$REPOSITORY_URL/releases/download}"

die() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo "==> $*"
}

# Sparkle's command-line tools ship inside its package artifact, so resolve the package first.
sparkle_bin() {
    local bin="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"
    if [ ! -x "$bin/sign_update" ]; then
        xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme Notchline \
            -derivedDataPath "$DERIVED_DATA" >/dev/null
    fi
    [ -x "$bin/sign_update" ] || die "Sparkle's tools are not at $bin"
    echo "$bin"
}

# The SHA-1 of the release certificate, lower case, or nothing when it is absent. More than one
# certificate with the name is an error: the designated requirement pins exactly one.
certificate_sha1() {
    local hashes
    hashes=$( (security find-certificate -a -c "$IDENTITY_NAME" -Z "$KEYCHAIN" 2>/dev/null || true) \
        | awk '/^SHA-1 hash:/ { print tolower($3) }')
    [ "$(printf '%s' "$hashes" | grep -c .)" -le 1 ] \
        || die "more than one certificate named \"$IDENTITY_NAME\" in $KEYCHAIN"
    printf '%s' "$hashes"
}

designated_requirement() {
    (codesign -d -r- "$1" 2>/dev/null || true) | sed -n 's/^designated => //p'
}

# Re-signs a built bundle inside out with the release certificate.
#
# Sparkle's XPC services exist for sandboxed hosts; Notchline is not one, so they are removed
# rather than re-signed. The build's entitlements are kept except `get-task-allow`, which
# "Sign to Run Locally" adds for the debugger. Hardened runtime stays off: without notarisation it
# buys nothing, and it would refuse Apple Events without an extra entitlement.
sign_app() {
    local app=$1
    local framework="$app/Contents/Frameworks/Sparkle.framework"
    local entitlements
    entitlements=$(mktemp -t notchline-entitlements)

    if [ -d "$framework" ]; then
        rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"
        codesign --force --sign "$IDENTITY_NAME" "$framework/Versions/B/Autoupdate"
        codesign --force --sign "$IDENTITY_NAME" "$framework/Versions/B/Updater.app"
        codesign --force --sign "$IDENTITY_NAME" "$framework"
    fi

    codesign -d --entitlements "$entitlements" --xml "$app" 2>/dev/null || true
    if [ -s "$entitlements" ]; then
        /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$entitlements" \
            >/dev/null 2>&1 || true
        codesign --force --sign "$IDENTITY_NAME" --entitlements "$entitlements" "$app"
    else
        codesign --force --sign "$IDENTITY_NAME" "$app"
    fi
    rm -f "$entitlements"

    codesign --verify --strict --deep "$app"
}

# Fails unless the bundle's designated requirement is the one recorded when the certificate was
# made. A different certificate would cost every user their Automation grant and Sparkle's
# code-signing anchor, so it must never ship by accident.
verify_requirement() {
    local app=$1 expected actual
    [ -f "$DR_FILE" ] || die "no $DR_FILE; run scripts/release/create-release-identity.sh first"
    expected=$(cat "$DR_FILE")
    actual=$(designated_requirement "$app")
    [ "$actual" = "$expected" ] \
        || die "designated requirement is
  $actual
not the recorded
  $expected"
}

# Prints `sparkle:edSignature="…" length="…"` for an archive.
sign_archive() {
    local bin output
    bin=$(sparkle_bin)
    # sign_update reports its errors on stdout, which the caller is capturing.
    if [ -n "$SPARKLE_KEY_FILE" ]; then
        output=$("$bin/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" "$1" 2>&1) \
            || die "sign_update: $output"
    else
        output=$("$bin/sign_update" --account "$SPARKLE_ACCOUNT" "$1" 2>&1) \
            || die "sign_update: $output"
    fi
    printf '%s\n' "$output"
}

info_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}
