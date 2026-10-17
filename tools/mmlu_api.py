#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mmlu 第三方客户端 API 库（纯标准库 + openssl）。

已在沙箱实测通过：
    python3 tools/mmlu_api.py smoke
    python3 tools/mmlu_api.py login 86 15152012300 1314ZLY

协议要点（见 docs/PROTOCOL.md）：
  1) 引导注册  POST v2/register      （无需 Authorization）
       body = {universal_id, platform, model, key, install_channel, install, source}
       key  = SHA-256("hcg" + universal_id + "hcg").hexdigest()
       -> {"success":{"token":<游客token>, "user_id":.., "universal_id":..}}
  2) 账号登录  POST v2/user/login    （Authorization: Bearer <游客token>）
       body = {country_codes, phone, password, platform}
       -> {"success":{"token":<账号token>, "user_id":..}}
  3) 之后所有请求  Authorization: Bearer <账号token>
  4) 响应统一信封: {"success": <data>} / 错误 {"error": {...}}
  5) 当响应头 X-App-Name=app 时响应体是 AES-CBC 密文（见 decrypt_response）
"""
import base64
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

# --- 从 APK 还原的常量 ------------------------------------------------
SECURE_KEY = "OlFXpWEoON2n+EuUuvDOod5lauDh98GLYmCsvBgMwts="
API_KEY = "6e561ccd4aade2fed458d4da61e76770"
PLATFORM = "Android"
VERSION = "1.5.20"
DEFAULT_API = "https://api1.mmlu.services"

# 播放线路 = host.txt 的 stream 数组（见 docs/PROTOCOL.md §9B.1）。
# 每项：url=API 域（拉 m3u8 用）, chain, tsurl=CDN 主机（签名 host 用）, name。
STREAM_LINES = [
    {"name": "国内线路1", "url": "https://api1.mmlu.services",
     "chain": "miOBGgHNWhpt2", "tsurl": "https://stream-encrypt1.mmlutech.xyz"},
    {"name": "国内线路2", "url": "https://api1.ook.cool",
     "chain": "miOBGgHNWhpt2", "tsurl": "https://stream-encrypt1.mmlu4.site"},
]

STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".state.json")


# --- 加密原语 ---------------------------------------------------------
def md5hex_zp(s: str) -> str:
    """MD5 补零小写 hex（EncodeUtility.f / G2 用）。"""
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def bigint_hex(b: bytes) -> str:
    """BigInteger(1, bytes).toString(16)：不补零、小写（ebody key 用）。"""
    return format(int.from_bytes(b, "big"), "x")


def g2(s: str) -> str:
    """MD5hex(s).substring(8, 24)（16 字符）。"""
    return md5hex_zp(s)[8:24]


def _openssl(args, data: bytes) -> bytes:
    p = subprocess.run(["openssl", "enc"] + args + ["-nosalt"],
                       input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError("openssl: " + p.stderr.decode("utf-8", "replace"))
    return p.stdout


def aes_cbc_encrypt(key_ascii: bytes, iv_ascii: bytes, plain: bytes) -> bytes:
    return _openssl(["-aes-256-cbc", "-K", key_ascii.hex(), "-iv", iv_ascii.hex()], plain)


def aes_cbc_decrypt(key_ascii: bytes, iv_ascii: bytes, ct: bytes) -> bytes:
    return _openssl(["-d", "-aes-256-cbc", "-K", key_ascii.hex(), "-iv", iv_ascii.hex()], ct)


def aes_cbc_decrypt128(key: bytes, iv: bytes, ct: bytes, nopad: bool = False) -> bytes:
    """HLS 分片解密：AES-128-CBC，key=key.php 的 16 字节（ASCII），iv=m3u8 的 IV。
    默认按 PKCS7 去填充（出 188 整数倍 TS）；分片损坏时可用 nopad=True 兜底。"""
    args = ["-d", "-aes-128-cbc", "-K", key.hex(), "-iv", iv.hex()]
    if nopad:
        args.append("-nopad")
    return _openssl(args, ct)


def new_nonce() -> str:
    """10 位随机 nonce（ThreadLocalRandom.nextLong(1e9, 1e10)）。"""
    return str(random.randint(1000000000, 9999999999))


def build_ebody(nonce: str, path: str) -> str:
    """构造 ebody 请求头（RequestHashBean 2 参构造）。"""
    key = bigint_hex(hashlib.md5(base64.b64decode(SECURE_KEY)).digest()).encode("ascii")
    iv = g2(nonce).encode("ascii")
    plain = json.dumps({"path": path, "payload": g2(nonce)},
                       separators=(",", ":")).encode("utf-8")
    return base64.b64encode(aes_cbc_encrypt(key, iv, plain)).decode("ascii")


def decrypt_response(body: bytes, xlen: str) -> str:
    """解密响应体（X-App-Name=app 时）。"""
    key = md5hex_zp(API_KEY).encode("ascii")
    iv = g2(xlen).encode("ascii")
    return aes_cbc_decrypt(key, iv, base64.b64decode(body)).decode("utf-8", "replace")


# --- HTTP -------------------------------------------------------------
class MmluError(Exception):
    def __init__(self, status, payload):
        super().__init__(f"HTTP {status}: {payload}")
        self.status = status
        self.payload = payload


def call(path, body=None, token=None, api=DEFAULT_API, method=None, raw=False, sign=True):
    """发一个请求。返回 (status, data)。data 已解密/解析，异常时抛 MmluError。

    sign=False 时不发 payload/ebody/Content-Type（用于流媒体等最小头请求，
    实测 curl 最小头即可取 m3u8）。
    """
    api = api.rstrip("/")
    headers = {"platform": PLATFORM, "version": VERSION, "User-Agent": "okhttp/4.9.0"}
    if sign:
        nonce = new_nonce()
        headers["Content-Type"] = "application/json"
        headers["payload"] = nonce
        headers["ebody"] = build_ebody(nonce, path)
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None
    if body is not None:
        data = json.dumps(body, separators=(",", ":")).encode("utf-8")
        method = method or "POST"
    req = urllib.request.Request(f"{api}/{path.lstrip('/')}",
                                 data=data, method=method or "GET", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            status, hdr, rawbody = resp.status, resp.headers, resp.read()
    except urllib.error.HTTPError as e:
        status, hdr, rawbody = e.code, e.headers, e.read()

    text = None
    if hdr.get("X-App-Name") == "app" and hdr.get("X-Response-Length"):
        text = decrypt_response(rawbody, hdr["X-Response-Length"])
    else:
        text = rawbody.decode("utf-8", "replace")
    if raw:
        return status, text
    try:
        obj = json.loads(text)
    except Exception:
        obj = {"_raw": text}
    if status >= 400 or "error" in obj:
        raise MmluError(status, obj)
    return status, obj.get("success", obj)


# --- 流程 -------------------------------------------------------------
def make_device():
    dev = str(uuid.uuid4())
    key = hashlib.sha256(("hcg" + dev + "hcg").encode("utf-8")).hexdigest()
    return dev, key


def register(api=DEFAULT_API):
    """设备引导注册，返回游客 token。"""
    dev, key = make_device()
    _, data = call("v2/register", {
        "universal_id": dev,
        "platform": 2,
        "model": "Xiaomi_Redmi Note 12",
        "key": key,
        "install_channel": "com.android.vending",
        "install": "",
        "source": "",
    }, api=api)
    return data["token"], data


def login(country_codes, phone, password, api=DEFAULT_API):
    """注册游客 token -> 账号登录，返回账号 token。"""
    guest, _ = register(api=api)
    _, data = call("v2/user/login", {
        "country_codes": country_codes,
        "phone": phone,
        "password": password,
        "platform": 2,
    }, token=guest, api=api)
    return data["token"], data


def call_retry(path, tries=6, **kw):
    """带退避重试的 call（沙箱网络抖动时用）。"""
    import time
    last = None
    for i in range(tries):
        try:
            return call(path, **kw)
        except MmluError:
            raise
        except Exception as e:  # 连接被重置等
            last = e
            time.sleep(1.5 + i)
    raise last


def animat_media(animate_id, token, api=DEFAULT_API, quality="720", version=3):
    """取动漫详情里的媒体相对路径。

    version=3 → /v3/nsanimat/media/<q>/<avkey>.m3u8，分片 = 无签名 na.mmlu1.site（可直下）；
    version=2 → /v1/animat/media/<q>/<avkey>.m3u8，分片 = 签名 URL（易 403）。
    默认用 v3（见 docs/PROTOCOL.md §9B）。
    """
    ep = (f"v3/nsanimat/internal/{animate_id}" if version == 3
          else f"v2/combine/animat/internal/{animate_id}")
    _, data = call_retry(ep, token=token, api=api)
    summary = data.get("summary") or data.get("directory") or []
    if isinstance(summary, dict):
        summary = [summary]
    media = summary[0]["media"]
    return media[quality]


def parse_m3u8(text):
    """解析 HLS 清单，返回 (key_uri, iv, [seg_url...])。"""
    key_uri = iv = None
    segs = []
    for ln in text.splitlines():
        ln = ln.strip()
        if ln.startswith("#EXT-X-KEY"):
            m = re.search(r'URI="([^"]+)"', ln)
            key_uri = m.group(1) if m else None
            m2 = re.search(r"IV=0x([0-9A-Fa-f]+)", ln)
            iv = bytes.fromhex(m2.group(1)) if m2 else None
        elif ln.startswith("http"):
            segs.append(ln)
        elif ln and not ln.startswith("#") and ".ts" in ln:
            segs.append("https://" + ln)
    return key_uri, iv, segs


def _get_bytes(url, tries=15):
    """裸 GET（分片/key 免鉴权），带重试（沙箱偶发 Connection reset）。"""
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "okhttp/4.9.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                b = r.read()
            if b:
                return b
            last = RuntimeError("empty body")
        except Exception as e:
            last = e
        time.sleep(0.6 + min(i, 8) * 0.5)
    raise last


def download_hls(media_path, out_path, token, line=None, api=None, quality=None, workers=6):
    """整片下载：拉 m3u8 → 并行下分片 → AES-128-CBC 解密 → 顺序合并落盘。

    返回 (总字节数, 分片数)。分片落在 <media_path> 对应的 na.mmlu1.site（无签名）。
    """
    import concurrent.futures as cf
    text = get_m3u8(media_path, token, line=line, api=api)
    key_uri, iv, segs = parse_m3u8(text)
    if not segs:
        raise RuntimeError("m3u8 无分片")
    key = _get_bytes(key_uri)[:16]

    def fetch(iu):
        i, u = iu
        ct = _get_bytes(u)
        try:
            pt = aes_cbc_decrypt128(key, iv, ct)
        except Exception:
            pt = aes_cbc_decrypt128(key, iv, ct, nopad=True)
        return i, pt

    parts = [None] * len(segs)
    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        for i, pt in ex.map(fetch, list(enumerate(segs))):
            parts[i] = pt
    data = b"".join(parts)
    with open(out_path, "wb") as f:
        f.write(data)
    return len(data), len(segs)


def get_m3u8(media_path, token, line=None, api=None):
    """拉取并解密 HLS 播放清单（返回明文 m3u8 文本）。

    media_path 形如 /v1/animat/media/720/QNB-M018.m3u8。
    line 为 STREAM_LINES 的一项；默认用 host.txt 的国内线路1。
    服务端返回 text/plain + X-App-Name:app，复用标准响应解密。
    """
    line = line or STREAM_LINES[0]
    host = line["tsurl"].split("://", 1)[-1].rstrip("/")
    url = f"{media_path}?host={host}&chain={line['chain']}"
    _, text = call_retry(url, token=token, api=api or line["url"], raw=True, sign=False)
    return text


def save_state(d):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


def load_state():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


# --- CLI --------------------------------------------------------------
def _smoke(api):
    print("== register (guest) ==")
    guest, rd = register(api=api)
    print("   guest token:", guest)
    print("  ", rd)

    print("\n== smoke GET (guest) ==")
    for path in ["v2/common/appinfo", "v2/comic/banner"]:
        try:
            st, data = call(path, token=guest, api=api)
            s = json.dumps(data, ensure_ascii=False)
            print(f"   [{path}] HTTP {st}  {s[:160]}")
        except MmluError as e:
            # 注意：内容类接口对「游客 token」可能返回 495 {"error":{"msg":"unidentify"}}，
            # 需用账号 token（见 login）。
            print(f"   [{path}] HTTP {e.status}  {e.payload}")

    print("\n== smoke GET (account, 若有 .state.json) ==")
    acct = load_state().get("token")
    if acct:
        for path in ["v2/user/info", "v2/comic/banner", "v2/payment/payments"]:
            try:
                st, data = call(path, token=acct, api=api)
                s = json.dumps(data, ensure_ascii=False)
                print(f"   [{path}] HTTP {st}  {s[:160]}")
            except MmluError as e:
                print(f"   [{path}] HTTP {e.status}  {e.payload}")
    else:
        print("   (无 .state.json，跳过；先跑 login)")


def main():
    args = sys.argv[1:]
    api = DEFAULT_API
    if not args:
        print(__doc__)
        return
    cmd = args[0]
    if cmd == "register":
        tok, d = register(api=api)
        print(tok)
    elif cmd == "login":
        cc, phone, pwd = args[1], args[2], args[3]
        tok, d = login(cc, phone, pwd, api=api)
        st, info = call("v2/user/info", token=tok, api=api)
        save_state({"token": tok, "user": info, "cred": [cc, phone, pwd]})
        print("token :", tok)
        print("user  :", json.dumps(info, ensure_ascii=False))
        print("saved :", os.path.normpath(STATE_FILE))
    elif cmd == "get":
        tok = load_state().get("token")
        st, data = call(args[1], token=tok, api=api)
        print(json.dumps(data, ensure_ascii=False, indent=2))
    elif cmd == "smoke":
        _smoke(api)
    elif cmd == "lines":
        print(json.dumps(STREAM_LINES, ensure_ascii=False, indent=2))
    elif cmd == "m3u8":
        aid = args[1]
        quality = args[2] if len(args) > 2 else "720"
        tok = load_state().get("token")
        if not tok:
            print("需要 .state.json（先跑 login）"); return
        path = animat_media(aid, tok, api=api, quality=quality)
        print("# media path:", path)
        lines = get_m3u8(path, tok)
        print(lines)
    elif cmd == "dl":
        # dl <animate_id> [quality=720] [out.ts]
        aid = args[1]
        quality = args[2] if len(args) > 2 else "720"
        out = args[3] if len(args) > 3 else f"/tmp/mmlu_{aid}_{quality}.ts"
        tok = load_state().get("token")
        if not tok:
            print("需要 .state.json（先跑 login）"); return
        path = animat_media(aid, tok, api=api, quality=quality)
        print("# media path:", path)
        t0 = time.time()
        total, n = download_hls(path, out, tok)
        print(f"# {out}  {total/1048576:.1f}MB / {n} 段 / {time.time()-t0:.0f}s")
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
