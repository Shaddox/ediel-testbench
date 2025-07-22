#!/usr/bin/env bash
set -euo pipefail

# directories
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

# Step 2: SIGN the .edi (optional but recommended)
openssl smime -sign -nodetach \
    -in base-message/edifact_message.edi \
    -signer keys/our_cert.pem \
    -inkey keys/our_key.pem \
    -out signed-message/signed_message.pem \
    -outform SMIME

# Step 3: ENCRYPT the signed message for the recipient
openssl smime -encrypt \
    -in signed-message/signed_message.pem \
    -out encrypted-output/encrypted_message.smime \
    -outform SMIME \
    -des3 \
    keys/recipient_cert.pem

# Step 4: Assemble final .eml
#  - Prepend your SMTP headers
#  - Skip the initial MIME-Version header from the S/MIME blob to avoid duplicates
{
  echo "From: \"Our Company\" <ediel@ourcompany.se>"
  echo "To:   \"Utility Contact\" <ediel@recipient-utility.se>"
  echo "Subject: PRODAT UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'"
  echo "Date: $(date -R)"
  echo "MIME-Version: 1.0"
  # Now inject the S/MIME payload (drop everything up through the first blank line)
  sed '1,/^$/d' encrypted-output/encrypted_message.smime
} > final-emails/final_email_smime.eml

echo "✅ Final email written to final-emails/final_email_smime.eml"
