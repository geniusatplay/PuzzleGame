#!/usr/bin/env python3
"""Signing for one iPhone build on GitHub's Mac (Nov 27 2026). Apple's automatic signing wants a registered iPhone
for its development profile, so instead each run makes its own Apple Distribution certificate and App Store profile
with the App Store Connect API key, signs and uploads, then revokes and deletes both (builds already uploaded stay
valid). Nothing private outlives the run.
  asc_signing.py create <csr.pem> <out dir> <bundle id> <run id>   -> out/cert.cer, out/profile.mobileprovision, out/ids
  asc_signing.py cleanup <out dir>
Needs ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID in the environment."""
import base64, json, os, sys, time
import jwt, requests

BASE = "https://api.appstoreconnect.apple.com"


def headers():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                     key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    return {"Authorization": "Bearer " + tok, "Content-Type": "application/json"}


def call(method, path, body=None):
    r = requests.request(method, BASE + path, headers=headers(), data=None if body is None else json.dumps(body), timeout=60)
    if r.status_code >= 300:
        raise SystemExit("%s %s -> %d %s" % (method, path, r.status_code, r.text[:1500]))
    return r.json() if r.text else {}


def create(csr_path, out, bundle, run):
    os.makedirs(out, exist_ok=True)
    csr = open(csr_path).read()
    cert = call("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION", "csrContent": csr}}})["data"]
    open(os.path.join(out, "cert.cer"), "wb").write(base64.b64decode(cert["attributes"]["certificateContent"]))
    bid = call("GET", "/v1/bundleIds?filter[identifier]=%s" % bundle)["data"]
    bid = [b for b in bid if b["attributes"]["identifier"] == bundle][0]["id"]
    name = "Physics Chain CI %s" % run
    prof = call("POST", "/v1/profiles", {"data": {"type": "profiles", "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}},
                          "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})["data"]
    open(os.path.join(out, "profile.mobileprovision"), "wb").write(base64.b64decode(prof["attributes"]["profileContent"]))
    json.dump({"certificate": cert["id"], "profile": prof["id"], "profile_name": name, "profile_uuid": prof["attributes"]["uuid"]},
              open(os.path.join(out, "ids"), "w"))
    print("certificate", cert["id"], "profile", name, prof["attributes"]["uuid"])


def cleanup(out):
    p = os.path.join(out, "ids")
    if not os.path.exists(p):
        return
    ids = json.load(open(p))
    for kind, key in (("profiles", "profile"), ("certificates", "certificate")):
        try:
            call("DELETE", "/v1/%s/%s" % (kind, ids[key]))
            print("removed", kind, ids[key])
        except SystemExit as e:
            print("could not remove", kind, e)


if __name__ == "__main__":
    if sys.argv[1] == "create":
        create(*sys.argv[2:6])
    else:
        cleanup(sys.argv[2])
