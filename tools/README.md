# tools/

## `efi-sync.sh`

工作区 `EFI/` ↔ ESP 的校验与拷贝。**方向永远只有 仓库 → ESP。**

```bash
./tools/efi-sync.sh status                 # 打印 EFI 指纹:补丁数、kext 数、三码、boot-args
./tools/efi-sync.sh check  /Volumes/EFI    # 只读对比仓库与 ESP(sha256)
./tools/efi-sync.sh push   /Volumes/EFI    # 备份 → 预览 → 覆盖 → 回读校验
```

`push` 会:

1. 把 ESP 上的 `OC/config.plist`、`OC/OpenCore.efi`、`BOOT/BOOTx64.efi`
   备份到 `<ESP>/EFI-Backups/<时间戳>/`;
2. 打印 `rsync --dry-run` 预览(哪些文件被删/覆盖/新增);
3. 覆盖,然后逐个回读 sha256 校验。

`Microsoft/ APPLE/ ubuntu/ fedora/ debian/ systemd/` 这些目录**不拷也不删**,
多系统机器上不会误伤别的引导。

> 脚本只管仓库根目录的 `EFI/`。往**安装 U 盘**拷的时候没有脚本,手动
> `cp -R` 到 U 盘的 EFI 分区即可(见 [`docs/安装指南.md`](../docs/安装指南.md) 1.3)。

## `ivb-check.sh`

在 **macOS 上**跑,**重启之后**用:一屏判定 Ivy Bridge(HD 4000)到底有没有真的加速。

```bash
bash tools/ivb-check.sh                 # 判定 + 存 ~/Desktop/ivb-check-<主机名>-<时间>.txt
bash tools/ivb-check.sh /Volumes/USB    # 也可以指定输出目录
```

默认只读:不改 EFI、不改系统卷、不改 NVRAM。只有在**有项没过**时,失败分支才会跑一次
`kextutil -v -t` —— 那一步等价于 `kmutil load`,只是把**磁盘上已有的** kext 再交给内核一次
(不写盘、不改配置),目的是把「开机起不来 / 加载后能起来」这两种病分开。

判定三条(对应 [`docs/OCLP.md`](../docs/OCLP.md) 8.5):

| # | 指标 | 通过的样子 |
|---|---|---|
| ① | `kextstat` 里的驱动 | `AppleIntelFramebufferCapri` 和 `AppleIntelHD4000Graphics` **两条都要在** |
| ② | `ioreg -lw0 -r -c IOAccelerator` | 有输出(实例数 > 0) |
| ③ | `system_profiler SPDisplaysDataType` | `Metal: Supported`(中文系统「Metal 支持: 是」,两种都认) |

每条打「通过 / 没过」,**退出码 0 = 三条全过、1 = 还有没过的**。
有没过时会自动把 `kextutil -v -t` 和内核日志(`log show`)也收进同一个文件 ——
直接把那一个文件发出来就够了,不用另外跑命令。

### 第 ④ 节:IOKit 匹配现场

「kext 进了内核、服务却没起来」时,唯一能说清原因的是 xnu 自己的匹配日志。它默认关着,
boot-args 末尾加两个开关(**只写日志,不改任何行为**):

```
io=0x1f                              # kIOLogAttach|Probe|Start|Register|Match
iokit_print_verbose_match_logs=1     # 按匹配类别列出候选和 probe 分数
```

`io=` 是 xnu 的 TUNABLE(xnu `iokit/IOKit/IOKitDebug.h`),发行版内核里照样生效,配合已经有的
`debug=0x100` 就能从 `log show` 里读到。开了之后第 ④ 节会收:`Registering:`、
`::attach`/`::probe`/`::start`、`match category`,外加 `ioclasscount` 和
「ACPI 里那块显卡叫 IGPU 还是 VID」。判读写在脚本输出里。**排完把这两个参数删掉。**

> 它和 `oclp-diag.sh` 的分工:这个只回答「好没好」,
> 那个是把整个现场(补丁记录、AuxKC/BootKC、NVRAM、SIP、电源管理)打包给 troubleshooting 用。

### 第 ⓔ 节:两处 30 s 超时的现场(面板 / ME(PAVP)/ 环)

①②③ 全过之后还有一类病:**kext 都在、`start()` 卡死**(现场是
`AppleIntelCapriController::start took 30173 ms` + `IntelAccelerator::start took 30001 ms`
→ `start ... failed`)。这一节按**驱动二进制里的原话关键字**捞内核日志,不按 kext 名捞:

```text
powering ON the panel!!          Timeout /GMBUS / Assertion failed
display event timeout on index    ring to go idle / stuck waiting
PAVP / MEClient / DRMStatus       MEIClient / HECI / AppleIntelMEI
```

顺带把 `AppleIntelMEIDriver` / `AppleMEClientController` 和 ACPI 里的 `IMEI|HECI`
节点、每次 `::start took ...` / `busy timeout` 一起收下来。**判读**:出现
`powering ON the panel` / `GMBUS` = 卡在点亮面板那一路;出现 `PAVP` / `MEClient` /
`DRMStatus` = 卡在 ME(PAVP)握手那一路;`AppleIntelMEIDriver` 不在 = MEI 设备压根
没露给 macOS。来龙去脉见 [`docs/踩坑记录.md`](../docs/踩坑记录.md) 第 16 条。

同一次运行里还会查一件事:**EFI 的 `Kernel -> Add` 那两个 IVB kext 到底注进去没有** ——
读 ESP 根目录最新的 `opencore-*.txt`,找 `Prelinked injection` 行。
**出现 `Invalid Parameter` 就是 OpenCore 没注进去**,那 12+ 上真正在跑的驱动只可能是
OCLP 留在 `/Library/Extensions` 的那两份(**别挪走**);
`kernelmanagerd` 那句 `Collision: replacing Kext ...` 是人工 `kextutil -t` 的产物,
不是「两份来源冲突」的证据。

