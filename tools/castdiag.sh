#!/bin/sh
# 投屏画质诊断（只读）。必须在【投屏已连接】时运行。
#   ./tools/castdiag.sh
# 输出 probes/castdiag-<时间戳>.txt

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTDIR=$ROOT/probes
mkdir -p "$OUTDIR"
OUT=$OUTDIR/castdiag-$(date +%Y%m%d-%H%M%S).txt

say() { printf '%s\n' "$*" >> "$OUT"; }
cap() { t=$1; shift; say ""; say "########## $t ##########"; "$@" >> "$OUT" 2>&1; }

say "castdiag @ $(date '+%Y-%m-%d %H:%M:%S')"

cap "1. 无线显示会话" adb shell 'dumpsys display | grep -A18 "WifiDisplayAdapter" | head -24'
cap "2. 协商分辨率/标志" adb shell 'dumpsys display | grep -E "mAdvertisedDisplay"'

cap "3. 每块显示的尺寸与色彩模式" adb shell 'dumpsys display | grep "DisplayInfo{" | sed "s/, /\n/g" | grep -E "DisplayInfo|real |colorMode|supportedColorModes|density|type |layerStack"'

cap "4. 各显示合成色彩（关键）" adb shell 'dumpsys SurfaceFlinger | grep -E "^Display |colorMode=|renderIntent|dataspace|colorTransformMatrix|needsFiltering"'

cap "4b. 当前刷新率与模式" adb shell 'dumpsys display | grep -E "renderFrameRate|mode [0-9]+, |activeMode" | head -10; dumpsys SurfaceFlinger | grep -E "refreshRate|vsyncPeriod" | head -5'

cap "5. 镜像图层抽样" adb shell 'dumpsys SurfaceFlinger | grep -c "mirrored from"'

cap "6. 编码器日志" adb shell 'logcat -d -t 6000 2>/dev/null | grep -iE "codec.*(avc|hevc)|bitrate|WFDSession|MMediaCodec|video encoder" | tail -40'

cap "7. WiFi P2P 链路" adb shell 'dumpsys wifi | grep -iE "p2p|WifiP2pGroup|linkSpeed|mFrequency|connected" | head -30'

cap "8. 码率/画质相关设置" adb shell 'for ns in system secure global; do settings list $ns 2>/dev/null | grep -iE "wfd|cast|mirror|color_mode|bitrate"; done'

cap "9. 当前色彩模式设置" adb shell 'settings list global | grep -i color_mode'

say ""
say "########## 判读要点 ##########"
say "1) 第2节 mAdvertisedDisplayWidth/Height 就是协商输出分辨率；1080p = 与电视面板一致，不算低。"
say "2) 第4节看外接虚拟显示的 colorMode 与 colorTransformMatrix："
say "   若内屏 dataspace=DISPLAY_P3 而虚拟显示 colorMode=0 且 colorTransformMatrix=单位矩阵，"
say "   就是广色域数据被当 sRGB 送出 -> 电视端过饱和。"
say "3) 第6节若出现 bitrate= 具体数字，记录编码码率。"
say "4) 第7节 linkSpeed 决定码率上限；低于 50Mbps 基本喂不动 1080p 高质量。"
printf 'written: %s\n' "$OUT"
