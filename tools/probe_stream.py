#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""对比昨天(na.mmlu1.site/无签名)与本会话(stream-encrypt1/签名403)的流媒体取法。

测试维度：
  - 详情来源： v3/nsanimat/internal/{id}  vs  v2/combine/animat/internal/{id}
  - media 路径：服务端给的 media[720]
  - host 参数： None / '' / na.mmlu1.site / stream-encrypt1.mmlutech.xyz / stream-encrypt1.mmlu4.site
最后实际 GET 第一个分片，报告 HTTP 状态。
"""
import json
import sys
import time
import urllib.request
import urllib.error

sys.path.insert(0, "/root/mmlu_client/tools")
import mmlu_api as M

TOK = M.load_state().get("token")
API = M.DEFAULT_API


def retry(fn, tries=6, base=1.2):
    last = None
    for i in range(tries):
        try:
            return fn()
        except M.MmluError:
            raise
        except Exception as e:
            last = e
            time.sleep(base + i)
    raise last


def get_raw(url, api):
    def f():
        return M.call(url, token=TOK, api=api, raw=True, sign=False)
    return retry(f)


def head_segments(text):
    segs = []
    for ln in text.splitlines():
        ln = ln.strip()
        if ln.startswith("http") or ("/ts/" in ln and ln.startswith("stream")) or ln.startswith("na."):
            segs.append(ln)
    return segs


def main():
    aid = sys.argv[1] if len(sys.argv) > 1 else None
    # 取一个动漫 id + avkey
    st, data = retry(lambda: M.call("v3/nsanimat/new", token=TOK, api=API, raw=False))
    items = data if isinstance(data, list) else data.get("data") or []
    if aid is None:
        aid = str(items[0]["id"])
    print(f"# anime id={aid}  avkey={items[0].get('avkey')}")

    # 两个详情来源
    for src in [f"v3/nsanimat/internal/{aid}", f"v2/combine/animat/internal/{aid}"]:
        try:
            _, d = retry(lambda s=src: M.call(s, token=TOK, api=API))
            summ = d.get("summary") or d.get("directory") or []
            if isinstance(summ, dict):
                summ = [summ]
            media = summ[0].get("media", {})
            print(f"\n== {src}\n   media={json.dumps(media, ensure_ascii=False)}")
            path = media.get("720")
            if not path:
                continue
            # host 变体
            hosts = [None, "", "na.mmlu1.site", "stream-encrypt1.mmlutech.xyz", "stream-encrypt1.mmlu4.site"]
            for h in hosts:
                q = "chain=miOBGgHNWhpt2"
                if h is not None:
                    q = f"host={h}&" + q
                url = f"{path}?{q}"
                try:
                    _, text = get_raw(url, API)
                except Exception as e:
                    print(f"   [host={h!r}] FETCH ERR {type(e).__name__}: {e}")
                    continue
                segs = head_segments(text)
                key = next((l for l in text.splitlines() if "EXT-X-KEY" in l), "")
                sample = segs[0] if segs else "(no seg)"
                signed = "Signature=" in sample
                print(f"   [host={h!r}] segs={len(segs)} signed={signed}")
                print(f"       key: {key[:120]}")
                print(f"       seg: {sample[:140]}")
                # 尝试下载第一个分片
                if sample:
                    u = sample if sample.startswith("http") else "https://" + sample
                    try:
                        rq = urllib.request.Request(u, headers={"User-Agent": "okhttp/4.9.0"})
                        with urllib.request.urlopen(rq, timeout=20) as r:
                            b = r.read()
                            print(f"       -> GET {r.status} bytes={len(b)}")
                    except urllib.error.HTTPError as e:
                        print(f"       -> GET HTTP {e.code} (len={len(e.read())})")
                    except Exception as e:
                        print(f"       -> GET ERR {type(e).__name__}: {e}")
        except Exception as e:
            print(f"== {src} ERR {type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
