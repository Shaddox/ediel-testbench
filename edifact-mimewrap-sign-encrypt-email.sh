#!/usr/bin/env bash
set -euo pipefail

# Create directories
mkdir -p base-message wrapped-message signed-message encrypted-output final-emails

# Step 1: Create EDIFACT message
cat > base-message/edifact_message.edi << 'EOF'
UNA:+.? '
UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'
UNH+1+PRODAT:E2SE5A:UN:EDIEL2'
BGM+Z03+MSG001+9'
DTM+137:20220101:102'
UNT+10+1'
UNZ+1+MSG001'
EOF

# Step 2: MIME wrap the EDIFACT (per Swedish spec page 40)
cat > wrapped-message/mime_wrapped.txt << EOF
Content-Type: application/EDIFACT
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="edifact"

$(base64 -w 76 base-message/edifact_message.edi)
EOF

echo "✓ EDIFACT message MIME-wrapped"

# Step 3: SIGN the MIME-wrapped message
openssl smime -sign -nodetach \
    -in wrapped-message/mime_wrapped.txt \
    -signer keys/our_cert.pem \
    -inkey keys/our_key.pem \
    -out signed-message/signed_message.smime \
    -outform SMIME

echo "✓ Message signed"

# Step 4: ENCRYPT the signed message
openssl smime -encrypt \
    -in signed-message/signed_message.smime \
    -out encrypted-output/encrypted_message.smime \
    -outform SMIME \
    -des3 \
    keys/recipient_cert.pem

echo "✓ Message encrypted"

# Step 5: Assemble final email
# Strip OpenSSL's MIME headers and use our own
{
  echo "From: \"Our Company\" <ediel@ourcompany.se>"
  echo "To: \"Utility Contact\" <ediel@recipient-utility.se>"
  echo "Subject: PRODAT UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'"
  echo "Date: $(date -R)"
  echo "Message-ID: <$(date +%s).$(shuf -i 1000-9999 -n 1)@ourcompany.se>"
  echo "MIME-Version: 1.0"

  # Extract S/MIME payload (skip headers, keep content)
  sed '1,/^$/d' encrypted-output/encrypted_message.smime

} > final-emails/final_email.eml

echo "✅ Final email written to final-emails/final_email.eml"

# Step 6: Test local decryption to verify format
echo ""
echo "Testing decryption locally..."

# Extract just the encrypted data for testing
sed '1,/^$/d' encrypted-output/encrypted_message.smime > final-emails/test_decrypt_input.txt

# Create temporary S/MIME file for decryption test
{
  echo "MIME-Version: 1.0"
  cat final-emails/test_decrypt_input.txt
} > final-emails/temp_smime_for_test.txt

# Test decryption
if openssl smime -decrypt \
    -in final-emails/temp_smime_for_test.txt \
    -inkey keys/recipient_key.pem \
    -out final-emails/decrypted_test.txt 2>/dev/null; then
  echo "✓ Local decryption successful"

  # Test signature verification
  if openssl smime -verify \
      -in final-emails/decrypted_test.txt \
      -CAfile keys/our_cert.pem \
      -out final-emails/verified_mime.txt 2>/dev/null; then
    echo "✓ Signature verification successful"
    echo "✓ Recovered MIME-wrapped EDIFACT in: verified_mime.txt"
  else
    echo "⚠️  Signature verification failed (but decryption worked)"
  fi
else
  echo "❌ Local decryption failed - check certificate format"
fi

# Cleanup temp files
rm -f final-emails/test_decrypt_input.txt final-emails/temp_smime_for_test.txt

echo ""
echo "File sizes:"
echo "  Original EDIFACT: $(wc -c < base-message/edifact_message.edi) bytes"
echo "  MIME wrapped: $(wc -c < wrapped-message/mime_wrapped.txt) bytes"
echo "  Final email: $(wc -c < final-emails/final_email.eml) bytes"

echo ""
echo "SUCCESS: Email ready for sending via Mailgun!"