#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mmlu v2/user/login 实登脚本（纯标准库 + openssl，沙箱无 pycryptodome）。

用法:
    python3 tools/live_login.py <country_codes> <phone> <password> [api_base]

依据 docs/PROTOCOL.md:
  - 请求头: platform=Android, version=1.5.20, payload=<10位nonce>, ebody=<AES-CBC>
  - ebody key = BigInteger(1, MD5(Base64decode(secureKey))).toString(16)  (ASCII 32B -> AES-256)
  - ebody iv  = G2(nonce) ; 明文 = {"path":..,"payload":G2(nonce)}
  - 响应: 当 X-App-Name==app 时, key=md5hexZp(apiKey), iv=G2(X-Response-Length)
"""
import base64
import hashlib
import json
import subprocess
import sys
import urllib.request

SECURE_KEY = "OlFXpWEoON2n+EuUuvDOod5lauDh98GLYmCsvBgMwts="
API_KEY = "6e561ccd4aade2fed458d4da61e76770"
LOGIN_PATH = "v2/user/login"
PLATFORM = "Android"
VERSION = "1.5.20"
DEFAULT_API = "https://api1.mmlu.services"


def md5hex_zp(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()  # 32 位补零小写


def g2(s: str) -> str:
    return md5hex_zp(s)[8:24]


def bigint_hex(b: bytes) -> str:
    return format(int.from_bytes(b, "big"), "x")  # 不补零、小写


def _openssl(args, data: bytes) -> bytes:
    p = subprocess.run(["openssl", "enc"] + args + ["-nosalt"],
                       input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode())
    return p.stdout


def aes_cbc_encrypt(key_ascii: bytes, iv_ascii: bytes, plain: bytes) -> bytes:
    return _openssl(["-aes-256-cbc", "-K", key_ascii.hex(), "-iv", iv_ascii.hex()], plain)


def aes_cbc_decrypt(key_ascii: bytes, iv_ascii: bytes, ct: bytes) -> bytes:
    return _openssl(["-d", "-aes-256-cbc", "-K", key_ascii.hex(), "-iv", iv_ascii.hex()], ct)


def new_nonce() -> str:
    import random
    return str(random.randint(1000000000, 9999999999))


def build_ebody(nonce: str) -> str:
    key = bigint_hex(hashlib.md5(base64.b64decode(SECURE_KEY)).digest()).encode("ascii")
    iv = g2(nonce).encode("ascii")
    plain = json.dumps({"path": LOGIN_PATH, "payload": g2(nonce)},
                       separators=(",", ":")).encode("utf-8")
    return base64.b64encode(aes_cbc_encrypt(key, iv, plain)).decode("ascii")


def decrypt_response(body: bytes, xlen: str) -> str:
    key = md5hex_zp(API_KEY).encode("ascii")
    iv = g2(xlen).encode("ascii")
    return aes_cbc_decrypt(key, iv, base64.b64decode(body)).decode("utf-8", "replace")


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(2)
    cc, phone, pwd = sys.argv[1], sys.argv[2], sys.argv[3]
    api = (sys.argv[4] if len(sys.argv) > 4 else DEFAULT_API).rstrip("/")
    # 登录前 App 无 token，但仍带 @Header("Authorization")（值为空串）。
    token = sys.argv[5] if len(sys.argv) > 5 else ""

    nonce = new_nonce()
    ebody = build_ebody(nonce)
    body = json.dumps({
        "country_codes": cc, "phone": phone, "password": pwd, "platform": 2,
    }, separators=(",", ":")).encode("utf-8")

    url = f"{api}/{LOGIN_PATH}"
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Content-Type": "application/json",
        "platform": PLATFORM,
        "version": VERSION,
        "payload": nonce,
        "ebody": ebody,
        "Authorization": token,
    })
    print(f"POST {url}")
    print(f"  payload={nonce}")
    print(f"  ebody  ={ebody}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            xname = r.headers.get("X-App-Name")
            xlen = r.headers.get("X-Response-Length")
            status = r.status
    except urllib.error.HTTPError as e:
        raw = e.read()
        xname = e.headers.get("X-App-Name")
        xlen = e.headers.get("X-Response-Length")
        status = e.code

    print(f"HTTP {status}  X-App-Name={xname}  X-Response-Length={xlen}")
    print(f"  raw({len(raw)}B)={raw[:200]!r}")
    if xname == "app" and xlen:
        plain = decrypt_response(raw, xlen)
        print("  decrypted:", plain)
        try:
            obj = json.loads(plain)
            print("  token =", obj.get("token"))
            print("  userId=", obj.get("userId"))
        except Exception:
            pass


if __name__ == "__main__":
    main()
