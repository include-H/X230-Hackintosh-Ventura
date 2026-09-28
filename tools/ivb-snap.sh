#!/bin/bash
# ThinkPad X230 黑苹果:最小快照 —— 就地看一眼 HD 4000(IVB)此刻到底有没有加速
#
# 用法(macOS 上,桌面里直接跑:不用重启、不用 sudo、不改任何东西):
#   bash tools/ivb-snap.sh                 # 存一份 ~/Desktop/ivb-snap-<主机名>-<时间>.txt
#   bash tools/ivb-snap.sh /Volumes/USB    # 存到指定目录
#
# 跑的就是这三条(外加 kextstat 一行,用来分清「内核里到底有没有驱动」):
#   ioreg -lw0 -r -c IntelAccelerator | head -30
#   ioreg -lw0 -r -c IOAccelerator | wc -l
#   system_profiler SPDisplaysDataType | grep -iE 'Metal|VRAM'
#
# 它只回答「此刻什么样」。要「开机那次 vs 现场加载一次」的 A/B 对照用 tools/ivb-now.sh,
# 要重启后的一屏判定用 tools/ivb-check.sh。
set -u

OUTDIR=""
for a in "$@"; do [ -d "$a" ] && OUTDIR="$a"; done
OUTDIR="${OUTDIR:-$HOME/Desktop}"
[ -d "$OUTDIR" ] || OUTDIR="$HOME"
OUT="$OUTDIR/ivb-snap-$(hostname -s)-$(date +%Y%m%d-%H%M%S).txt"
: >"$OUT"

say(){ printf '%s\n' "$*" | tee -a "$OUT"; }
run(){ printf '\n$ %s\n' "$1" | tee -a "$OUT"; bash -c "$1" 2>&1 | tee -a "$OUT" || printf '(命令失败 / 不存在)\n' | tee -a "$OUT"; }
hr(){ printf '%s\n' "------------------------------------------------------------" | tee -a "$OUT"; }

say "IVB(HD 4000)最小快照   $(date '+%F %T')"
say "主机: $(hostname -s)   系统: $(sw_vers -productVersion 2>/dev/null || echo '?') ($(uname -r))"
# 让这份日志自己带上「是哪份 config 跑出来的」——免得拿旧日志当新结果
for e in /Volumes/EFI /Volumes/ESP /Volumes/EFI1 /Volumes/BOOT; do
  if [ -f "$e/OC/config.plist" ]; then
    say "ESP config: $e/OC/config.plist   sha256(前16位) = $(shasum -a 256 "$e/OC/config.plist" 2>/dev/null | cut -c1-16)"
    break
  fi
done
hr
run "ioreg -lw0 -r -c IntelAccelerator | head -30"
run "ioreg -lw0 -r -c IOAccelerator | wc -l"
run "system_profiler SPDisplaysDataType | grep -iE 'Metal|VRAM'"

hr
say "== 判定 =="

ACCEL="$(ioreg -lw0 -r -c IOAccelerator 2>/dev/null | grep -c . || true)"
say "加速器实例(IOAccelerator 行数): ${ACCEL:-0}   $([ "${ACCEL:-0}" -gt 0 ] && echo '-> 在' || echo '-> 空,没有硬件加速')"

if command -v kmutil >/dev/null 2>&1; then
  LOADED="$(kmutil showloaded 2>/dev/null)"
else
  LOADED="$(kextstat 2>/dev/null)"
fi
KLINE="$(printf '%s\n' "$LOADED" | grep -iE 'Capri|HD4000' | awk '{print $6}' | paste -sd'; ' -)"
say "kextstat: ${KLINE:-(两条都没在)}"

DISPLAY_INFO="$(system_profiler SPDisplaysDataType 2>/dev/null)"
# 英文是 "Metal: Supported, feature set ...",中文是 "Metal 支持: 是" —— 两种都认
if printf '%s\n' "$DISPLAY_INFO" | grep -qiE 'Metal[^:：]*[:：] *(Supported|Yes|是)'; then
  say "Metal: 支持 ✓"
else
  say "Metal: 不支持(或系统没报这一行)"
fi
hr
say "怎么看:"
say "  加速器实例 > 0 且 Metal 支持   -> 内核侧和用户态都接上了"
say "  实例 0 但 kextstat 两条都在   -> kext 进了内核,服务起不来(注入属性 / 同名 kext 打架)"
say "  kextstat 少 AppleIntelHD4000Graphics -> 加速器根本没进内核,看 tools/ivb-now.sh 的第 ①/③ 对照"
say ""
say "输出文件(整体发出来就行): $OUT"
