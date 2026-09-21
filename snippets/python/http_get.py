#!/usr/bin/env python3
"""用标准库发一个 GET 请求并返回文本。"""
import sys
import urllib.request


def http_get(url: str, timeout: int = 10) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "snippet-box/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8")


if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else "https://example.com"
    print(http_get(url)[:500])
