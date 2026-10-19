#!/bin/bash
# Project-only signing identity. Never modifies login/system keychains or root trust.
set -euo pipefail
cd "$(dirname "$0")/.."
signing_dir="$PWD/.dev-signing"
mkdir -p "$signing_dir"
chmod 700 "$signing_dir"
umask 077
if [ ! -s "$signing_dir/password" ]; then
    /usr/bin/openssl rand -hex 24 > "$signing_dir/password"
fi
IFS= read -r signing_password < "$signing_dir/password"
if [ ! -s "$signing_dir/certificate.pem" ]; then
    /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
        -keyout "$signing_dir/private-key.pem" -out "$signing_dir/certificate.pem" \
        -subj '/CN=MacOfficeTabs Local Development/' \
        -addext 'basicConstraints=critical,CA:FALSE' \
        -addext 'keyUsage=critical,digitalSignature' \
        -addext 'extendedKeyUsage=critical,codeSigning' >/dev/null 2>&1
fi
if [ ! -s "$signing_dir/identity.p12" ]; then
    /usr/bin/openssl pkcs12 -export -inkey "$signing_dir/private-key.pem" \
        -in "$signing_dir/certificate.pem" -out "$signing_dir/identity.p12" \
        -name 'MacOfficeTabs Local Development' -passout "file:$signing_dir/password"
fi
keychain="$signing_dir/development.keychain-db"
if [ ! -f "$keychain" ]; then
    /usr/bin/security create-keychain -p "$signing_password" "$keychain"
    /usr/bin/security unlock-keychain -p "$signing_password" "$keychain"
    /usr/bin/security import "$signing_dir/identity.p12" -k "$keychain" \
        -P "$signing_password" -T /usr/bin/codesign
    /usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$signing_password" "$keychain" >/dev/null
fi
/usr/bin/security unlock-keychain -p "$signing_password" "$keychain"
/usr/bin/openssl x509 -in "$signing_dir/certificate.pem" -noout -fingerprint -sha1 \
    | /usr/bin/sed 's/^.*=//;s/://g' > "$signing_dir/identity-sha1"
echo 'Project development keychain ready. No root trust or default keychain changes made.'
