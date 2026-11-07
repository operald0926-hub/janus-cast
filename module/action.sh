#!/system/bin/sh
# KernelSU 模块「操作」按钮。只做只读状态展示，不做破坏性动作。

MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
exec "$MODDIR/bin/extd" status
