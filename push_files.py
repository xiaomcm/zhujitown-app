#!/usr/bin/env python3
"""把指定的单个/多个文件更新到 GitHub（contents API），用于 git 协议被代理拦截时的增量改动。

用法：
    export GH_TOKEN=ghp_xxx
    python push_files.py codemagic.yaml zhujitown-ios/scripts/build_unsigned_ipa.sh
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

TOKEN = os.environ.get("GH_TOKEN")
REPO = os.environ.get("GH_REPO", "xiaomcm/zhujitown-app")
BRANCH = os.environ.get("GH_BRANCH", "main")
MSG = os.environ.get("GH_MSG", "更新文件")

if not TOKEN:
    raise SystemExit("请先 export GH_TOKEN=你的令牌")

BASE = f"https://api.github.com/repos/{REPO}/contents"
HEADERS = {"Authorization": "Bearer " + TOKEN,
           "Accept": "application/vnd.github+json",
           "Content-Type": "application/json",
           "User-Agent": "zhujitown-builder"}


def call(method, url, payload=None):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {url} -> {e.code} {e.read().decode()[:300]}")


for path in sys.argv[1:]:
    if not os.path.isfile(path):
        print(f"跳过（不存在）: {path}")
        continue
    remote = path.replace("\\", "/")
    sha = None
    try:
        sha = call("GET", f"{BASE}/{remote}")["sha"]
    except SystemExit:
        pass  # 新文件，没有 sha
    payload = {
        "message": MSG,
        "content": base64.b64encode(open(path, "rb").read()).decode("ascii"),
        "branch": BRANCH,
    }
    if sha:
        payload["sha"] = sha
    d = call("PUT", f"{BASE}/{remote}", payload)
    print(f"已更新 {remote}  ->  commit {d['commit']['sha'][:8]}")
