import json, os, sys, re, urllib.request, urllib.error, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mmlu_api as M

API = M.DEFAULT_API
tok, _ = M.register(api=API)
try:
    M.call("v2/combine/startup?platform=2", token=tok, api=API)
except Exception as e:
    print("startup", type(e).__name__, str(e)[:80])

def get(path):
    return M.call(path, token=tok, api=API, raw=True, sign=False)

def head(url, n=16):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "okhttp/4.9.0"})
        with urllib.request.urlopen(req, timeout=30) as r:
            b = r.read(n); return f"{r.status} bytes={len(b)} {b[:16]!r}"
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code} len={len(e.read())}"
    except Exception as e:
        return f"ERR {type(e).__name__}: {str(e)[:80]}"

def test_media(label, mpath):
    print(f"\n########## {label}: {mpath}")
    for host in ["na.mmlu1.site", "stream-encrypt1.mmlutech.xyz",
                 "stream-encrypt1.mmlu4.site", "na.mmlutech.xyz", "na.mmlu4.site"]:
        url = f"{mpath}?host={host}&chain=miOBGgHNWhpt2"
        try:
            _, text = get(url)
        except Exception as e:
            print(f"  host={host:32s} m3u8 ERR {type(e).__name__} {str(e)[:80]}"); continue
        lines=[l.strip() for l in text.splitlines()]
        key=next((l for l in lines if "EXT-X-KEY" in l), "")
        segs=[l for l in lines if l and not l.startswith("#")]
        m=re.search(r'URI="([^"]+)"', key)
        ku=m.group(1) if m else None
        if ku and not ku.startswith("http"): ku="https://"+ku
        su=segs[0] if segs else None
        if su and not su.startswith("http"): su="https://"+su
        kstat = head(ku) if ku else "(no key)"
        sstat = head(su) if su else "(no seg)"
        print(f"  host={host:32s} segs={len(segs):4d} keyhost={ (ku.split('/')[2] if ku else '-') }")
        print(f"        KEY {kstat}")
        print(f"        SEG {sstat}")

# NS 动漫
try:
    _, d = M.call("v3/nsanimat/new", token=tok, api=API)
    items = d if isinstance(d, list) else d.get("data") or []
    it = items[0]
    print("NS item", it.get("id"), it.get("avkey"), it.get("source"))
    _, det = M.call(f"v3/nsanimat/internal/{it['id']}", token=tok, api=API)
    summ = det.get("summary") or det.get("directory") or []
    if isinstance(summ, dict): summ=[summ]
    media = summ[0].get("media", {})
    test_media("NS", media.get("720") or next(iter(media.values())))
except Exception as e:
    print("NS err", type(e).__name__, str(e)[:160])

# AV 动漫
try:
    _, d = M.call("v3/search/animat?keywords=" + urllib.parse.quote("鬼父") + "&sort=1&counts=24&pages=1", token=tok, api=API)
    items = d if isinstance(d, list) else d.get("data") or []
    av = next(x for x in items if x.get("source")=="av")
    print("\nAV item", av.get("id"), av.get("avkey"))
    _, det = M.call(f"v2/combine/animat/internal/{av['id']}", token=tok, api=API)
    summ = det.get("summary") or det.get("directory") or []
    if isinstance(summ, dict): summ=[summ]
    media = summ[0].get("media", {})
    test_media("AV", media.get("720") or next(iter(media.values())))
except Exception as e:
    print("AV err", type(e).__name__, str(e)[:160])
