encrypt-binary-mime-body : 

produces a smime email as an encrypted binary

Sample Usage for encryption : 

```shell
./encrypt-ediel-clean.sh INPUT.edi OUTPUT.eml
```
Or, for more verbose output: 

```shell
./fixed-encrypt-nosign.sh INPUT.edi OUTPUT.eml
```



Sample Usage for decryption

```shell
./decrypt-received-message.sh INPUT.eml OUTPUT.edi
```

Or for more debugging purposes 

```shell
./debug-decrypt.sh INPUT.eml OUTPUT.edi
```