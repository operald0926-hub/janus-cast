#!/bin/sh
# 打包成可被 KernelSU / Magisk 管理器直接安装的 zip。
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=$(grep '^version=' "$ROOT/module/module.prop" | cut -d= -f2)
OUT=$ROOT/dist/janus-cast-$VER.zip

mkdir -p "$ROOT/dist"
rm -f "$OUT"

cd "$ROOT/module"
zip -r -q "$OUT" . -x '*.DS_Store' '*/.git/*'

printf 'built: %s (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
