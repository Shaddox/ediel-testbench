#!/usr/bin/env bash
set -euo pipefail

# ============================================
# CONFIGURATION
# ============================================

EDIFACT_FILE="${1:-edifact_message.edi}"       # EDIFACT input file
OUTPUT_FILE="${2:-encrypted_ediel_der.eml}"  # Output email or raw DER file

RECIPIENT_CERT_DIR="./keys/recipient"    # Directory containing recipient_*.pem certificates

CREATE_EMAIL="yes"             # Set to "no" for raw DER only
SENDER_EMAIL="ediel@sender.com"
RECIPIENT_EMAIL="ediel@recipient.com"

# ============================================
# VALIDATION & CERTIFICATE COLLECTION
# ============================================

# Check EDIFACT file
if [ ! -f "$EDIFACT_FILE" ]; then
  echo "❌ Error: EDIFACT file not found: $EDIFACT_FILE"
  exit 1
fi

# Gather recipient certs
mapfile -t RECIPIENT_CERTS < <(find "$RECIPIENT_CERT_DIR" -type f -name 'recipient_*.pem')
if [ ${#RECIPIENT_CERTS[@]} -eq 0 ]; then
  echo "❌ Error: No recipient_*.pem certificates found in $RECIPIENT_CERT_DIR"
  exit 1
fi

# Optional CRL checks (basic validity)
VALID_CERTS=()
echo "🔍 Validating recipient certificates..."
for cert in "${RECIPIENT_CERTS[@]}"; do
  echo "  - Checking $cert"
  if openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then
    VALID_CERTS+=("$cert")
  else
    echo "    ⚠️  Skipping expired/not-yet-valid: $cert"
  fi
done

if [ ${#VALID_CERTS[@]} -eq 0 ]; then
  echo "❌ Error: No valid recipient certificates available"
  exit 1
fi

echo "✅ Encrypting to ${#VALID_CERTS[@]} valid certificate(s)"

# ============================================
# WORKING DIRECTORY
# ============================================
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Step 1: MIME wrap inner entity (no MIME-Version)
cat > "$TMPDIR/mime_wrapped.txt" <<EOF
Content-Type: application/EDIFACT
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=edifact

$(base64 -w 76 "$EDIFACT_FILE")
EOF

# Step 2: Encrypt (no signing) → DER
openssl smime -encrypt \
  -des3 \
  -in "$TMPDIR/mime_wrapped.txt" \
  -out "$TMPDIR/encrypted.der" \
  -outform DER \
  "${VALID_CERTS[@]}"

# Base64-encode DER for email transport
base64 -w 76 "$TMPDIR/encrypted.der" > "$TMPDIR/encrypted.der.b64"

# ============================================
# BUILD OUTPUT
# ============================================
if [ "$CREATE_EMAIL" = "yes" ]; then
  UNB_LINE=$(grep '^UNB' "$EDIFACT_FILE" | head -1 || echo 'UNB+UNKNOWN')
  {
    echo "From: <$SENDER_EMAIL>"
    echo "To: <$RECIPIENT_EMAIL>"
    echo "Subject: PRODAT $UNB_LINE"
    echo "Date: $(date -R)"
    echo "Message-ID: <$(date +%s).$$@$(hostname)>"
    echo "MIME-Version: 1.0"
    echo 'Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name="smime.p7m"'
    echo "Content-Transfer-Encoding: base64"
    echo 'Content-Disposition: attachment; filename="smime.p7m"'
    echo ""
    cat "$TMPDIR/encrypted.der.b64"
  } > "$OUTPUT_FILE"
else
  cp "$TMPDIR/encrypted.der" "$OUTPUT_FILE"
fi

echo "✅ Output written to: $OUTPUT_FILE"
