#!/usr/bin/env bash
set -euo pipefail

# ============================================
# CONFIGURATION
# ============================================

# Input/Output files
EDIFACT_FILE="${1:-edifact_message.edi}"    # EDIFACT input file
OUTPUT_FILE="${2:-encrypted_ediel.eml}"     # Output email or S/MIME file

# Directories and certificates
SENDER_KEY="./keys/our_key.pem"
SENDER_CERT="./keys/our_cert.pem"
RECIPIENT_CERT_DIR="./keys"         # Directory containing all recipient_*.pem files

# Email configuration
CREATE_EMAIL="yes"  # "no" for raw S/MIME only
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

# Check sender key/cert
for f in "$SENDER_KEY" "$SENDER_CERT"; do
    if [ ! -f "$f" ]; then
        echo "❌ Error: Missing sender file: $f"
        exit 1
    fi
done

# Find recipient certs
mapfile -t all_recipient_certs < <(find "$RECIPIENT_CERT_DIR" -type f -name "recipient_*.pem")
if [ ${#all_recipient_certs[@]} -eq 0 ]; then
    echo "❌ Error: No recipient_*.pem certificates in $RECIPIENT_CERT_DIR"
    exit 1
fi

# Prepare temp
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Validate & CRL-check recipients
valid_recipients=()
echo "🔍 Validating recipient certificates..."
for cert in "${all_recipient_certs[@]}"; do
    echo "  - $cert"
    # Ensure within validity
    if ! openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then
        echo "    ⚠️  Expired or not yet valid, skipping"
        continue
    fi
    # Extract CRL DP
    crl_dp=$(openssl x509 -in "$cert" -noout -text \
        | awk '/CRL Distribution Points/{getline; print}' \
        | sed -e 's/ *URI://')
    if [[ -n "$crl_dp" ]]; then
        crl_file="$TEMP_DIR/$(basename "$cert" .pem).crl"
        echo "    ↳ Fetching CRL from $crl_dp"
        if wget -q -O "$crl_file" "$crl_dp"; then
            if ! openssl verify -crl_check -CRLfile "$crl_file" "$cert" >/dev/null 2>&1; then
                echo "    ❌ Revoked, skipping"
                continue
            fi
        else
            echo "    ⚠️  Could not download CRL, including cert without revocation check"
        fi
    else
        echo "    ⚠️  No CRL DP, including cert without revocation check"
    fi
    valid_recipients+=("$cert")
done

if [ ${#valid_recipients[@]} -eq 0 ]; then
    echo "❌ Error: No valid recipient certificates after checks"
    exit 1
fi

echo "✅ Found ${#valid_recipients[@]} valid recipient cert(s)"

# ============================================
# ENCRYPTION PROCESS
# ============================================

echo "🔐 Encrypting EDIFACT message..."
# Step 1: MIME wrap
cat > "$TEMP_DIR/mime_wrapped.txt" << EOF
Content-Type: application/EDIFACT
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="edifact"

$(base64 -w 76 "$EDIFACT_FILE")
EOF

# Step 2: Sign
openssl smime -sign -nodetach \
    -in "$TEMP_DIR/mime_wrapped.txt" \
    -signer "$SENDER_CERT" \
    -inkey "$SENDER_KEY" \
    -out "$TEMP_DIR/signed.smime" \
    -outform SMIME

# Step 3: Encrypt to all valid recipients
openssl smime -encrypt \
    -des3 \
    -in "$TEMP_DIR/signed.smime" \
    -out "$TEMP_DIR/encrypted.smime" \
    -outform SMIME \
    "${valid_recipients[@]}"

# Step 4: Build output
if [ "$CREATE_EMAIL" = "yes" ]; then
    echo "📧 Creating email format..."
    UNB_LINE=$(grep "^UNB" "$EDIFACT_FILE" || echo "UNB+UNKNOWN")
    {
        echo "From: <$SENDER_EMAIL>"
        echo "To: <$RECIPIENT_EMAIL>"
        echo "Subject: PRODAT $UNB_LINE"
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