## `ivb-now.sh`

在 **macOS 上**跑,**不用重启** —— 回答「此刻这一刻」加速器在不在,并且同一次运行里做
A/B 对照:

```bash
bash tools/ivb-now.sh                 # ① 先读一次 → ② 现场加载一次 → ③ 再读一次
bash tools/ivb-now.sh --ro            # 只读,只看现在什么样
bash tools/ivb-now.sh /Volumes/USB    # 指定输出目录
```

第 ② 步就是把 `kextutil -t`(`kmutil load`)在桌面上跑一次。为什么要 A/B:

| ① 现在 | ③ 加载后 | 说明 |
|---|---|---|
| 空 | 空 | 内核侧真的起不来 —— 查 `start()` 失败的原因 |
| 空 | 有 | 服务能起,只是**开机那次**没起来 → 时序/顺序问题,方向完全不同 |
| 有 | 有 | 内核侧是好的 —— 那 `Metal` 还不支持就说明是用户态那套(`Metal 3802` + `MTLDriver.bundle`) |

输出里还带 `WindowServer`(`Failed to create MetalDevice` / `Software compositor activated`)
和 `kernelmanagerd`(`Collision: replacing Kext` / `will start, will match`)的**带时间戳**原文 ——
光看最后一句会被开机那会儿骗。输出文件整体发出来就行。

## `ivb-snap.sh`

在 **macOS 上**跑,**不用重启、不用 sudo、不改任何东西** —— 最小版:就地看一眼
HD 4000 此刻到底有没有加速。就三条命令:

```bash
bash tools/ivb-snap.sh                 # 存一份 ~/Desktop/ivb-snap-<主机名>-<时间>.txt
bash tools/ivb-snap.sh /Volumes/USB    # 指定输出目录
```

```bash
ioreg -lw0 -r -c IntelAccelerator | head -30
ioreg -lw0 -r -c IOAccelerator | wc -l
system_profiler SPDisplaysDataType | grep -iE 'Metal|VRAM'
```

末尾附一行 `kextstat`(驱动进没进内核)和一句总判。想分清「开机那次起不来 / 现场加载能起来」
用 `ivb-now.sh`;想重启后一屏判定用 `ivb-check.sh`。

## `oclp-diag.sh`

在 **macOS 上**跑,把 OCLP / 显卡 / 加速相关的状态收成一个文本文件:

```bash
bash tools/oclp-diag.sh            # 输出到 ~/Desktop/oclp-diag-<主机名>-<时间>.txt
bash tools/oclp-diag.sh /Volumes/USB   # 也可以指定输出目录
```

只读:不改 EFI、不改系统卷、不改 NVRAM。需要 root 的项(内核集合、`log show`、
`kmutil log`)会先问一次 `sudo` 密码;拿不到就跳过那几项。

收的内容:系统与机型、`system_profiler SPDisplaysDataType`、IORegistry 里的
加速器 / 帧缓冲(含 `IOAccelerator` 实例数)、
`/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist`
(OCLP 自己记的补丁清单,最关键)、补丁实体文件(含 `/Library/Extensions`
那份 AuxKC 副本)、`kextstat`、AuxKC / BootKC 里到底装了哪些 kext、
`MTLCompilerService` 崩溃记录、SIP / NVRAM / 安全启动 / FileVault、电源管理、
图形相关系统日志、根卷挂在哪、以及**真正手动跑的那次 OCLP 补丁日志**
(自动补丁在 hackintosh 上会静默跳过,不能拿它当证据)。

要发给人看时,发这一个文件就够了。它为什么存在见
[`docs/OCLP.md`](../docs/OCLP.md) 第 5 节。

---

## 不随仓库附带的两个工具

`ocvalidate` 和 `macserial` 是 [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)
自带的命令行工具。本仓库**不附带二进制**(体积、以及"二进制该不该进 git"的问题),
需要时自己拿一份放到这里或放进 `PATH`:

| 工具 | 干什么 | 从哪来 |
|---|---|---|
| `ocvalidate` | 校验 `config.plist`。改完 config **必须**跑 | OpenCorePkg release 里的 `Utilities/ocvalidate`,或自己 `make` |
| `macserial` | 生成 SMBIOS 三码(SystemSerialNumber / MLB / SmUUID) | OpenCorePkg release 里的 `Utilities/macserial` |

```bash
# 用法示例(本仓库两份 config,改过哪份就验哪份)
ocvalidate EFI/OC/config.plist              # 日常版(蓝牙四件套开着)
ocvalidate EFI/OC/config-install.plist      # 装系统版(蓝牙四件套关着)
macserial -g MacBookPro9,2                  # 生成一组 9,2 的三码
```

Windows 上不想折腾命令行,可以用:

- [OCAT](https://github.com/ic005k/OCAuxiliaryTools) —— 图形界面,内置 config 校验和机型生成;
- [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) —— 专门生成三码。

> ⚠️ 用 OCAT 之类的 GUI 打开 `config.plist` 时,注意别让它「顺手」重写格式或升级配置,
> 那会动到本仓库精心调过的 NVRAM 键。改完一定 `diff` 一遍。

## 校验 ACPI

```bash
iasl -d EFI/OC/ACPI/SSDT-PNLF.aml      # 反编译成同名 .dsl
iasl -d docs/参考/硬件报告/ACPI/DSDT.aml
```

`iasl` 来自 [ACPICA](https://github.com/acpica/acpica)(Linux/macOS 都有包)。
