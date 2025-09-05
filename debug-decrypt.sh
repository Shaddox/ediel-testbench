#!/usr/bin/env bash
set -euo pipefail

EML="${1:-./simulated-received-message/encrypted_ediel.eml}"
OUT_EDI="${2:-./simulated-decrypted-message/message.edi}"

OUR_CERT="./keys/our-cert/our_cert.pem"
OUR_KEY="./keys/our_key.pem"   # <- ensure this matches your layout

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT_EDI")"

# 1) Decrypt: feed the whole .eml as SMIME; OpenSSL will pick the matching RecipientInfo
openssl smime -decrypt \
  -inform SMIME \
  -in "$EML" \
  -recip "$OUR_CERT" -inkey "$OUR_KEY" \
  -out "$TMP/inner.mime"

# 2) Show what we got (first 20 header lines)
echo "---- inner.mime (head) ----"
head -n 20 "$TMP/inner.mime" || true
echo "---------------------------"

# 3) Extract body (after the first blank line; handle spaces/CRLF)
#    Use a robust blank-line detector: lines that are only whitespace count as blank
awk 'BEGIN{b=0} {
  gsub(/\r$/,"");
  if (!b) { if ($0 ~ /^[[:space:]]*$/) { b=1; next } }
  else { print }
}' "$TMP/inner.mime" > "$TMP/edifact.b64"

# 4) Confirm Content-Type is what we expect (optional but useful)
ctype=$(awk 'BEGIN{RS=""; FS="\n"} NR==1{
  for(i=1;i<=NF;i++){ if ($i ~ /^Content-Type:/i){print $i; exit} }
}' "$TMP/inner.mime" || true)
echo "Detected inner Content-Type: ${ctype:-<none>}"

# 5) Sanity check: non-empty base64 body?
if ! [ -s "$TMP/edifact.b64" ]; then
  echo "❌ No base64 body found after headers. Check inner.mime above."
  exit 1
fi

# 6) Decode base64 (ignore whitespace with -i) and write .edi
base64 -di "$TMP/edifact.b64" > "$OUT_EDI" || {
  echo "❌ Base64 decode failed. Dumping first 60 chars of body:"
  head -c 60 "$TMP/edifact.b64" | od -An -tx1
  exit 1
}

# 7) Final validation
if [ ! -s "$OUT_EDI" ]; then
  echo "❌ Decryption/base64 succeeded but EDIFACT is empty."
  exit 1
fi

echo "✅ Decrypted EDIFACT written to: $OUT_EDI"
wc -c "$OUT_EDI"
