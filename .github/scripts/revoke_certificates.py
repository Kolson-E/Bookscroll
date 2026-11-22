"""Revokes the Apple Development certificates that Xcode made during this CI run.

Xcode makes a new development certificate on each fresh CI machine to sign the archive;
the upload itself uses Apple's cloud-managed distribution certificate. Revoking the
run's development certificate keeps them from piling up in the account.

Usage: revoke_certificates.py SERIAL [SERIAL ...]
Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8 file).
"""
import json
import os
import sys
import time
import urllib.request

import jwt  # PyJWT, with the cryptography package for ES256

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    with open(os.environ["ASC_KEY_PATH"], encoding="utf-8") as handle:
        key = handle.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, url, bearer):
    request = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {bearer}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        return json.loads(body) if body else None


def normal(serial):
    return serial.strip().upper().lstrip("0")


def main(serials):
    wanted = {normal(s) for s in serials if s.strip()}
    if not wanted:
        print("No development certificate was made in this run.")
        return
    bearer = token()
    found = call("GET", f"{API}/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200", bearer)
    for certificate in found.get("data", []):
        serial = normal(certificate["attributes"].get("serialNumber", ""))
        if serial in wanted:
            call("DELETE", f"{API}/certificates/{certificate['id']}", bearer)
            print(f"Revoked development certificate {serial} made by this run.")
            wanted.discard(serial)
    for serial in wanted:
        print(f"Development certificate {serial} was not found in the account; nothing to revoke.")


if __name__ == "__main__":
    main(sys.argv[1:])
