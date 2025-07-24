#!/usr/bin/env bash
set -euo pipefail

# ============================================
# CONFIGURATION
# ============================================

# Input/Output files
EDIFACT_FILE="${1:-edifact_message.edi}"  # First argument or default
OUTPUT_FILE="${2:-encrypted_ediel.eml}"   # Second argument or default

# Directory containing recipient certificates
RECIPIENT_CERT_DIR="./keys/recipient"

# Email configuration (optional, for full email format)
CREATE_EMAIL="yes"  # Set to "no" for S/MIME only
SENDER_EMAIL="ediel@sender.com"
RECIPIENT_EMAIL="ediel@recipient.com"

# ============================================
# VALIDATION & CERTIFICATE PREPARATION
# ============================================

if [ ! -f "$EDIFACT_FILE" ]; then
    echo "❌ Error: EDIFACT file not found: $EDIFACT_FILE"
    echo "Usage: $0 [edifact_file] [output_file]"
    exit 1
fi

# Gather recipient certs
mapfile -t all_certs < <(find "$RECIPIENT_CERT_DIR" -type f -name "recipient_*.pem")
if [ ${#all_certs[@]} -eq 0 ]; then
    echo "❌ Error: No recipient certificates found in $RECIPIENT_CERT_DIR"
    exit 1
fi

# Create temp directory for CRLs and intermediate files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

valid_certs=()
echo "🔍 Validating recipient certificates (signature & CRL)..."
for cert in "${all_certs[@]}"; do
    echo "  - Checking $cert"
    # Check certificate validity period
    if ! openssl x509 -in "$cert" -noout -checkend 0 > /dev/null 2>&1; then
        echo "    ⚠️  Certificate expired or not yet valid: $cert"
        continue
    fi
    # Extract CRL Distribution Point URL
    crl_url=$(openssl x509 -in "$cert" -noout -text \
        | awk '/CRL Distribution Points/{getline; print}' \
        | sed -e 's/ *URI://')
    if [[ -n "$crl_url" ]]; then
        crl_file="$TEMP_DIR/$(basename "$cert" .pem).crl"
        echo "    ↳ Downloading CRL from $crl_url"
        if ! wget -q -O "$crl_file" "$crl_url"; then
            echo "    ⚠️  Failed to download CRL, skipping CRL check for $cert"
            valid_certs+=("$cert")
            continue
        fi
        # Verify against CRL
        if ! openssl verify -crl_check -CRLfile "$crl_file" "$cert" > /dev/null 2>&1; then
            echo "    ❌ Certificate is revoked: $cert"
            continue
        fi
    else
        echo "    ⚠️  No CRL DP found, including cert without revocation check"
    fi
    valid_certs+=("$cert")
done

if [ ${#valid_certs[@]} -eq 0 ]; then
    echo "❌ Error: No valid recipient certificates available after CRL checks"
    exit 1
fi

echo "✅ Using ${#valid_certs[@]} valid certificates for encryption"

# ============================================
# ENCRYPTION PROCESS
# ============================================

echo "🔐 Encrypting EDIFACT message for Ediel..."
echo "   Input: $EDIFACT_FILE"
echo "   Output: $OUTPUT_FILE"

# Step 1: MIME wrap inner entity (no MIME-Version)
cat > "$TEMP_DIR/mime_wrapped.txt" << EOF
Content-Type: application/EDIFACT
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=edifact

$(base64 -w 76 "$EDIFACT_FILE")
EOF

# Step 2: Encrypt to all valid recipient certs
openssl smime -encrypt \
    -des3 \
    -in "$TEMP_DIR/mime_wrapped.txt" \
    -out "$TEMP_DIR/encrypted.smime" \
    -outform SMIME \
    "${valid_certs[@]}"

# Step 3: Build output
if [ "$CREATE_EMAIL" = "yes" ]; then
    echo "📧 Creating Ediel-compliant email format..."
    UNB_LINE=$(grep "^UNB.*'" "$EDIFACT_FILE" | head -1 || echo "UNB+UNKNOWN'")
    MSG_TYPE="PRODAT"
    if grep -q "UTILTS" "$EDIFACT_FILE"; then MSG_TYPE="UTILTS"; fi
    if grep -q "MSCONS" "$EDIFACT_FILE"; then MSG_TYPE="MSCONS"; fi

    {
        echo "From: <$SENDER_EMAIL>"
        echo "To: <$RECIPIENT_EMAIL>"
        echo "Subject: $MSG_TYPE $UNB_LINE"
        echo "Date: $(date -R)"
        echo "Message-ID: <$(date +%s).$(shuf -i 1000-9999 -n 1)@$(hostname)>"
        echo "MIME-Version: 1.0"
        echo "Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name=\"smime.p7m\""
        echo "Content-Transfer-Encoding: base64"
        echo "Content-Disposition: attachment; filename=\"smime.p7m\""
        echo ""
        sed '1,/^$/d' "$TEMP_DIR/encrypted.smime"
    } > "$OUTPUT_FILE"
else
    cp "$TEMP_DIR/encrypted.smime" "$OUTPUT_FILE"
fi

echo "✅ Success! Encrypted message saved to: $OUTPUT_FILE"

# Compliance summary
echo "📊 Ediel Compliance Status:"
echo "   ✅ Algorithm: 3DES-EDE3-CBC"
echo "   ✅ Encrypted to all valid recipient certificates"
echo "   ✅ Inner MIME entity as per A.3.7"
echo "   ✅ Outer S/MIME enveloped-data format"
