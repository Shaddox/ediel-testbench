#!/usr/bin/env bash
set -euo pipefail

# ============================================
# CONFIGURATION
# ============================================

EDIFACT_FILE="${1:-edifact_message.edi}"
OUTPUT_FILE="${2:-encrypted_ediel_der.eml}"

SENDER_KEY="./keys/our_key.pem"
SENDER_CERT="./keys/our_cert.pem"
RECIPIENT_CERT_DIR="./keys/recipient"    # where recipient_*.pem live

CREATE_EMAIL="yes"
SENDER_EMAIL="ediel@sender.com"
RECIPIENT_EMAIL="ediel@recipient.com"

# ============================================
# VALIDATION & CERT COLLECTION
# ============================================

[ -f "$EDIFACT_FILE" ] \
  || { echo "❌ EDIFACT file not found"; exit 1; }
for f in "$SENDER_KEY" "$SENDER_CERT"; do
  [ -f "$f" ] || { echo "❌ Missing $f"; exit 1; }
done

# collect all recipient certs
mapfile -t RECIPIENT_CERTS < <(find "$RECIPIENT_CERT_DIR" -type f -name 'recipient_*.pem')
[ ${#RECIPIENT_CERTS[@]} -gt 0 ] \
  || { echo "❌ No recipient_*.pem in $RECIPIENT_CERT_DIR"; exit 1; }

# (Optional) CRL-check each, push into VALID_CERTS[]
VALID_CERTS=()
for cert in "${RECIPIENT_CERTS[@]}"; do
  if openssl x509 -in "$cert" -noout -checkend 0; then
    VALID_CERTS+=("$cert")
  else
    echo "⚠️  Skipping expired/invalid cert: $cert"
  fi
done
[ ${#VALID_CERTS[@]} -gt 0 ] \
  || { echo "❌ No valid recipient certs"; exit 1; }

# ============================================
# WORK DIR
# ============================================
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Step 1: MIME-wrap the EDIFACT
cat > "$TMP/mime.txt" <<EOF
Content-Type: application/EDIFACT
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=edifact

$(base64 -w 76 "$EDIFACT_FILE")
EOF

# Step 2: Sign → DER
openssl smime -sign \
  -nodetach \
  -in  "$TMP/mime.txt" \
  -signer "$SENDER_CERT" \
  -inkey  "$SENDER_KEY" \
  -out   "$TMP/signed.der" \
  -outform DER

# Step 3: Encrypt → DER
openssl smime -encrypt \
  -des3 \
  -in   "$TMP/signed.der" \
  -out  "$TMP/encrypted.der" \
  -outform DER \
  "${VALID_CERTS[@]}"

# Base64-encode the DER for email transport
base64 -w 76 "$TMP/encrypted.der" > "$TMP/encrypted.der.b64"

# ============================================
# BUILD OUTPUT EMAIL
# ============================================
if [ "$CREATE_EMAIL" = "yes" ]; then
  UNB=$(grep '^UNB' "$EDIFACT_FILE" | head -1 || echo 'UNB+UNKNOWN')
  {
    echo "From: <$SENDER_EMAIL>"
    echo "To: <$RECIPIENT_EMAIL>"
    echo "Subject: PRODAT $UNB"
    echo "Date: $(date -R)"
    echo "Message-ID: <$(date +%s).$$@$(hostname)>"
    echo "MIME-Version: 1.0"
    echo 'Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name="smime.p7m"'
    echo "Content-Transfer-Encoding: base64"
    echo 'Content-Disposition: attachment; filename="smime.p7m"'
    echo ""
    cat "$TMP/encrypted.der.b64"
  } > "$OUTPUT_FILE"
else
  # raw DER:
  cp "$TMP/encrypted.der" "$OUTPUT_FILE"
fi

echo "✅ Written $OUTPUT_FILE (DER + Base64)"
