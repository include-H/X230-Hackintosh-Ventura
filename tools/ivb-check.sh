#!/bin/bash
# ThinkPad X230 黑苹果:一屏判定 IVB(HD 4000)到底有没有真的加速
#
# 用法(macOS 上,**重启之后**跑):
#   bash tools/ivb-check.sh                 # 判定 + 存一份 ~/Desktop/ivb-check-<主机名>-<时间>.txt
#   bash tools/ivb-check.sh /Volumes/USB    # 存到指定目录
#
# 只读:不改 EFI、不改系统卷、不改 NVRAM。需要 sudo 的项会先问一次密码。
# 退出码:0 = 三条全过;1 = 还有没过的(过不了的输出会自动收进文件,直接发出来就行)。
#
# 判定的是三件事(对应 docs/OCLP.md 8.5):
#   ① kextstat 里 Capri 和 HD4000Graphics 两条都要在
#   ② IOAccelerator 实例数 > 0
#   ③ system_profiler 里 Metal 是 Supported
set -u

OUTDIR="${1:-$HOME/Desktop}"
[ -d "$OUTDIR" ] || OUTDIR="$HOME"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$OUTDIR/ivb-check-$(hostname -s)-$STAMP.txt"
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

say "IVB(HD 4000)加速判定"
say "主机: $(hostname -s)   系统: $(sw_vers -productVersion 2>/dev/null || echo '?') ($(uname -r))"
# 让每份日志自己带上「这是哪份 config 跑出来的」—— 免得拿旧日志当新结果
ESPCFG=""
for e in /Volumes/EFI /Volumes/ESP /Volumes/EFI1 /Volumes/BOOT; do
  [ -f "$e/OC/config.plist" ] && ESPCFG="$e/OC/config.plist" && break
done
if [ -n "$ESPCFG" ]; then
  say "ESP config: $ESPCFG"
  say "            sha256(前16位) = $(shasum -a 256 "$ESPCFG" 2>/dev/null | cut -c1-16)   ← 和工作区对比它,就知道这日志是新是旧"
else
  say "ESP config: (ESP 没挂载,跳过 —— 挂上再跑,日志就会带上 config 指纹)"
fi
hr

PASS=0
FAIL=0
verdict(){ # verdict <说明> <ok|fail> [细节]
  if [ "$2" = ok ]; then
    say "[ 通过 ] $1"
    PASS=$((PASS + 1))
  else
    say "[ 没过 ] $1"
    [ $# -ge 3 ] && say "         $3"
    FAIL=$((FAIL + 1))
  fi
}

say "== ① 驱动有没有进内核(kextstat)=="
if command -v kmutil >/dev/null 2>&1; then
  SHOWLOADED="$(kmutil showloaded 2>/dev/null)"
else
  SHOWLOADED="$(kextstat 2>/dev/null)"
fi
K_HD="$(printf '%s\n' "$SHOWLOADED" | grep -c 'AppleIntelHD4000Graphics' || true)"
K_CAPRI="$(printf '%s\n' "$SHOWLOADED" | grep -c 'AppleIntelFramebufferCapri' || true)"
printf '%s\n' "$SHOWLOADED" | grep -i 'AppleIntel\(HD4000Graphics\|FramebufferCapri\|HD4000GraphicsGLDriver\)' | tee -a "$OUT"

if [ "$K_HD" -gt 0 ]; then
  verdict "com.apple.driver.AppleIntelHD4000Graphics 已加载(加速器)" ok
else
  verdict "com.apple.driver.AppleIntelHD4000Graphics 不在列表里(加速器没进内核)" fail \
    "EFI 注入那两条启用了没?先确认 EFI 真的推到了 ESP(./tools/efi-sync.sh check /Volumes/EFI)"
fi
if [ "$K_CAPRI" -gt 0 ]; then
  verdict "com.apple.driver.AppleIntelFramebufferCapri 已加载(帧缓冲)" ok
else
  verdict "com.apple.driver.AppleIntelFramebufferCapri 也没加载 —— 两个都没进来" fail
fi

say ""
say "== ② 有没有加速器实例(IOAccelerator)=="
ACCEL="$(ioreg -lw0 -r -c IOAccelerator 2>/dev/null | wc -l | tr -d ' ')"
say "IOAccelerator 实例数: $ACCEL"
if [ "${ACCEL:-0}" -gt 0 ]; then
  verdict "IOAccelerator 有 $ACCEL 行输出(> 0)" ok
else
  verdict "IOAccelerator 是空的(= 0,硬件加速没起来)" fail \
    "kext 在、服务起不来。常见两种:iGPU 注入的属性声明了 BIOS 没预留的内存(framebuffer-stolenmem 之类),或同名 kext 被注入了两份(EFI 与 OCLP 的 AuxKC 打架)—— 看下面「附」里 iGPU 属性、同名 kext 和日志"
fi

say ""
say "== ③ Metal(system_profiler)=="
DISPLAY_INFO="$(system_profiler SPDisplaysDataType 2>/dev/null)"
printf '%s\n' "$DISPLAY_INFO" | grep -iE 'Chipset|Chipset Model|VRAM|Metal|芯片组|显存' | tee -a "$OUT"
METAL_LINE="$(printf '%s\n' "$DISPLAY_INFO" | grep -i 'Metal' | head -1)"
# 英文 "Metal: Supported" / 中文 "Metal 支持: 是" 都要认
METAL_VAL="$(printf '%s' "$METAL_LINE" | sed 's/.*[:：] *//' | tr -d '\r' | sed 's/ *$//')"
# 真机上是 "Metal: Supported, feature set macOS GPUFamily1 v4" 这种带尾巴的,
# 中文系统是 "Metal 支持: 是",所以用前缀匹配,不用全等。
case "$METAL_VAL" in
  Supported*|supported*|Yes*|yes*|是*) verdict "Metal = $METAL_VAL" ok ;;
  "")                                 verdict "system_profiler 里没有 Metal 这一行" fail ;;
  *)                                  verdict "Metal = $METAL_VAL" fail ;;
