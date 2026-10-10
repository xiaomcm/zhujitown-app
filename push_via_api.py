#!/usr/bin/env python3
"""在 git 协议被代理拦截时，用 GitHub Git Data API 推送本地仓库（保留提交历史）。

用法：
    set GH_TOKEN=ghp_xxx          (Windows cmd)
    export GH_TOKEN=ghp_xxx       (bash)
    python push_via_api.py xiaomcm zhujitown-app

原理：逐个本地 commit 取其完整快照 tree -> API 创建 tree -> commit -> 移动 ref。
只走 HTTPS REST，跟 curl 同一条链路（本机能通）。
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"
MAX_BYTES_PER_TREE = 3_500_000   # 单次 tree 请求体上限（留余量）
MAX_ENTRIES_PER_TREE = 80


def git(*args, binary=False):
    r = subprocess.run(["git", *args], capture_output=True, check=True)
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def api(method, path, token, payload=None, tries=4):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "zhujitown-app-builder",
        },
    )
    last = None
    for i in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            last = f"{e.code} {body[:400]}"
            if e.code in (429, 502, 503, 504):
                time.sleep(2 * (i + 1))
                continue
            raise SystemExit(f"API {method} {path} 失败: {last}")
        except Exception as e:                      # noqa: BLE001
            last = str(e)
            time.sleep(2 * (i + 1))
    raise SystemExit(f"API {method} {path} 重试耗尽: {last}")


def snapshot(commit_sha):
    """返回 [(mode, type, path)] 完整快照"""
    out = git("ls-tree", "-r", "-z", "--format=%(objectmode) %(objecttype) %(path)", commit_sha)
    items = []
    for rec in out.split("\0"):
        rec = rec.strip()
        if not rec:
            continue
        parts = rec.split(" ", 2)
        if len(parts) != 3:
            continue
        mode, otype, path = parts
        if otype != "blob":          # 跳过 submodule / 空 tree
            continue
        items.append((mode, path))
    return items


def read_blob(commit_sha, path):
    """取该文件在指定 commit 的内容（bytes）"""
    spec = f"{commit_sha}:{path}"
    try:
        return git("cat-file", "blob", spec, binary=True)
    except subprocess.CalledProcessError:
        return None


def entry_payload(commit_sha, mode, path):
    raw = read_blob(commit_sha, path)
    if raw is None:
        return None
    try:
        text = raw.decode("utf-8")
        if "\0" in text:
            raise UnicodeDecodeError("utf-8", b"", 0, 1, "NUL")
        return {"path": path, "mode": mode, "type": "blob", "content": text}
    except UnicodeDecodeError:
        return {"path": path, "mode": mode, "type": "blob",
                "content": base64.b64encode(raw).decode("ascii"), "encoding": "base64"}


def main():
    token = os.environ.get("GH_TOKEN")
    if not token:
        raise SystemExit("请先 export GH_TOKEN=你的令牌")
    owner = sys.argv[1] if len(sys.argv) > 1 else None
    repo = sys.argv[2] if len(sys.argv) > 2 else "zhujitown-app"

    me = api("GET", "/user", token)
    owner = owner or me["login"]
    print(f"==> 已登录：{owner}，目标仓库 {owner}/{repo}")

    # 仓库不存在则创建
    try:
        info = api("GET", f"/repos/{owner}/{repo}", token)
    except SystemExit:
        print(f"==> 创建仓库 {repo}")
        info = api("POST", "/user/repos", token, {
            "name": repo, "private": False,
            "description": "主机镇 WordPress 原生 App（Android + iOS）",
        })
    default_branch = info.get("default_branch") or "main"
    branch = "master" if default_branch == "master" else default_branch

    # 空仓库要先有一个 commit（tree API 对空仓库返回 409），用 contents API 初始化
    parent = None
    try:
        ref = api("GET", f"/repos/{owner}/{repo}/git/refs/heads/{branch}", token)
        parent = ref["object"]["sha"]
        print(f"==> 仓库已有内容，{branch} @ {parent[:8]}")
    except SystemExit:
        print("==> 空仓库，先写入 README 初始化")
        init = api("PUT", f"/repos/{owner}/{repo}/contents/README.md", token, {
            "message": "初始化仓库",
            "content": base64.b64encode(
                "# zhujitown-app\n\n主机镇 WordPress 原生 App（Android + iOS）\n".encode("utf-8")
            ).decode("ascii"),
            "branch": branch,
        })
        parent = init["commit"]["sha"]

    # 本地提交（按时间正序）
    log = git("log", "--reverse", "--format=%H%x1f%an%x1f%ae%x1f%aI%x1f%s%x1e")
    commits = []
    for rec in log.split("\x1e"):
        rec = rec.strip("\n")
        if not rec.strip():
            continue
        sha, an, ae, ad, subj = rec.split("\x1f", 4)
        commits.append((sha, an, ae, ad, subj))
    print(f"==> 本地 {len(commits)} 个提交待重放")

    for idx, (sha, an, ae, ad, subj) in enumerate(commits, 1):
        items = snapshot(sha)
        # 分批 -> 累积成一个完整 tree
        tree_sha = None
        batch, batch_bytes = [], 0
        batches = []
        for mode, path in items:
            e = entry_payload(sha, mode, path)
            if e is None:
                continue
            size = len(e["content"]) * (3 / 4 if e.get("encoding") == "base64" else 1)
            if batch and (batch_bytes + size > MAX_BYTES_PER_TREE
                          or len(batch) >= MAX_ENTRIES_PER_TREE):
                batches.append(batch)
                batch, batch_bytes = [], 0
            batch.append(e)
            batch_bytes += size
        if batch:
            batches.append(batch)

        for bi, b in enumerate(batches, 1):
            payload = {"tree": b}
            if tree_sha:
                payload["base_tree"] = tree_sha
            tree_sha = api("POST", f"/repos/{owner}/{repo}/git/trees", token, payload)["sha"]
            print(f"    tree {bi}/{len(batches)} -> {tree_sha[:8]}")

        payload = {"tree": tree_sha, "message": subj,
                   "author": {"name": an, "email": ae, "date": ad}}
        if parent:
            payload["parents"] = [parent]
        c = api("POST", f"/repos/{owner}/{repo}/git/commits", token, payload)
        parent = c["sha"]
        print(f"[{idx}/{len(commits)}] {c['sha'][:8]}  {subj[:50]}")

    api("PATCH", f"/repos/{owner}/{repo}/git/refs/heads/{branch}", token, {"sha": parent})
    print()
    print(f"==> 完成：https://github.com/{owner}/{repo}")
    print(f"    {branch} @ {parent[:8]}（{len(commits)} 个提交）")
    print(f"==> Actions：https://github.com/{owner}/{repo}/actions")


if __name__ == "__main__":
    main()
