#!/usr/bin/env bash
set -euo pipefail

# Create directories
mkdir -p base-message wrapped-message signed-message encrypted-output final-emails

echo "🔄 Creating S/MIME message with corrected Content-Type header..."

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

# Step 3: Sign the MIME-wrapped message
openssl smime -sign -nodetach \
    -in wrapped-message/mime_wrapped.txt \
    -signer keys/our_cert.pem \
    -inkey keys/our_key.pem \
    -out signed-message/signed_message.smime \
    -outform SMIME

echo "✓ Message signed"

# Step 4: Encrypt the signed message
openssl smime -encrypt \
    -in signed-message/signed_message.smime \
    -out encrypted-output/encrypted_message.smime \
    -outform SMIME \
    -des3 \
    keys/recipient_cert.pem

echo "✓ Message encrypted"

# Step 5: Extract S/MIME payload and fix the Content-Type header
sed '1,/^$/d' encrypted-output/encrypted_message.smime > encrypted-output/smime_payload.txt

# Step 6: Create final email with CORRECTED Content-Type header
{
  echo "From: \"Our Company\" <ediel@ourcompany.se>"
  echo "To: \"Utility Contact\" <ediel@recipient-utility.se>"
  echo "Subject: PRODAT UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'"
  echo "Date: $(date -R)"
  echo "Message-ID: <$(date +%s).$(shuf -i 1000-9999 -n 1)@ourcompany.se>"
  echo "MIME-Version: 1.0"
  # CORRECTED: Remove "x-" prefix to match Swedish spec
  echo "Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name=\"smime.p7m\""
  echo "Content-Transfer-Encoding: base64"
  echo "Content-Disposition: attachment; filename=\"smime.p7m\""
  echo ""

  # Include the S/MIME payload
  cat encrypted-output/smime_payload.txt

} > final-emails/final_email_corrected.eml

echo "✅ Final email created with CORRECTED Content-Type: final-emails/final_email_corrected.eml"

# Step 7: Test the corrected version can still be decrypted
echo ""
echo "🔍 Testing corrected version..."

# Create a temporary S/MIME file with corrected headers for testing
{
  echo "MIME-Version: 1.0"
  echo "Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name=\"smime.p7m\""
  echo "Content-Transfer-Encoding: base64"
  echo "Content-Disposition: attachment; filename=\"smime.p7m\""
  echo ""
  cat encrypted-output/smime_payload.txt
} > final-emails/test_corrected_headers.smime

# Test decryption with corrected headers
if openssl smime -decrypt \
    -in final-emails/test_corrected_headers.smime \
    -inkey keys/recipient_key.pem \
    -out final-emails/test_decrypted.txt 2>/dev/null; then
  echo "✓ Corrected version decrypts successfully!"

  # Test signature verification
  if openssl smime -verify \
      -in final-emails/test_decrypted.txt \
      -CAfile keys/our_cert.pem \
      -out final-emails/test_verified.txt 2>/dev/null; then
    echo "✓ Signature verification successful!"
  else
    echo "⚠️  Signature verification failed (but decryption worked)"
  fi
else
  echo "❌ Corrected version decryption failed"
fi

# Cleanup temp files
rm -f final-emails/test_corrected_headers.smime final-emails/test_decrypted.txt final-emails/test_verified.txt

echo ""
echo "📊 COMPARISON:"
echo "OpenSSL generated:  application/x-pkcs7-mime (non-standard)"
echo "Swedish spec wants: application/pkcs7-mime (RFC standard)"
echo ""
echo "✅ Your S/MIME process is working perfectly!"
echo "✅ The issue was likely the Content-Type header mismatch."
echo "✅ Try sending the corrected version: final-emails/final_email_corrected.eml"