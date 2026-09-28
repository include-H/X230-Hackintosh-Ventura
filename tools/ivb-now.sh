#!/bin/bash
# ThinkPad X230 黑苹果:「此刻」IVB(HD 4000)加速器状态 —— 同一次运行里做 A/B 对照
#
# 用法(macOS 上,**不用重启**,桌面里直接跑):
#   bash tools/ivb-now.sh                 # ① 先读一次 ② 现场把 kext 交给内核一次 ③ 再读一次
#   bash tools/ivb-now.sh --ro            # 只读(跳过第 ② 步,只回答「现在什么样」)
#   bash tools/ivb-now.sh /Volumes/USB    # 输出文件放别处
#
# 为什么要 A/B:开机时起不来、现场加载能起来,和「怎么都起不来」是两种完全不同的病
#   · ①③ 都空                    -> 内核侧真的起不来
#   · ① 空、③ 有                 -> 服务能起,只是开机那次没起来(时序/顺序问题)
#   · ③ 有但 Metal 还是不支持    -> 内核有了,用户态 Metal 那套没接上(OCLP 的 Metal 3802 + MTLDriver)
#
# 第 ② 步就是 `kextutil -t`(等价于 `kmutil load`):把已经在磁盘上的 kext 再交给内核一次。
# 它不改 EFI、不改系统卷、不改 NVRAM —— 和 `ivb-check.sh` 失败分支里做的是同一件事。
# 输出文件直接发出来就够了。
set -u

RO=0
OUTDIR=""
for a in "$@"; do
  case "$a" in
    --ro|ro) RO=1 ;;
    *) [ -d "$a" ] && OUTDIR="$a" ;;
  esac
done
OUTDIR="${OUTDIR:-$HOME/Desktop}"
[ -d "$OUTDIR" ] || OUTDIR="$HOME"
OUT="$OUTDIR/ivb-now-$(hostname -s)-$(date +%Y%m%d-%H%M%S).txt"
: >"$OUT"

say(){ printf '%s\n' "$*" | tee -a "$OUT"; }
run(){ printf '\n$ %s\n' "$1" | tee -a "$OUT"; bash -c "$1" 2>&1 | tee -a "$OUT" || printf '(命令失败 / 不存在)\n' | tee -a "$OUT"; }
hr(){ printf '%s\n' "------------------------------------------------------------" | tee -a "$OUT"; }

SUDO=""
if command -v sudo >/dev/null 2>&1 && sudo -v 2>/dev/null; then
  SUDO="sudo"
else
  say "!! 没拿到 sudo —— 需要 root 的项会跳过(想看全就重跑,提示时输入密码)"
fi

probe(){ # probe <标签>
  say "== $1 =="
  run "ioreg -lw0 -r -c IntelAccelerator 2>/dev/null | head -30"
  run "ioreg -lw0 -r -c IOAccelerator 2>/dev/null | wc -l | sed 's/^/IOAccelerator 行数: /'"
  run "system_profiler SPDisplaysDataType 2>/dev/null | grep -iE 'Chipset|VRAM|Metal|芯片组|显存'"
  run "kmutil showloaded 2>/dev/null | grep -iE 'Capri|HD4000' || echo '(kmutil showloaded 里没有 Capri / HD4000)'"
}

say "IVB(HD 4000)此刻状态   $(date '+%F %T')"
say "主机: $(hostname -s)   系统: $(sw_vers -productVersion 2>/dev/null || echo '?') ($(uname -r))   已开机: $(uptime | sed 's/.* up //; s/,.*//')"
for e in /Volumes/EFI /Volumes/ESP /Volumes/EFI1 /Volumes/BOOT; do
  if [ -f "$e/OC/config.plist" ]; then
    say "ESP config: $e/OC/config.plist   sha256(前16位) = $(shasum -a 256 "$e/OC/config.plist" 2>/dev/null | cut -c1-16)"
    break
  fi
done
run "nvram boot-args 2>/dev/null"
hr
probe "① 现在(什么都还没做)"

say ""
say "-- WindowServer / kernelmanagerd 最近怎么说(时间戳很关键:只看最后一句会被开机那会儿骗)--"
run "$SUDO log show --last boot --info --debug --predicate 'process == \"WindowServer\"' 2>/dev/null | grep -iE 'accelerator|Metal|compositor' | tail -12"
run "$SUDO log show --last boot --info --debug --predicate 'process == \"kernelmanagerd\"' 2>/dev/null | grep -iE 'Capri|HD4000|Collision|in-kernel fileset' | tail -12"

if [ "$RO" -eq 1 ]; then
  hr
  say "-- 只读模式:跳过第 ② 步(现场加载)--"
else
  hr
  say "== ② 现场把加速器 kext 交给内核一次(就是 ivb-check.sh 失败分支里 kextutil 干的事)=="
  KEXT=""
  for c in /Library/Extensions/AppleIntelHD4000Graphics.kext /System/Library/Extensions/AppleIntelHD4000Graphics.kext; do
    [ -d "$c" ] && KEXT="$c" && break
  done
  if [ -n "$KEXT" ]; then
    run "$SUDO kextutil -v -t '$KEXT' 2>&1 | tail -20"
    say "(等 5 秒,让内核把「匹配 → 启动」这一段跑完)"
    sleep 5
    hr
    probe "③ 加载之后"
    say ""
    say "-- kernelmanagerd 对这一次加载的判决(关键就两句话:Collision / will start, will match)--"
    run "$SUDO log show --last 2m --info --debug --predicate 'process == \"kernelmanagerd\"' 2>/dev/null | grep -iE 'HD4000|Capri|Collision|in-kernel fileset' | tail -12"
  else
    say "(/Library/Extensions 和系统卷里都没有 AppleIntelHD4000Graphics.kext —— 补丁实体不在,该重跑 OCLP 了)"
  fi
fi

hr
say "== 结论怎么看 =="
say "① 和 ③ 都空             -> 内核侧真的起不来,查加速器 start() 为什么失败"
say "① 空、③ 有              -> 服务能起,只是开机那次没起来 -> 时序/顺序问题,方向完全不同"
say "③ 有、但 Metal 不支持   -> 内核有了,用户态 Metal 那套没接上(OCLP Metal 3802 + MTLDriver)"
say "两处都是 software compositor -> WindowServer 到那一刻仍在软件渲染"
say ""
say "输出文件(整体发出来就行): $OUT"
