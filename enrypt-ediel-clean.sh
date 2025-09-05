#!/usr/bin/env bash
set -euo pipefail

# Encrypt an EDIFACT file into an EDIEL-compliant S/MIME email (.eml)
# Usage: ./encrypt-ediel-clean.sh input.edi output.eml

# ----------------------
# Configuration
# ----------------------
EDIFACT_FILE="${1:-./messages/edifact.edi}"
OUTPUT_FILE="${2:-./final-emails/encrypted_ediel.eml}"
RECIPIENT_CERT_DIR="./keys/recipient-cert"   # contains recipient_*.pem

# Email envelope
SENDER_EMAIL="ediel@sender.com"
RECIPIENT_EMAIL="ediel@recipient.com"

# ----------------------
# Validation
# ----------------------
[ -f "$EDIFACT_FILE" ] || { echo "EDIFACT not found: $EDIFACT_FILE" >&2; exit 1; }
mapfile -t RECIPIENT_CERTS < <(find "$RECIPIENT_CERT_DIR" -type f -name 'recipient_*.pem' | sort)
[ ${#RECIPIENT_CERTS[@]} -gt 0 ] || { echo "No recipient_*.pem in $RECIPIENT_CERT_DIR" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ----------------------
# Inner MIME entity (no MIME-Version; base64 body)
# ----------------------
cat > "$TMP/inner.mime" <<EOF
Content-Type: application/EDIFACT
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=edifact

$(base64 -w 76 "$EDIFACT_FILE")
EOF

# ----------------------
# Encrypt (3DES) to all recipient certs (multi-RecipientInfo)
# ----------------------
openssl smime -encrypt \
  -des3 \
  -in "$TMP/inner.mime" \
  -out "$TMP/smime.p7m" \
  -outform SMIME \
  "${RECIPIENT_CERTS[@]}"

# ----------------------
# Build .eml
# ----------------------
UNB_LINE=$(grep "^UNB.*'" "$EDIFACT_FILE" | head -1 || echo "UNB+UNKNOWN'")
MSG_TYPE="PRODAT"

{
  echo "From: <$SENDER_EMAIL>"
  echo "To: <$RECIPIENT_EMAIL>"
  echo "Subject: $MSG_TYPE $UNB_LINE"
  echo "Date: $(date -R)"
  echo "Message-ID: <$(date +%s).$$@$(hostname)>"
  echo "MIME-Version: 1.0"
  echo 'Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name="smime.p7m"'
  echo 'Content-Transfer-Encoding: base64'
  echo 'Content-Disposition: attachment; filename="smime.p7m"'
  echo
  # append the S/MIME body (just the base64 payload from p7m)
  sed '1,/^$/d' "$TMP/smime.p7m"
} > "$OUTPUT_FILE"

echo "Wrote: $OUTPUT_FILE"
