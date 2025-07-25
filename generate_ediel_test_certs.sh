#!/bin/bash

set -e

# Step 1: Generate our private key and self-signed certificate
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout ./keys/our_key.pem \
    -out ./keys/our_cert.pem \
    -days 365 \
    -subj "/CN=EDIEL Sender Test/O=TestOrg/C=SE/emailAddress=sender@example.com"

echo "Generated our_key.pem and our_cert.pem"

# Step 2: Generate recipient's private key and self-signed certificate
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout ./keys/recipient_key.pem \
    -out ./keys/recipient_cert.pem \
    -days 365 \
    -subj "/CN=EDIEL Recipient Test/O=TestOrg/C=SE/emailAddress=recipient@example.com"

echo "Generated recipient_key.pem and recipient_cert.pem"

# Optional: show fingerprints for verification
echo
echo "Fingerprints:"
openssl x509 -in ./keys/our_cert.pem -noout -fingerprint
openssl x509 -in ./keys/recipient_cert.pem -noout -fingerprint

