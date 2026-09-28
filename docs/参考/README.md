# docs/参考/

这里只放**参考资料**,不是 EFI 的一部分,**不会被拷到 ESP**。

| 路径 | 是什么 | 来源 |
|---|---|---|
| `硬件报告/sysInfo.txt` | 本机(X230)在 Windows 下的硬件转储 | 本机跑 [RapidEFI](https://github.com/JeoJay127/RapidEFI-Tool) 导出 |
| `硬件报告/ACPI/` | 本机固件表转储,含 `DSDT.aml` 和反编译好的 `DSDT.dsl` | 本机导出 |
| `经典仓库笔记.md` | 对下面那个经典仓库两份 config 的对比笔记 | 见下 |
| `经典仓库-Install_USB-config.plist` | 该仓库「安装 U 盘版」config 的副本 | `banhbaoxamlan/X230-Hackintosh` |
| `经典仓库-正式EFI-config.plist` | 该仓库「日常版」config 的副本 | 同上 |
| `USB定制/SSDT-UIAC.dsl` | 本机 USB 端口地图的**可读存档**(ACPI 写法)。**未采用** —— 实测换上去内建设备会消失,见 `../USB定制.md` 第 6 节 | 本机 Hackintool 导出 |

> **本目录已脱敏。** 硬件报告里的计算机名、Windows 产品 ID、内存与磁盘序列号
> 都换成了 `(已移除)`;经典仓库那两份 config 副本里的 SMBIOS 字段是上游作者
> 自己用的占位值(`W00000000001` / `112233445566` 那套),不是真机序列号。
> 本仓库 EFI 里的三码同样是占位值,见 `AGENTS.md` 2.4。

## 两个灵感来源仓库

**[`banhbaoxamlan/X230-Hackintosh`](https://github.com/banhbaoxamlan/X230-Hackintosh)**

X230 最经典的仓库,面向的正是 Catalina / Big Sur / Monterey 世代。本仓库
「装系统阶段尽量少挂东西」的思路就是照它来的:两份 config 只差蓝牙三件套的开关,
安装阶段那份把蓝牙 kext 全关。它的 Install USB 版做得更极端——几乎不加载
自定义 ACPI 和蓝牙,这也解释了为什么装系统阶段要尽量少挂东西(`AGENTS.md` 3.2)。
它的两份 config 在这里留了副本,方便离线对照。

**[`zyq8888/X230-MAC-OpenCore`](https://github.com/zyq8888/X230-MAC-OpenCore)**

另一份 X230 EFI(i5-3320M / BCM94360HMB / SMBIOS `MacBookPro16,2`)。
本仓库**没有收录它的任何文件**——要看请去上游仓库。
它对我们唯一的价值是一个反面教材:几个 SSDT 的 `Scope` 指向了 X230 上不存在的设备
(`IGPU` / `LPCB` / `EC0`),`AGENTS.md` 3.4 节记了完整清单。

> 顺带一个可验证的结论:它的 `DSDT.aml` 与本机转储**逐字节相同**
> (sha256 `1c713428c…`)。同 BIOS 版本(`G2ETB7WW`)的 X230 之间 DSDT 可以互换,
> 但正因为一样,替换 DSDT 没有任何收益。

## 怎么用 DSDT

```bash
# .dsl 已经反编译好了,直接搜设备名
rg -n "Device \(VID\)|Device \(IGPU\)|Device \(LPC\)|Device \(LPCB\)|Device \(KBD\)|Device \(PS2K\)|Device \(EC\)|Device \(EC0\)" docs/参考/硬件报告/ACPI/DSDT.dsl
```

X230 上存在的是 `VID` / `LPC` / `KBD` / `EC`;不存在的是
`IGPU` / `LPCB` / `PS2K` / `EC0`。**改 SSDT 之前先对一遍这几个名字。**