esac

say ""
say "== ④ IOKit 匹配现场(boot-args 里有 io=0x1f 才有内容,空的不代表坏)=="
KLOG(){ # KLOG <标签> <grep 扩展正则>
  say ""
  say "-- $1 --"
  run "$SUDO log show --last boot --info --debug --predicate 'process == \"kernel\"' 2>/dev/null | grep -E '$2' | head -50"
}
KLOG "加速器/帧缓冲这一族在 IOKit 里露过面吗(attach / probe / start)" 'IntelAccelerator|AppleIntelHD4000Graphics|AppleIntelCapriController|AppleIntelFramebuffer'
KLOG "匹配器的判决(匹配类别 / probe 分数 / 延迟匹配)" 'match category|probe score|matching deferred'
KLOG "IGPU 这个 nub 上注册过哪些服务(Registering)" 'Registering:.*(IGPU|VID|Capri|Accelerator|IGD)'
say ""
say "-- 这个类在内核里到底存不存在(ioclasscount:数字 = 实例数;报错 = 连类都没有)--"
run "if command -v ioclasscount >/dev/null 2>&1; then ioclasscount IntelAccelerator IOAccelerator AppleIntelCapriController AppleIntelFramebuffer 2>&1; else echo '(这台机器没有 ioclasscount,跳过)'; fi"
say ""
say "-- ACPI 里那块显卡叫 IGPU 还是 VID(SSDT-PNLF 的 Scope 要对上它)--"
run "ioreg -lw0 -p IODeviceTree -n IGPU 2>/dev/null | head -4; ioreg -lw0 -p IODeviceTree -n VID 2>/dev/null | head -4"
say ""
say "-- 诊断开关真的生效了吗(空的就说明 io=0x1f 没进内核)--"
run "nvram boot-args 2>/dev/null | tr ' ' '\n' | grep -E '^(io=|iokit_)' || echo '(boot-args 里没有 io= / iokit_*,④ 这节是空的属于正常)'"
say ""
say "④ 怎么读:"
say "  出现 IntelAccelerator[..]::attach(IGPU[..])  -> 个性匹配上了,是 start() 失败 -> 查它的内存/帧缓冲依赖"
say "  只有 Registering:、没有 attach               -> 个性根本没匹配上 -> 查 kext 来源与 Info.plist"
say "  出现 match category ... exists               -> 那个匹配类别被别人占了 -> 看谁先占了它"
say "  ioclasscount 里没有 IntelAccelerator         -> 类都没进内核,kext 是白加载的"
say ""

