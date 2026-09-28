#!/bin/bash
# ThinkPad X230 黑苹果:OCLP 显卡 / 加速诊断信息收集
#
# 用法(macOS 上):
#   bash oclp-diag.sh                 # 输出到 ~/Desktop/oclp-diag-<主机名>-<时间>.txt
#   bash oclp-diag.sh /Volumes/USB    # 输出到指定目录
#
# 只读:不改 EFI、不改系统卷、不改 NVRAM。需要 sudo 的项会先问一次密码。
set -u

OUTDIR="${1:-$HOME/Desktop}"
[ -d "$OUTDIR" ] || OUTDIR="$HOME"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$OUTDIR/oclp-diag-$(hostname -s)-$STAMP.txt"

SUDO=""
if sudo -v 2>/dev/null; then
  SUDO="sudo"
else
  printf '!! 没拿到 sudo —— 跳过需要 root 的项。想看完整信息请重跑并在提示时输入密码。\n'
fi

sec(){ printf '\n\n=========================================================\n== %s\n=========================================================\n' "$1" >>"$OUT"; }
sh_(){ printf '\n$ %s\n' "$1" >>"$OUT"; bash -c "$1" >>"$OUT" 2>&1 || printf '(命令失败 / 不存在)\n' >>"$OUT"; }

: >"$OUT"
printf 'OCLP / 显卡诊断包\n主机: %s\n时间: %s\n' "$(hostname)" "$(date)" >>"$OUT"

sec "1. 系统与机型"
sh_ "sw_vers"
sh_ "uname -a"
sh_ "sysctl -n machdep.cpu.brand_string; sysctl -n hw.model; sysctl -n hw.ncpu"
sh_ "system_profiler SPHardwareDataType"

sec "2. 显卡现状(system_profiler)"
sh_ "system_profiler SPDisplaysDataType"

sec "3. 加速器 / 帧缓冲(IORegistry;空 = 没有加速器)"
sh_ "ioreg -lw0 -r -c IOAccelerator | head -80"
sh_ "echo \"IOAccelerator 实例数: \$(ioreg -lw0 -r -c IOAccelerator | wc -l)\""
sh_ "ioreg -lw0 -r -c AppleIntelFramebufferCapri | grep -E 'IOClass|AAPL,ig-platform-id|IOFBDependentID|IOAccelerator' | head -20"
sh_ "ioreg -lw0 -p IOService -n IntelAccelerator | head -40"
sh_ "ioreg -lw0 -r -c IOFramebuffer | grep -E '\\\"IOClass\\\"|\\\"model\\\"|\\\"IOAccelerator\\\"|AAPL,ig-platform-id|IOGVACodec|MetalPluginName' | head -60"
sh_ "ioreg -lw0 | grep -i -E 'AGDP|MetalPluginName|IOAccelerator' | head -40"

sec "4. OCLP 补丁记录(最关键:它记着 OCLP 到底给这台机器打了哪些补丁)"
sh_ "ls -l /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist"
sh_ "plutil -p /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist"
sh_ "ls -l /Users/Shared/.com.dortania.opencore-legacy-patcher.plist; plutil -p /Users/Shared/.com.dortania.opencore-legacy-patcher.plist 2>/dev/null | head -40"
sh_ "defaults read /Applications/OpenCore-Patcher.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null; ls -d /Applications/OpenCore-Patcher.app 2>/dev/null"

sec "5. 补丁实体:系统卷上到底有没有这些文件"
sh_ "ls -ld /System/Library/Extensions/AppleIntelHD4000Graphics.kext /System/Library/Extensions/AppleIntelFramebufferCapri.kext /System/Library/Extensions/AppleIntelIVBVA.bundle /System/Library/Extensions/AppleIntelGraphicsShared.bundle"
sh_ "ls -ld /System/Library/Extensions/AppleIntelHD4000Graphics*.bundle"
sh_ "for k in AppleIntelHD4000Graphics.kext AppleIntelFramebufferCapri.kext; do printf '%s -> ' \$k; defaults read /System/Library/Extensions/\$k/Contents/Info CFBundleVersion 2>/dev/null || echo '(读不到)'; done"
sh_ "ls -l /System/Library/Extensions | grep -i -E 'HD4000|Capri|IVBVA|GraphicsShared'"
sh_ "ls -l /System/Library/PrivateFrameworks/MTLCompiler.framework/Versions 2>/dev/null | head"
sh_ "ls -l /System/Library/PrivateFrameworks/GPUCompiler.framework/Versions 2>/dev/null | head"
sh_ "ls -l /System/Library/PrivateFrameworks/GPUCompiler.framework/Versions/*/Libraries/lib/clang 2>/dev/null | head -20"
sh_ "ls -l /System/Library/PrivateFrameworks/MTLCompiler.framework/Versions/Current 2>/dev/null"
sh_ "ls -l /Library/Application\\ Support/Dortania 2>/dev/null | head"
sh_ "echo '-- Ventura+ 上 IVB 显卡走 AuxKC:/Library/Extensions 才是关键 --'"
sh_ "ls -l /Library/Extensions"
sh_ "for k in AppleIntelHD4000Graphics.kext AppleIntelFramebufferCapri.kext; do echo \"== \$k\"; ls -l /Library/Extensions/\$k/Contents/ 2>&1; defaults read /Library/Extensions/\$k/Contents/Info OSBundleRequired 2>&1; done"

