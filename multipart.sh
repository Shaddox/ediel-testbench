#!/usr/bin/env bash
set -euo pipefail

# This script:
# 1. Builds a PRODAT EDIFACT file
# 2. Encrypts it with S/MIME (DER output)
# 3. Wraps the encrypted blob as an attachment in a multipart/mixed email

# ---- CONFIGURATION ----
FROM_ADDR="Our Company <ediel@ourcompany.se>"
TO_ADDR="Utility Contact <ediel@recipient-utility.se>"
SUBJECT="PRODAT UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'"
CERT_RECIP="keys/recipient_cert.pem"
# ------------------------

# directories
mkdir -p base-message encrypted-output final-emails

# Step 1: Create EDIFACT PRODAT message
cat > base-message/prodat.edi << 'EOF'
UNA:+.? '
UNB+UNOC:3+12345:ZZ+67890:ZZ+220101:1200+MSG001++23-DDQ-PRODAT++1'
UNH+1+PRODAT:E2SE5A:UN:EDIEL2'
BGM+Z03+MSG001+9'
DTM+137:20220101:102'
UNT+10+1'
UNZ+1+MSG001'
EOF

# Step 2: Encrypt the EDIFACT file (DER-encoded S/MIME envelope)
openssl smime -encrypt \
  -in base-message/prodat.edi \
  -outform DER \
  -des3 \
  -out encrypted-output/prodat.p7m \
  "${CERT_RECIP}"

# Step 3: Assemble final multipart/mixed email with the encrypted attachment
BOUNDARY="====$(date +%s)===="

{
  printf '%s\n' \
    "From: ${FROM_ADDR}" \
    "To: ${TO_ADDR}" \
    "Subject: ${SUBJECT}" \
    "Date: $(date -R)" \
    "MIME-Version: 1.0" \
    "Content-Type: multipart/mixed; boundary=\"${BOUNDARY}\"" \
    "" \
    "--${BOUNDARY}" \
    "Content-Type: text/plain; charset=\"utf-8\"" \
    "Content-Transfer-Encoding: 7bit" \
    "" \
    "Please find attached the encrypted PRODAT message." \
    "" \
    "--${BOUNDARY}" \
    "Content-Type: application/pkcs7-mime; smime-type=enveloped-data; name=\"prodat.p7m\"" \
    "Content-Transfer-Encoding: base64" \
    "Content-Disposition: attachment; filename=\"prodat.p7m\"" \
    ""
  base64 -w 76 encrypted-output/prodat.p7m
  printf '\n--%s--\n' "${BOUNDARY}"
} > final-emails/final_email_multipart.eml

echo "✅ Final email ready: final-emails/final_email_multipart.eml"
