#!/usr/bin/env python3
import os, base64
from ldap3 import Server, Connection, ALL, SUBTREE, ANONYMOUS

# ─── CONFIG ────────────────────────────────────────────
LDAP_URI      = 'ldap://sodir01.expisoft.se:389'
BASE_DN       = 'c=se'
SEARCH_FILTER = '(mail=91100@ediel.se)'
ATTR          = 'userCertificate;binary'
OUT_DIR       = './certs'
# If you need a bind DN/password, set these; otherwise leave as None
BIND_DN       = None
BIND_PW       = None
# ───────────────────────────────────────────────────────

def sanitize_dn(dn):
    return dn.replace('=', '_').replace(',', '_').replace(' ', '')

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    server = Server(LDAP_URI, get_info=ALL)
    if BIND_DN:
        # simple bind with credentials
        conn = Connection(server, user=BIND_DN, password=BIND_PW, auto_bind=True)
    else:
        # anonymous bind
        conn = Connection(server, authentication=ANONYMOUS, auto_bind=True)

    conn.search(
        search_base=BASE_DN,
        search_filter=SEARCH_FILTER,
        search_scope=SUBTREE,
        attributes=[ATTR]
    )

    count = 0
    for entry in conn.entries:
        dn = sanitize_dn(str(entry.entry_dn))
        for idx, b64 in enumerate(entry[ATTR].values, 1):
            der = base64.b64decode(b64)
            fname = f"{dn}_{idx}.der"
            path = os.path.join(OUT_DIR, fname)
            with open(path, "wb") as f:
                f.write(der)
            print(f"Wrote {path}")
            count += 1

    print(f"\nTotal certificates written: {count}")

if __name__ == '__main__':
    main()
