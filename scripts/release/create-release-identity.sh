#!/bin/bash
# Creates, once, the two keys every Notchline release depends on, and writes a backup of each.
#
#   scripts/release/create-release-identity.sh <backup directory outside the repository>
#
# 1. A self-signed code-signing certificate named "Notchline Release", in the login keychain.
#    Signing every release with it keeps the designated requirement the same from build to
#    build, which is what keeps a user's Automation grant across updates. The certificate's hash
#    is written to scripts/release/designated-requirement.txt.
# 2. Sparkle's EdDSA key pair. The private key stays in the login keychain; the public key is
#    written into the project as NOTCHLINE_UPDATE_PUBLIC_ED_KEY, and every copy built from then on
#    accepts only updates signed with it.
#
# Losing either key has a permanent cost (docs/adr/0022), so the backups are not optional. Move the
# backup directory somewhere safe, such as a password manager, and delete it from disk.

source "$(dirname "$0")/common.sh"

[ $# -eq 1 ] || die "usage: $0 <backup directory outside the repository>"
mkdir -p "$1"
backup=$(cd "$1" && pwd)
case "$backup/" in
    "$REPO_ROOT"/*) die "the backup directory must be outside the repository" ;;
esac

[ -z "$(certificate_sha1)" ] || die "\"$IDENTITY_NAME\" already exists in $KEYCHAIN; it must never be replaced"
grep -q 'NOTCHLINE_UPDATE_PUBLIC_ED_KEY = "";' "$PBXPROJ" \
    || [ -n "$SPARKLE_KEY_FILE" ] \
    || die "the project already has a public EdDSA key; it must never be replaced"

work=$(mktemp -d -t notchline-identity)
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT

step "Creating the certificate \"$IDENTITY_NAME\""
cat > "$work/certificate.cnf" <<EOF
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = $IDENTITY_NAME
[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
# Twenty years: nothing checks a code signature's expiry by default, but no date should be
# anybody's problem.
/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -config "$work/certificate.cnf" \
    -keyout "$work/key.pem" -out "$work/certificate.pem" 2>/dev/null

# `security` refuses the PKCS#8 form `req` writes; the traditional RSA form imports.
/usr/bin/openssl rsa -in "$work/key.pem" -out "$work/key-rsa.pem" 2>/dev/null
security import "$work/key-rsa.pem" -k "$KEYCHAIN" -t priv -f openssl -T /usr/bin/codesign >/dev/null
security import "$work/certificate.pem" -k "$KEYCHAIN" -t cert -f pemseq >/dev/null

echo "Choose a passphrase for the certificate backup (it is not stored anywhere):"
read -rs passphrase
[ -n "$passphrase" ] || die "the backup needs a passphrase"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/certificate.pem" \
    -name "$IDENTITY_NAME" -out "$backup/notchline-release-certificate.p12" \
    -passout fd:3 3<<<"$passphrase"
unset passphrase
chmod 600 "$backup/notchline-release-certificate.p12"

step "Recording the designated requirement"
# Signing a copy of a small binary both proves codesign can use the new identity (a keychain
# prompt appears here, if at all) and yields the requirement exactly as codesign writes it.
cp /usr/bin/true "$work/probe"
codesign --force --sign "$IDENTITY_NAME" --identifier "$BUNDLE_ID" "$work/probe" 2>/dev/null \
    || die "codesign could not use \"$IDENTITY_NAME\"; is $KEYCHAIN on the keychain search list?"
requirement=$(designated_requirement "$work/probe")
[[ $requirement == "identifier \"$BUNDLE_ID\" and certificate "* ]] \
    || die "unexpected designated requirement: $requirement"
echo "$requirement" > "$DR_FILE"
echo "$requirement"

if [ -z "$SPARKLE_KEY_FILE" ]; then
    step "Creating Sparkle's EdDSA key"
    bin=$(sparkle_bin)
    "$bin/generate_keys" --account "$SPARKLE_ACCOUNT" >/dev/null
    public_key=$("$bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
    "$bin/generate_keys" --account "$SPARKLE_ACCOUNT" -x "$backup/notchline-sparkle-private-key"
    chmod 600 "$backup/notchline-sparkle-private-key"
    [[ $public_key =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "unexpected public key: $public_key"
    sed -i '' "s|NOTCHLINE_UPDATE_PUBLIC_ED_KEY = \"\";|NOTCHLINE_UPDATE_PUBLIC_ED_KEY = \"$public_key\";|g" "$PBXPROJ"
    echo "Public key $public_key written to the project"
fi

cat <<EOF

Done. Back up and then delete from disk:
  $backup/notchline-release-certificate.p12  (restore: security import … -T /usr/bin/codesign)
  $backup/notchline-sparkle-private-key      (restore: generate_keys --account $SPARKLE_ACCOUNT -f …)
Commit scripts/release/designated-requirement.txt and the project change.
EOF
