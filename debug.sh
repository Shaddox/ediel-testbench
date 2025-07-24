#!/usr/bin/env bash
set -euo pipefail

# Create directories
mkdir -p base-message wrapped-message signed-message encrypted-output final-emails debug

echo "🔍 DEBUGGING S/MIME PROCESS"
echo "=========================="

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

echo "✓ Step 1: EDIFACT message created"

# Step 2: MIME wrap the EDIFACT
cat > wrapped-message/mime_wrapped.txt << EOF
Content-Type: application/EDIFACT
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="edifact"

$(base64 -w 76 base-message/edifact_message.edi)
EOF

echo "✓ Step 2: MIME wrapped"

# DEBUG: Check certificate validity
echo ""
echo "🔍 CERTIFICATE VALIDATION:"
echo "Our certificate:"
if openssl x509 -in keys/our_cert.pem -text -noout > debug/our_cert_info.txt 2>&1; then
    echo "✓ Our certificate is valid"
    grep "Subject:" debug/our_cert_info.txt
else
    echo "❌ Our certificate is invalid!"
    exit 1
fi

echo ""
echo "Recipient certificate:"
if openssl x509 -in keys/recipient_cert.pem -text -noout > debug/recipient_cert_info.txt 2>&1; then
    echo "✓ Recipient certificate is valid"
    grep "Subject:" debug/recipient_cert_info.txt
else
    echo "❌ Recipient certificate is invalid!"
    exit 1
fi

# Step 3: Test signing only first
echo ""
echo "🔍 TESTING SIGNING ONLY:"
if openssl smime -sign -nodetach \
    -in wrapped-message/mime_wrapped.txt \
    -signer keys/our_cert.pem \
    -inkey keys/our_key.pem \
    -out signed-message/signed_only.smime \
    -outform SMIME 2>debug/sign_errors.txt; then
    echo "✓ Signing successful"
else
    echo "❌ Signing failed!"
    cat debug/sign_errors.txt
    exit 1
fi

# Test if we can verify our own signature
echo "Testing signature verification..."
if openssl smime -verify \
    -in signed-message/signed_only.smime \
    -CAfile keys/our_cert.pem \
    -out debug/verified_content.txt 2>debug/verify_errors.txt; then
    echo "✓ Signature verification successful"
else
    echo "❌ Signature verification failed!"
    cat debug/verify_errors.txt
fi

# Step 4: Test encryption only (skip signing for now)
echo ""
echo "🔍 TESTING ENCRYPTION ONLY (no signing):"
if openssl smime -encrypt \
    -in wrapped-message/mime_wrapped.txt \
    -out encrypted-output/encrypt_only.smime \
    -outform SMIME \
    -des3 \
    keys/recipient_cert.pem 2>debug/encrypt_errors.txt; then
    echo "✓ Encryption successful"
else
    echo "❌ Encryption failed!"
    cat debug/encrypt_errors.txt
    exit 1
fi

# Test if we can decrypt
echo "Testing decryption..."
if openssl smime -decrypt \
    -in encrypted-output/encrypt_only.smime \
    -inkey keys/recipient_key.pem \
    -out debug/decrypted_content.txt 2>debug/decrypt_errors.txt; then
    echo "✓ Decryption successful!"
    echo "Decrypted content matches original:"
    if diff wrapped-message/mime_wrapped.txt debug/decrypted_content.txt; then
        echo "✓ Content matches perfectly"
    else
        echo "⚠️  Content differs"
    fi
else
    echo "❌ Decryption failed!"
    cat debug/decrypt_errors.txt
fi

# Step 5: Now try sign + encrypt
echo ""
echo "🔍 TESTING SIGN + ENCRYPT:"
if openssl smime -encrypt \
    -in signed-message/signed_only.smime \
    -out encrypted-output/signed_and_encrypted.smime \
    -outform SMIME \
    -des3 \
    keys/recipient_cert.pem 2>debug/sign_encrypt_errors.txt; then
    echo "✓ Sign + Encrypt successful"
else
    echo "❌ Sign + Encrypt failed!"
    cat debug/sign_encrypt_errors.txt
    exit 1
fi

# Test decryption of signed+encrypted
echo "Testing decryption of signed+encrypted message..."
if openssl smime -decrypt \
    -in encrypted-output/signed_and_encrypted.smime \
    -inkey keys/recipient_key.pem \
    -out debug/decrypted_signed.smime 2>debug/decrypt_signed_errors.txt; then
    echo "✓ Decryption of signed+encrypted successful!"

    # Now verify the signature
    echo "Verifying signature from decrypted content..."
    if openssl smime -verify \
        -in debug/decrypted_signed.smime \
        -CAfile keys/our_cert.pem \
        -out debug/final_verified_content.txt 2>debug/verify_final_errors.txt; then
        echo "✓ Signature verification successful!"
        echo "Final content matches original:"
        if diff wrapped-message/mime_wrapped.txt debug/final_verified_content.txt; then
            echo "✅ COMPLETE SUCCESS - Sign+Encrypt+Decrypt+Verify all working!"
        else
            echo "⚠️  Final content differs from original"
        fi
    else
        echo "❌ Final signature verification failed!"
        cat debug/verify_final_errors.txt
    fi
else
    echo "❌ Decryption of signed+encrypted failed!"
    cat debug/decrypt_signed_errors.txt
fi

# Step 6: Show what the working encrypted message looks like
echo ""
echo "🔍 FORMAT ANALYSIS:"
echo "Working encrypted message headers:"
head -10 encrypted-output/signed_and_encrypted.smime

echo ""
echo "Content after sed extraction:"
sed '1,/^$/d' encrypted-output/signed_and_encrypted.smime | head -5

# Step 7: Create final email using the working format
echo ""
echo "🔍 CREATING FINAL EMAIL:"
{
  echo "From: \"Our Company\" <ediel@ourcompany.se>"
  echo "To: \"Utility Contact\" <ediel@recipient-utility.se>"
  echo "Subject: PRODAT UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'"
  echo "Date: $(date -R)"
  echo "Message-ID: <$(date +%s).$(shuf -i 1000-9999 -n 1)@ourcompany.se>"
  echo "MIME-Version: 1.0"

  # Extract S/MIME payload (skip headers, keep content)
  sed '1,/^$/d' encrypted-output/signed_and_encrypted.smime

} > final-emails/final_email.eml

echo "✅ Final email created: final-emails/final_email.eml"

echo ""
echo "DEBUG FILES CREATED:"
echo "  debug/our_cert_info.txt - Your certificate details"
echo "  debug/recipient_cert_info.txt - Recipient certificate details"
echo "  debug/verified_content.txt - Content after signature verification"
echo "  debug/decrypted_content.txt - Content after decryption"
echo "  debug/final_verified_content.txt - Final verified content"
echo "  debug/*_errors.txt - Error logs for each step"