sec "6. 内核集合 / 加载状态"
sh_ "kextstat | grep -i -E 'HD4000|Capri|IOAccelerator|AMFIPass|Lilu|WhateverGreen|AppleIntelCPUPower|Brcm|itlwm'"
sh_ "kextstat | wc -l"
sh_ "echo '-- AuxKC 里到底装了哪些 kext --'"
sh_ "strings /Library/KernelCollections/AuxiliaryKernelExtensions.kc | grep -i -E 'AppleIntelHD4000|AppleIntelFramebufferCapri|AppleIntelIVB|IOAccelerator' | sort -u"
sh_ "$SUDO kmutil inspect /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>&1 | grep -iE 'Bundle|Kext ' | head -30"
sh_ "$SUDO kmutil inspect -c /Library/KernelCollections/AuxiliaryKernelExtensions.kc 2>&1 | grep -iE 'Bundle|Kext ' | head -10"
sh_ "echo '-- BootKC / SystemKC 里有没有(EFI 注入的版本会出现在 BootKC) --'"
sh_ "ls -l /System/Library/KernelCollections/ 2>/dev/null"
sh_ "strings /System/Library/KernelCollections/BootKernelExtensions.kc 2>/dev/null | grep -i -E 'AppleIntelHD4000|AppleIntelFramebufferCapri' | sort -u | head -10"
sh_ "for k in AppleIntelHD4000Graphics AppleIntelFramebufferCapri; do echo \"== \$k\"; codesign -dvvv /Library/Extensions/\$k.kext 2>&1 | tail -4; codesign -v /Library/Extensions/\$k.kext; echo \"verify exit=\$?\"; done"
sh_ "$SUDO dmesg | grep -i -E 'HD4000|Capri|kext' | tail -30"
sh_ "ls -l /Library/KernelCollections/"
sh_ "$SUDO kmutil log show --last boot 2>/dev/null | tail -60"

sec "7. SIP / NVRAM / 安全启动 / FileVault"
sh_ "csrutil status"
sh_ "nvram -p"
sh_ "nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:OCLP-Settings 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:revpatch 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:revblock 7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args 7C436110-AB2A-4BBB-A880-FE41995C9F82:csr-active-config 94b73556-2197-4702-82a8-3e1337dafbfb:AppleSecureBootPolicy 2>/dev/null"
sh_ "$SUDO fdesetup status"
sh_ "defaults read /Library/Preferences/com.apple.CoreDisplay 2>/dev/null"

sec "8. 电源管理"
sh_ "sysctl machdep.xcpm.mode"
sh_ "kextstat | grep -i -E 'CPU|SMC'"
sh_ "pmset -g"

sec "9. 系统日志里的图形报错(最后 150 行;这段要跑几十秒)"
sh_ "$SUDO log show --last boot --style compact --predicate 'senderImagePath CONTAINS \"AppleIntelHD4000\" OR eventMessage CONTAINS \"MTLCompiler\" OR eventMessage CONTAINS \"IOAccelerator\"' 2>/dev/null | tail -150"
sh_ "echo '-- MTLCompilerService 崩溃记录 --'; ls -lt $HOME/Library/Logs/DiagnosticReports 2>/dev/null | head -15"
sh_ "$SUDO log show --last boot --info --debug --predicate 'eventMessage CONTAINS \"AppleIntelHD4000\" OR eventMessage CONTAINS \"AuxKC\" OR eventMessage CONTAINS \"auxiliary\" OR eventMessage CONTAINS \"IOAcceleratorFamily\"' 2>/dev/null | grep -v 'draining messages' | tail -80"

sec "10. 根卷在哪(判断系统盘是内置 SATA 还是 USB)"
sh_ "diskutil info / | grep -E 'Device Node|Protocol|Mounted|Volume Name|File System'"
sh_ "diskutil list"

sec "11. 无线 / 蓝牙(顺带)"
sh_ "system_profiler SPAirPortDataType | head -50"
sh_ "$SUDO system_profiler SPBluetoothDataType | head -40"
sh_ "ls -l /System/Library/Extensions | grep -i -E 'itlwm|AirportItlwm|Brcm|BlueTool'"

sec "12. OCLP 应用日志"
sh_ "ls -lt $HOME/Library/Logs/Dortania 2>/dev/null | head"
LOG1="$(ls -t "$HOME/Library/Logs/Dortania"/OpenCore-Patcher*.log 2>/dev/null | head -1)"
LOG2="$(ls -t "$HOME/Library/Logs/Dortania"/OpenCore-Patcher*.log 2>/dev/null | sed -n 2p)"
if [ -n "${LOG1:-}" ]; then sh_ "tail -n 800 '$LOG1'"; fi
if [ -n "${LOG2:-}" ]; then sh_ "tail -n 300 '$LOG2'"; fi
sh_ "echo '-- 自动补丁(auto patcher)会跳过,要看真正手动跑的那次;找带 AuxKC 关键字的日志 --'"
PATCHLOG="$(grep -ls 'Adding AuxKC support\|Building new Auxiliary Kernel Collection' "$HOME/Library/Logs/Dortania"/*.log 2>/dev/null | tail -1)"
if [ -n "${PATCHLOG:-}" ]; then
  sh_ "echo 打补丁日志: '$PATCHLOG'"
  sh_ "tail -n 400 '$PATCHLOG'"
else
  printf '\n(没找到含 AuxKC 关键字的补丁日志)\n' >>"$OUT"
fi
sh_ "echo '-- 关键行 --'; grep -h -E 'Adding AuxKC support|Building new Auxiliary|Forcing Auxiliary|requires authentication|Merging GPUCompiler|Failed|error' "$HOME/Library/Logs/Dortania"/*.log 2>/dev/null | tail -40"

sec "13. 完成"
sh_ "echo 收集完成; ls -lh '$OUT'"

printf '\n\n========== 完成 ==========\n文件: %s\n大小: %s\n\n把整个文件发给我就行。\n' "$OUT" "$(ls -lh "$OUT" | awk '{print $5}')"