hr
say "== ⓔ 两处 30s 超时的现场:面板 / ME(PAVP)/ 环 =="
say ""
say "-- 驱动自己说的话(按「原话关键字」捞,不按 kext 名捞,-- 这些句子在二进制里)--"
say "   powering ON the panel / GMBUS / Assertion failed / display event timeout / ring to go idle"
EP='powering ON the panel|GMBUS|Assertion failed|display event timeout|ring to go idle|stuck waiting|PAVP|DRMStatus|MEClient|MEIClient|HECI|AppleIntelMEI|Content Access'
run "$SUDO log show --last boot --info --debug --predicate 'process == \"kernel\"' 2>/dev/null | grep -iE '$EP' | head -40"
say ""
say "-- 哪个服务的 start 花了多久 / 谁陪着它一起结束(xnu 的 kIOLogStart,要 io=0x1f 才有)--"
run "$SUDO log show --last boot --info --debug --predicate 'process == \"kernel\"' 2>/dev/null | grep -E '::start took|\\) <1> failed|busy timeout' | head -30"
say ""
say "-- ME(管理引擎)这一侧:设备在、类被实例化,才谈得上 PAVP 会话 --"
say "   (注意 kextstat 只列 bundle:AppleIntelMEIDriver 是 AppleIntelFramebufferCapri 里的一个类,"
say "    它永远不出现在 kextstat;要看的是 ioreg 里有没有实例)"
run "ioreg -lw0 -r -c AppleIntelMEIDriver 2>/dev/null | head -30; ioreg -lw0 -r -c AppleMEClientController 2>/dev/null | grep -iE '\"IOClass\"|IOProviderClass|PAVP|Session|DRM' | head -20"
say "   上面空 = 没有任何设备被 AppleIntelMEIDriver 认领(PAVP 必然握手失败)"
run "ioreg -lw0 -p IODeviceTree | grep -iE -B2 -A6 'IMEI|HECI' | head -40"
say ""
say "-- PCI 设备全表(名称 厂商号 设备号;找 8086:1e3a = 7 系列 MEI,在不在一目了然)--"
run "ioreg -l -c IOPCIDevice | awk '/\+-o /{n=\$0; sub(/.*\+-o /,\"\",n); sub(/ +<class.*/,\"\",n)} /\"vendor-id\" = </{v=\$NF} /\"device-id\" = </{print n, v, \$NF}' | sort -u | head -40"
run "ioreg -l -c IOPCIDevice | grep -ci '3a1e0000' | sed 's/^/  device-id=0x1e3a(小端 3a1e0000)出现次数: /'"
say ""
say "-- ACPI 自己有没有报错(比如重命名 SSDT 的 Scope 打空 = AE_NOT_FOUND)--"
run "$SUDO log show --last boot --info --debug --predicate 'process == \"kernel\"' 2>/dev/null | grep -iE 'ACPI Error|AE_NOT_FOUND|AE_ALREADY_EXISTS' | head -20"
say ""
say "ⓔ 怎么读:"
say "  只有 powering ON the panel / GMBUS     -> 卡在点亮面板(显示输出) -> 查 ig-platform-id 与连接器"
say "  出现 PAVP / MEClient / DRMStatus       -> 卡在 ME(PAVP)握手        -> 看 BIOS 里 Intel ME 开没开"
say "  AppleIntelMEIDriver 没有实例 + PCI 表里没有 8086:1e3a -> ME 在这台机器上没开(BIOS/HAP)"
say "  AppleMEClientController::start took 30000 ms 整  -> 定时器到点,不是硬件卡顿"
say "  两条 ::start took 都约 30000 ms        -> 两处 30s 超时,见 docs/踩坑记录.md 第 16 条"
say "  MEIDriver 零实例 + MEClient 满 30000ms + DRMStatus 8877652 -> 先去 BIOS 把 Intel ME 打开(2026-09-27 确诊)"
say ""

