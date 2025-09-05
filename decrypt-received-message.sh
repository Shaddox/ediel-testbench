#!/usr/bin/env bash
set -euo pipefail

# Decrypt an EDIEL S/MIME email (.eml) to raw .edi
# Usage: ./decrypt-received-message.sh INPUT.eml OUTPUT.edi

EML="${1:-./simulated-received-message/encrypted_ediel.eml}"
OUT_EDI="${2:-./simulated-decrypted-message/message.edi}"

# Paths to our certificate and private key (matching keypair!!!)
OUR_CERT="./keys/our-cert/our_cert.pem"
OUR_KEY="./keys/our_key.pem"   # adjust if key lives elsewhere

# Optional: if your key is passphrase-protected, export KEYPASS and uncomment:
# export KEYPASS="your-passphrase"
# PASSIN=(-passin env:KEYPASS)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT_EDI")"

# If it's not a full EML but just a raw body, we'd have to do some trickery
# base64 -di smime.b64 > smime.der
# openssl smime -decrypt -inform DER -in smime.der -recip "$OUR_CERT" -inkey "$OUR_KEY" -out inner.mime

# 1) Decrypt the S/MIME email directly
openssl smime -decrypt \
  -inform SMIME \
  -in "$EML" \
  -recip "$OUR_CERT" -inkey "$OUR_KEY" ${PASSIN:-} \
  -out "$TMP/inner.mime"

# 2) Extract the inner MIME body (handles CRLF and whitespace-only separator line)
awk 'BEGIN{b=0} { gsub(/\r$/,""); if(!b){ if($0 ~ /^[[:space:]]*$/){b=1; next} } else { print } }' \
  "$TMP/inner.mime" > "$TMP/edifact.b64"

# 3) Decode base64 body to .edi
base64 -di "$TMP/edifact.b64" > "$OUT_EDI"

# 4) Quick sanity check
if [ ! -s "$OUT_EDI" ]; then
  echo "❌ Decrypted file is empty. Check certificate/key pairing and input email." >&2
  exit 1
fi

echo "✅ Decrypted EDIFACT written to: $OUT_EDI"
