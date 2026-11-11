#!/usr/bin/env python3
"""创建 GitHub Release 并上传 zip 附件。

用法:
    python3 tools/make_release.py <github_token> [tag]

token 需要 repo 权限（classic PAT 勾 repo 即可）。
说明正文取自 docs/RELEASE-<tag>.md，附件取 dist/janus-cast-<tag>.zip。
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

OWNER = "operlad0926-hub"
REPO = "janus-cast"


def main():
    if len(sys.argv) < 2:
        sys.exit("用法: python3 tools/make_release.py <github_token> [tag]")
    token = sys.argv[1]
    tag = sys.argv[2] if len(sys.argv) > 2 else "v1.2.0"

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    notes_path = os.path.join(root, "docs", f"RELEASE-{tag}.md")
    zip_path = os.path.join(root, "dist", f"janus-cast-{tag}.zip")
    for p in (notes_path, zip_path):
        if not os.path.exists(p):
            sys.exit(f"缺少文件: {p}")

    hdr = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "janus-release",
    }

    def call(url, method="GET", data=None, ctype="application/json"):
        req = urllib.request.Request(url, data=data, headers={**hdr, "Content-Type": ctype}, method=method)
        with urllib.request.urlopen(req, timeout=90) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}

    body = open(notes_path, encoding="utf-8").read()

    # 已存在就直接复用
    try:
        rel = call(f"https://api.github.com/repos/{OWNER}/{REPO}/releases/tags/{tag}")
        print("release 已存在:", rel["html_url"])
    except urllib.error.HTTPError as e:
        if e.code != 404:
            sys.exit(f"查询失败 HTTP {e.code}: {e.read()[:200]}")
        rel = call(
            f"https://api.github.com/repos/{OWNER}/{REPO}/releases",
            method="POST",
            data=json.dumps({
                "tag_name": tag,
                "target_commitish": "main",
                "name": f"JANUS Cast {tag}",
                "body": body,
            }).encode(),
        )
        print("release 已创建:", rel["html_url"])

    # 附件
    existing = {a["name"] for a in rel.get("assets", [])}
    name = os.path.basename(zip_path)
    if name in existing:
        print("附件已存在，跳过:", name)
        return

    up = rel["upload_url"].split("{")[0] + f"?name={name}"
    raw = open(zip_path, "rb").read()
    for attempt in range(4):
        try:
            asset = call(up, method="POST", data=raw, ctype="application/zip")
            print(f"附件已上传: {asset['name']} ({asset['size']} bytes)")
            return
        except urllib.error.HTTPError as e:
            if e.code == 422:
                print("附件已存在（422），视为完成")
                return
            print(f"上传失败 HTTP {e.code}，重试 {attempt + 1}/4")
            time.sleep(3)
    sys.exit("附件上传失败")


if __name__ == "__main__":
    main()
