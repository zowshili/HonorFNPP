# HonorFNPP

[English](README.en.md) | **简体中文**

让 HONOR MagicBook 在 Linux 下的 **Fn+P 性能模式**真正可用：Fn+P 一键在
智能（较低功率）/ 高能（高功率）之间切换，并弹出桌面通知（支持 GNOME/KDE/Deepin）。

> 已在 **HONOR MagicBook X 14 Pro（FRI-HXX，Ryzen 7 7840HS，BIOS 1.15）**、
> Debian 13、内核 7.2.6 上验证。其他 MagicBook 型号请先运行 `check`

## 问题

荣耀的笔记型电脑上，Fn+P 由 EC 处理。按下后 EC 自己会把性能位 `TUBF`（EC 偏移 `0xDC` bit0）
置 0/1，但 Linux 侧不会自动调整 ACPI `platform_profile`

实测在MagicBook X 14 Pro上，**两个开关必须同时满足**才有 45W：

| EC TUBF | ACPI platform_profile | 持续包功耗 |
|---|---|---|
| 0 | balanced | 35 W |
| 0 | performance | 35 W |
| 1 | balanced | 35 W |
| 1 | **performance** | **45 W** |

所以：

- 只按 Fn+P：EC 切了，OS 仍为 balanced → 35W，无法成功
- 只在 GNOME 里选“性能”：OS 切了，EC 仍是 0 → 35W，仍然无法成功
- 网络上部分“装 power-profiles-daemon 就能切性能”的说法实际上不成立

## 它做了什么

一个用户态 daemon，双向同步两个开关：

1. 轮询 EC `0xDC`，发现 Fn+P 改变了 `TUBF` → 设置
   `power-profiles-daemon` 的 `performance` / `balanced`。
2. 反向同步：在 GNOME 或 `powerprofilesctl` 里切“性能” → 通过 ACPI
   `STUB` 把 EC `TUBF` 置 1。

EC 读写路径：

- 读：`/sys/kernel/debug/ec/ec0/io` 偏移 `0xDC`（只读 1 字节）。
- 写：`acpi_call` → `\_SB.WMI1.WMAA 0 1 b040f01...`
  （group `0x04`, command `0x0f`）。

不改 DSDT、不刷 BIOS、不改内核。唯一的内核侧依赖是 `acpi_call`（DKMS），
用于写 EC；即使它失效，Fn+P 的 EC→PPD 方向仍然工作。

## 桌面支持

模式切换与桌面环境无关，而通知会按桌面环境自动选择，使用各自的原生/标准接口
 - 支持 **GNOME** / **KDE Plasma 5/6** / **Deepin DDE**
 - 测试通知功能：

```bash
sudo honorfnpp notify-test
```

## 安装

依赖（Debian/Ubuntu）：

```bash
sudo apt install python3 acpi-call-dkms power-profiles-daemon libnotify-bin
```

安装：

```bash
git clone <your-repo-url> HonorFNPP
cd HonorFNPP
sudo ./install.sh
# 或者自动装依赖：
sudo ./install.sh --with-deps
```

检查：

```bash
sudo honorfnpp check
sudo honorfnpp status
```

## 使用

```bash
sudo honorfnpp status      # EC / GTUB / platform_profile / PPD / AC / 电量
sudo honorfnpp on          # 高能模式 45W
sudo honorfnpp off         # 智能模式 35W
sudo honorfnpp toggle
sudo honorfnpp status --json
sudo honorfnpp notify-test   # 测试当前桌面的通知/OSD
```

- 按 **Fn+P**：自动切换并弹出通知
- GNOME/KDE/Deepin 的电源模式：也会和 Fn+P 双向同步
- 服务：`systemctl status honorfnpp`，
  日志：`journalctl -u honorfnpp -f`。

## 卸载

```bash
sudo ./uninstall.sh
# 连同 /etc/honorfnpp.conf：
sudo ./uninstall.sh --purge
```

## 支持新机型（欢迎 PR）

硬件差异存于 `devices/*.json`，新增机型无需改 Python 代码：

1. 按 [`docs/adding-device.md`](docs/adding-device.md) 收集 DMI、EC 偏移、
   `WMAA`/`GTUB`/`STUB`。
2. 复制模板：
   ```bash
   cp devices/_template.json devices/<id>.json
   ```
3. 校验：
   ```bash
   python3 tools/validate_devices.py devices
   ```
4. 在本机测试：
   ```bash
   sudo HONORFNPP_DEVICE_PROFILE="$PWD/devices/<id>.json" ./bin/honorfnpp check
   ```
5. 按 PR 模板提交：需要 `check` 输出、DSDT 片段、以及（`verified` 时）
   实测数据。

状态先写 `experimental`，实机验证后改 `verified`。详见
[`CONTRIBUTING.md`](CONTRIBUTING.md)、[`devices/README.md`](devices/README.md)。


## 参考

- [Wintego/Honor-PC-Helper](https://github.com/Wintego/Honor-PC-Helper)
- [aymanbagabas/Huawei-WMI](https://github.com/aymanbagabas/Huawei-WMI)
- [colorcube/Linux-on-Honor-Magicbook-14-Pro](https://github.com/colorcube/Linux-on-Honor-Magicbook-14-Pro)

## License

MIT
