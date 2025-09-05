encrypt-binary-mime-body : 

produces a smime email as an encrypted binary

Sample Usage for encryption : 

```shell
./fixed-encrypt-nosign.sh INPUT.edi OUTPUT.eml
./encrypt-ediel-clean.sh INPUT.edi OUTPUT.eml
```

Sample Usage for decryption

```shell
./decrypt-received-message.sh INPUT.eml OUTPUT.edi
```