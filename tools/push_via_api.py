#!/usr/bin/env python3
"""
通过 api.github.com 建仓库 + 上传全部文件 + 触发 Actions + 下载 IPA。
适用于「github.com 网页打不开 / git push 被阻断，但 api.github.com 可达」的情况。

用法（PowerShell）：
    $env:GITHUB_TOKEN = "ghp_xxx"
    python tools/push_via_api.py --repo probe --public --watch

用法（Git Bash / macOS）：
    export GITHUB_TOKEN=ghp_xxx
    python tools/push_via_api.py --repo probe --public --watch
"""

import argparse
import base64
import getpass
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"

SKIP_DIRS = {".git", "build", "__pycache__", ".idea", "DerivedData"}
SKIP_FILES = {".DS_Store", "Thumbs.db"}


def call(method, path, token, data=None):
    url = path if path.startswith("http") else API + path
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if body:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            payload = resp.read()
            return resp.status, (json.loads(payload) if payload else None)
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(text)
        except Exception:
            return e.code, text


def collect_files(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name in SKIP_FILES:
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            out.append((rel, full))
    return sorted(out)


def ensure_repo(token, repo, public):
    status, me = call("GET", "/user", token)
    if status != 200:
        sys.exit("Token 无效或权限不足：%s" % me)
    owner = me["login"]

    status, _ = call("GET", "/repos/%s/%s" % (owner, repo), token)
    if status == 200:
        print("仓库已存在：%s/%s" % (owner, repo))
        return owner

    print("创建仓库 %s/%s ..." % (owner, repo))
    status, res = call("POST", "/user/repos", token, {
        "name": repo,
        "private": not public,
        "auto_init": False,
        "description": "探针 Probe - iOS 系统监控面板（未签名 IPA 构建）",
    })
    if status not in (200, 201):
        sys.exit("创建仓库失败：%s" % res)
    return owner


def upload(token, owner, repo, files):
    total = len(files)
    for idx, (rel, full) in enumerate(files, 1):
        with open(full, "rb") as fh:
            content = base64.b64encode(fh.read()).decode("ascii")

        # 已存在则取 sha 覆盖
        status, meta = call("GET", "/repos/%s/%s/contents/%s" % (owner, repo, rel), token)
        body = {"message": "add %s" % rel, "content": content}
        if status == 200 and isinstance(meta, dict):
            body["sha"] = meta["sha"]

        status, res = call("PUT", "/repos/%s/%s/contents/%s" % (owner, repo, rel), token, body)
        mark = "ok" if status in (200, 201) else "失败(%s)" % status
        print("  [%2d/%2d] %-58s %s" % (idx, total, rel, mark))
        if status not in (200, 201):
            print("        详情：%s" % str(res)[:300])


def trigger_and_watch(token, owner, repo, timeout_min):
    status, _ = call("POST", "/repos/%s/%s/actions/workflows/build-ipa.yml/dispatches" % (owner, repo),
                     token, {"ref": "main"})
    if status not in (204, 200):
        print("触发 workflow 返回 %s（若已由 push 触发，可忽略）" % status)

    deadline = time.time() + timeout_min * 60
    run_id = None
    while time.time() < deadline:
        status, runs = call("GET", "/repos/%s/%s/actions/runs?per_page=1" % (owner, repo), token)
        if status == 200 and runs.get("workflow_runs"):
            run = runs["workflow_runs"][0]
            run_id = run["id"]
            state = "%s/%s" % (run.get("status"), run.get("conclusion"))
            print("  构建状态：%s" % state)
            if run.get("status") == "completed":
                break
        time.sleep(15)

    if not run_id:
        sys.exit("未找到构建记录")

    if run.get("conclusion") != "success":
        print("构建失败，日志：https://github.com/%s/%s/actions/runs/%s" % (owner, repo, run_id))
        return

    status, arts = call("GET", "/repos/%s/%s/actions/runs/%s/artifacts" % (owner, repo, run_id), token)
    if status != 200 or not arts.get("artifacts"):
        print("未找到产物")
        return

    art = arts["artifacts"][0]
    url = "%s/repos/%s/%s/actions/artifacts/%s/zip" % (API, owner, repo, art["id"])
    os.makedirs("dist", exist_ok=True)
    out = os.path.join("dist", art["name"] + ".zip")

    # 手动处理 302：跳转到对象存储后不要带 Authorization 头
    req = urllib.request.Request(url)
    req.add_header("Authorization", "Bearer " + token)
    opener = urllib.request.build_opener(urllib.request.HTTPRedirectHandler())
    with opener.open(req, timeout=180) as resp, open(out, "wb") as fh:
        fh.write(resp.read())
    print("已下载产物：%s（解压即得 Probe-unsigned.ipa）" % out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="probe", help="仓库名")
    ap.add_argument("--public", action="store_true", help="设为公开仓库（Actions 免费不限时长）")
    ap.add_argument("--watch", action="store_true", help="触发构建并等待、自动下载 IPA")
    ap.add_argument("--timeout", type=int, default=20, help="等待构建的分钟数")
    args = ap.parse_args()

    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        token = getpass.getpass("粘贴 GitHub Token（输入时不回显）：").strip()
    if not token:
        sys.exit("缺少 GITHUB_TOKEN")

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = collect_files(root)
    print("待上传 %d 个文件，根目录：%s\n" % (len(files), root))

    owner = ensure_repo(token, args.repo, args.public)
    upload(token, owner, args.repo, files)
    print("\n仓库地址：https://github.com/%s/%s" % (owner, args.repo))

    if args.watch:
        print("\n触发构建...")
        trigger_and_watch(token, owner, args.repo, args.timeout)


if __name__ == "__main__":
    main()
