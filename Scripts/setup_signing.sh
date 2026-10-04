#!/bin/bash
# One-time setup: creates a self-signed code-signing certificate named "Butler Dev" in your
# login keychain so every build of Butler has the SAME code identity. macOS ties the
# Screen & System Audio Recording permission to that identity.
set -euo pipefail

CERT_NAME="${1:-Butler Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$CERT_NAME\""; then
  echo "Code-signing identity '$CERT_NAME' already exists and is valid."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="butler-temp-$$"

cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

echo "Creating self-signed certificate '$CERT_NAME'..."
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf"

# Apple's security tool needs a PKCS#12 it can read; Homebrew OpenSSL 3 needs -legacy.
if ! openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
      -out "$TMP/cert.p12" -passout "pass:$PASS" 2>/dev/null; then
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout "pass:$PASS"
fi

echo "Importing into login keychain..."
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security

echo "Trusting it for code signing (macOS may ask for your password)..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo
security find-identity -v -p codesigning | grep "$CERT_NAME" \
  && echo "Done. Now run: xcodegen && open Butler.xcodeproj" \
  || { echo "Identity not listed as valid. Open Keychain Access > login > Certificates > '$CERT_NAME' > Trust > Code Signing: Always Trust."; exit 1; }
