#!/bin/bash
# X230 黑苹果:工作区 EFI <-> ESP 校验/拷贝
#   ./efi-sync.sh status              打印工作区 EFI 的指纹与状态
#   ./efi-sync.sh check  <ESP挂载点>  对比工作区与 ESP(只读)
#   ./efi-sync.sh push   <ESP挂载点>  工作区 -> ESP(先备份+预览,再覆盖+回读校验)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WS="$ROOT/EFI"
ESP="${2:-}"; ESP="${ESP%/}"
# 保护:这些目录不属于我们,不拷也不删(防误伤 Windows/Linux 引导)
PROTECT=(--exclude=Microsoft --exclude=APPLE --exclude=ubuntu --exclude=fedora --exclude=debian --exclude=systemd)
KEYFILES=(OC/config.plist OC/OpenCore.efi BOOT/BOOTx64.efi)

hash_of(){ [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1 || echo "(缺失)"; }

usage(){ echo "用法: $0 {status|check|push} <ESP挂载点>"; }

status(){
  echo "== 工作区 EFI(权威) =="
  echo "路径    : $WS"
  echo "config  : $(stat -c '%y' "$WS/OC/config.plist" 2>/dev/null | cut -d. -f1)"
  echo "sha256  : $(hash_of "$WS/OC/config.plist")"
  python3 - "$WS/OC/config.plist" <<'PY'
import plistlib, sys, fnmatch
p = plistlib.load(open(sys.argv[1], 'rb'))
print("补丁     :", len(p['Kernel'].get('Patch', [])), "条 Kernel/Patch")
print("kext     :", sum(1 for k in p['Kernel']['Add'] if k.get('Enabled')), "启用 /",
      sum(1 for k in p['Kernel']['Add'] if not k.get('Enabled')), "关闭")
g = p['PlatformInfo']['Generic']
print("SMBIOS   :", g['SystemProductName'], g['SystemSerialNumber'])
print("boot-args:", p['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']['boot-args'])
n = p['NVRAM']['Add'].get('4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102', {})
print("NVRAM    :", "rtc-blacklist=%d 字节" % len(n.get('rtc-blacklist') or b''),
      "| SecureBootModel:", p['Misc']['Security']['SecureBootModel'])

def _v(s):
    """内核版本串 -> 可比较的整数元组(不能用字符串比:'12.0.0' > '20.0.0')"""
    try:
        return tuple(int(x) for x in str(s).split('.'))
    except ValueError:
        return ()

def applies(k, ver):
    """这条 kext 在给定内核版本(如 22.0.0)下会不会加载"""
    if not k.get('Enabled'):
        return False
    mn, mx = _v(k.get('MinKernel') or ''), _v(k.get('MaxKernel') or '')
    v = _v(ver)
    if mn and v < mn:
        return False
    if mx and v > mx:
        return False
    return True

wanted = ['AirportItlwm_BigSur.kext', 'AirportItlwm_Ventura.kext', 'itlwm.kext',
          'BrcmPatchRAM3.kext', 'BlueToolFixup.kext',
          'AppleIntelCPUPowerManagement.kext', 'RestrictEvents.kext',
          'AppleIntelFramebufferCapri.kext', 'AppleIntelHD4000Graphics.kext']
osmap = [('11', '20.0.0'), ('12', '21.0.0'), ('13', '22.0.0'), ('14', '23.0.0'), ('15', '24.0.0')]
print("版本切档 :  (按 Kernel/Add 的 Min/MaxKernel 推算)")
for name, ver in osmap:
    on = [k['BundlePath'] for k in p['Kernel']['Add']
          if k['BundlePath'] in wanted and applies(k, ver)]
    print("   macOS %-2s -> %s" % (name, ", ".join(on) if on else "(无)"))
PY
}

case "${1:-}" in
  status) status ;;
  check|push)
    [ -n "$ESP" ] || { usage; exit 1; }
    [ -f "$ESP/EFI/OC/config.plist" ] || { echo "错误: $ESP/EFI/OC/config.plist 不存在 —— ESP 挂载点给错了?"; exit 1; }
    ws=$(hash_of "$WS/OC/config.plist"); es=$(hash_of "$ESP/EFI/OC/config.plist")
    echo "工作区 sha256: $ws"
    echo "ESP    sha256: $es"
    if [ "$ws" = "$es" ]; then echo "结果: ✔ 一致,ESP 已是最新"; else echo "结果: ✘ 不一致(以工作区为准)"; fi
    [ "$1" = check ] && exit 0
    [ "$ws" = "$es" ] && { echo "无需拷贝。"; exit 0; }

    ts=$(date +%Y%m%d-%H%M%S); bk="$ESP/EFI-Backups/$ts"
    mkdir -p "$bk/OC" "$bk/BOOT"
    for f in "${KEYFILES[@]}"; do [ -f "$ESP/EFI/$f" ] && cp -a "$ESP/EFI/$f" "$bk/$f"; done
    echo "已把 ESP 上的关键文件备份到: $bk"

    echo "-- 预览(即将发生的变化,- 删除 / f 覆盖 / > 新增) --"
    rsync -a --delete --dry-run --itemize-changes "${PROTECT[@]}" "$WS/" "$ESP/EFI/" | sed 's/^/   /'

    echo "-- 开始覆盖 --"
    rsync -a --delete --itemize-changes "${PROTECT[@]}" "$WS/" "$ESP/EFI/" | sed 's/^/   /'

    echo "-- 回读校验 --"
    ok=1
    for f in "${KEYFILES[@]}"; do
      a=$(hash_of "$WS/$f"); b=$(hash_of "$ESP/EFI/$f")
      if [ "$a" = "$b" ]; then echo "   ✔ $f"; else echo "   ✘ $f 不一致"; ok=0; fi
    done
    echo "文件数: 工作区 $(find "$WS" -type f | wc -l) / ESP $(find "$ESP/EFI" -type f | wc -l)"
    [ "$ok" = 1 ] && echo "完成:ESP 已更新为工作区版本。" || echo "!! 校验失败,请检查。"
    ;;
  *) usage; exit 1 ;;
esac
