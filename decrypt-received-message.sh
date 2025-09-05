#!/usr/bin/env bash
set -euo pipefail

EML="${1:-./simulated-received-message/encrypted_ediel.eml}"
OUR_CERT="./keys/our-cert/our_cert.pem"   # the cert that matches our private key
OUR_KEY="./keys/our_key.pem"     # our private key
OUT_EDI="${2:-./simulated-decrypted-message/message.edi}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$(dirname "$OUT_EDI")"

# 1) extract the S/MIME blob (Base64) from the .eml and decode to binary p7m
awk 'f{print} /^$/{f=1}' "$EML" | tr -d '\r' > "$TMP/smime.b64"
base64 -d "$TMP/smime.b64" > "$TMP/smime.p7m"

# 2) decrypt the enveloped-data to reveal the inner MIME entity
#    (OpenSSL will pick the right RecipientInfo if you encrypted to multiple certs)
openssl smime -decrypt \
  -in "$TMP/smime.p7m" -inform SMIME \
  -recip "$OUR_CERT" -inkey "$OUR_KEY" \
  -out "$TMP/inner.mime"

# 3) the inner MIME is your original "application/EDIFACT" wrapper with a Base64 body.
#    strip headers and decode to get the raw .edi
awk 'f{print} /^$/{f=1}' "$TMP/inner.mime" | tr -d '\r' > "$TMP/edifact.b64"
base64 -d "$TMP/edifact.b64" > "$OUT_EDI"

echo "✅ Decrypted EDIFACT written to: $OUT_EDI"