hr
say "== 附:上下文(判「为什么」的时候要用)=="
say "-- 加速器节点(空 = 服务被创建过、start 失败后被内核收走了)--"
run "ioreg -lw0 -r -c IntelAccelerator | head -40"
say ""
say "-- 帧缓冲控制器 / 帧缓冲实例(这一层通常是好的)--"
run "ioreg -lw0 -r -c AppleIntelCapriController | grep -iE '\"IOClass\"|AAPL,ig-platform-id|IOAccelerator' | head -20"
run "ioreg -lw0 -r -c AppleIntelFramebuffer | grep -iE '\"IOClass\"|AAPL,ig-platform-id|VRAM,totalMB|IOFBMemorySize' | head -40"
say ""
say "-- iGPU 上到底注进去了哪些属性(和 docs/踩坑记录.md 第 10 节对一遍)--"
run "ioreg -lw0 -r -c IOPCIDevice | grep -B3 -A25 'AAPL,ig-platform-id' | head -60"
run "ls -ld /Library/Extensions/AppleIntel*.kext /System/Library/Extensions/AppleIntel*.bundle 2>/dev/null"
run "if [ -d /Library/Extensions/AppleIntelHD4000Graphics.kext ]; then echo '(正常形态:12+ 真正在跑的就是 /Library/Extensions 这份 —— 别挪走)'; else echo '!! /Library/Extensions 里没有 HD4000 加速器 kext —— 该重跑 OCLP 的 Post-Install Root Patch'; fi"
say ""
say "-- EFI 的 Kernel -> Add 那两个同名 kext 到底注进去没有(12+ 上是 BootKC 预链接注入)--"
OCLOG="$(for e in /Volumes/EFI /Volumes/ESP /Volumes/EFI1 /Volumes/BOOT; do ls "$e"/opencore-*.txt 2>/dev/null; done | tail -1)"
if [ -n "$OCLOG" ]; then
  say "   (最新 OC 日志: $OCLOG)"
  run "grep -E 'Prelinked injection' '$OCLOG' || echo '(OC 日志里没有 Prelinked injection 行)'"
  say "   Invalid Parameter = OpenCore 没把它注进 BootKC,那两条 Kernel -> Add 是哑的;"
  say "   12+ 上真正提供驱动的永远是 /Library/Extensions 那份(见 docs/踩坑记录.md 第 16 条)。"
else
  say "(ESP 没挂载 / 根目录没有 opencore-*.txt —— 挂上 ESP 再跑,这一步就能看到 OC 的注入结论)"
fi
say ""
say "-- 两份同名 kext(EFI 注入的 vs OCLP 留在 /Library/Extensions 的)内核是怎么处理的 --"
run "$SUDO log show --last boot --style compact --predicate 'eventMessage CONTAINS \"AppleIntelHD4000Graphics\" OR eventMessage CONTAINS \"AppleIntelFramebufferCapri\"' 2>/dev/null | tail -25"

