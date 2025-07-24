#!/bin/bash

set -e

# Step 1: Create EDIFACT message
cat > ./base-message/edifact_message.txt << 'EOF'
UNA:+.? '
UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'
UNH+1+PRODAT:E2SE5A:UN:EDIEL2'
BGM+Z03+MSG001+9'
DTM+137:20220101:102'
UNT+10+1'
UNZ+1+MSG001'
EOF

# Step 2: Create MIME wrapper for EDIFACT (section 6.4.2)
cat > ./wrapped-message/mime_wrapped.txt << EOF
Content-Type: application/EDIFACT
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="edifact"

$(base64 -w 76 ./base-message/edifact_message.txt)
EOF

# Step 3: SIGN (optional, recommended for EDIEL)
openssl smime -sign -nodetach \
    -in ./wrapped-message/mime_wrapped.txt \
    -signer ./keys/our_cert.pem \
    -inkey ./keys/our_key.pem \
    -out ./signed-message/signed_mime.txt \
    -outform SMIME

# Step 4: ENCRYPT (with recipient's cert)
openssl smime -encrypt \
    -in ./signed-message/signed_mime.txt \
    -out ./encrypted-output/encrypted.p7m \
    -outform SMIME \
    -des3 \
    ./keys/recipient_cert.pem

# Step 5: Create final S/MIME email format
SMIME_BASE64=$(base64 -w 76 ./encrypted-output/encrypted.p7m)

cat > ./final-emails/final_email_der_smime-signed.eml << EOF
From: "Our Company" <ediel@ourcompany.se>
To: "Utility Contact" <ediel@recipient-utility.se>
Subject: PRODAT UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'
Date: $(date -R)
MIME-Version: 1.0
Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name="smime.p7m"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="smime.p7m"

$SMIME_BASE64
EOF

echo "Email ready: ./final-emails/final_email_der_smime-signed.eml"