if [ "$FAIL" -gt 0 ]; then
  hr
  say "== 有 $FAIL 条没过,自动把这两份输出也收进来 =="
  KEXT=""
  for cand in /Library/Extensions/AppleIntelHD4000Graphics.kext /System/Library/Extensions/AppleIntelHD4000Graphics.kext; do
    [ -d "$cand" ] && KEXT="$cand" && break
  done
  if [ -n "$KEXT" ]; then
    run "$SUDO kextutil -v -t '$KEXT' 2>&1 | tail -40"
  else
    say "(系统卷和 /Library/Extensions 里都没有 AppleIntelHD4000Graphics.kext —— 补丁实体不在,那就该重跑 OCLP 了)"
  fi
  # 关键:`kextutil`(其实是 `kmutil load`)会把 kext 现场交给内核一次。
  # 开机时起不来、加载后能起来,和「怎么都起不来」是两种完全不同的病,
  # 所以这里必须再验一次,别让这个信息溜掉。
  say ""
  say "-- 把 kext 现场加载之后再验一次(和开头 ①②③ 对比;两种结果指向完全不同的病)--"
  run "sleep 4; ioreg -lw0 -r -c IntelAccelerator 2>/dev/null | head -20"
  run "ioreg -lw0 -r -c IOAccelerator 2>/dev/null | wc -l"
  run "sleep 1; system_profiler SPDisplaysDataType 2>/dev/null | grep -iE 'Metal|VRAM'"
  # 加速器 start 失败时,原因只有内核自己知道:kernel 的 IOLog 不打 kext 名,
  # 所以这里按「关键字」捞,不要只按 kext 名捞。加速器二进制里的原话有
  #   "Failed to map Device ID: 0x%x to GPU SKU!"、"NO EDRAM"、"STOLEN MEM" 等,
  # 帧缓冲侧有 "... Assertion failed: idx < fFBMemoryCount" 等。
  GK='AppleIntel|IGAccel|IntelAccelerator|AcceleratorIsMissing|Capri|Gen7|ig-platform|IGPU|stolen|STOLEN|SKU|EDRAM|FBMemory'
  say "-- 内核自己怎么说(只挑和显卡相关的行;这段要跑十几秒)--"
  run "$SUDO log show --last boot --info --debug --predicate 'process == \"kernel\"' 2>/dev/null | grep -iE '$GK' | grep -v 'draining messages' | tail -80"
  run "$SUDO dmesg 2>/dev/null | grep -iE '$GK' | tail -60"
  say ""
  say "-- Lilu / WhateverGreen 怎么说的(默认是哑的,除非 boot-args 里有 -liludbgall -wegdbg)--"
  run "$SUDO log show --last boot --info --debug --predicate 'eventMessage CONTAINS \"WhateverGreen\" OR eventMessage CONTAINS \"Lilu\" OR eventMessage CONTAINS \"igfx\"' 2>/dev/null | grep -vi 'draining messages' | tail -40"
  say ""
  say "-- 帧缓冲 start() 有没有被别人等超时(-- 出现 busy timeout 就说明有服务等它等到 60s --)"
  run "$SUDO log show --last boot --info --debug --predicate 'process == \"kernel\"' 2>/dev/null | grep -iE 'busy (timeout|extended)|loadPrefs|Multi Planes|waitQuiet' | tail -25"
  say ""
  say "-- kernelmanagerd 有没有在同名 kext 上打架(collision / marked as loadable / 构建集合)--"
  run "$SUDO log show --last boot --info --debug --predicate 'process == \"kernelmanagerd\"' 2>/dev/null | grep -iE 'Capri|HD4000|IOAccel|collision|loadable|build candidate|Auxiliary' | tail -30"
  say ""
  say "-- OCLP 的 AuxKC 里到底有没有这两个 kext(和 EFI 注入是两条路;按字符串数,不依赖 kmutil 的旗标)--"
  run "strings /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>/dev/null | grep -c 'AppleIntelHD4000Graphics' | sed 's/^/  AppleIntelHD4000Graphics 出现次数: /'"
  run "strings /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>/dev/null | grep -c 'AppleIntelFramebufferCapri' | sed 's/^/  AppleIntelFramebufferCapri 出现次数: /'"
  say ""
  say "-- WindowServer 自己怎么说(找不到加速器时它会抱怨 / 退回软件渲染)--"
  run "$SUDO log show --last boot --info --debug --predicate 'process == \"WindowServer\"' 2>/dev/null | grep -iE 'accelerator|metal|renderer|softwar|GPU' | tail -25"
  say ""
  say "-- boot-args 里有没有开 Lilu/WG 调试 --"
  run "nvram boot-args 2>/dev/null | tr ' ' '\n' | grep -iE 'lilu|weg|igfx' || echo '(没开 -liludbgall / -wegdbg,上面 WG 那段是空的很正常)'"
fi

hr
say "== 结论 =="
say "通过 $PASS 条 / 没过 $FAIL 条"
if [ "$FAIL" -eq 0 ]; then
  say ""
  say "三条全过 = 驱动和加速器都进内核了。再用手感确认一下:"
  say "  · Dock 应该是透明/半透明的,程序坞不应该是实心灰条"
  say "  · 拖动窗口、滚动网页不该一顿一顿"
  say "  · 关于本机 → 显示器 里显存应为 1536 MB"
  say ""
  say "文件也存了一份(方便和之前的状态对比): $OUT"
else
  say ""
  say "还没加速。把这个文件整体发出来就行 —— 上面「有 N 条没过」那一段已经"
  say "自动收好了 kextutil 和内核日志,不用你另外跑命令。"
  say ""
  say "在此之前可以顺手确认两件事:"
  say "  1) EFI 到底推没推上去:  ./tools/efi-sync.sh check /Volumes/EFI"
  say "  2) 系统侧补丁实体还在不在: ls -ld /Library/Extensions/AppleIntel*.kext"
  say "     (❌ 在的话**别点** Revert Root Patches —— 那 5 个用户态 bundle 只有 OCLP 能写)"
fi
say ""
say "输出文件: $OUT"

if [ "$FAIL" -eq 0 ]; then exit 0; else exit 1; fi
