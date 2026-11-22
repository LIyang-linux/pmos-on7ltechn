# 第一步：验证显示与系统初始化

目标很窄：**能亮屏、能进 XFCE 桌面**。触摸、WiFi、音频等在拿到这个基线之后再谈。

## 为什么先做这一步

显示是唯一“不给任何软件反馈”的部件——屏幕不亮时，既没有日志也没有串口（除非焊 UART）。
所以先用最少的变量确认 DRM/DSI 链路和面板驱动是否正常，后面所有调试才有参照物。

按原厂 DTS 的比对结果（见 `hardware-notes.md`），国行 G6000 与上游 `samsung-on7`
的面板型号一致（lk2nd 日志实测 `ss_dsi_panel_S6D7AA0X62_BV050HDM_HD`，`lcd_id=0x59b810`）。

但**上游 `msm8916-samsung-on7.dts` 里没有任何显示节点**——没有 `&mdss`、
没有 `&mdss_dsi0` 的 panel、没有 backlight。第一次刷机的结果正是这个的必然表现：
lk2nd 的测试条能显示（它用自己的下游面板驱动），内核启动后 DSI 从未初始化，
于是只剩背光。

因此需要给内核打补丁（`kernel-patches/`）：

| 补丁 | 内容 |
|---|---|
| `0002-drm-panel-s6d7aa0-add-bv050hdm.patch` | 给 `panel-samsung-s6d7aa0` 增加 BV050HDM 变体（初始化序列取自原厂 DTS 的 `qcom,mdss-dsi-on-command`），并把 `power`（S4）设到 2.1V |
| `0003-arm64-dts-qcom-on7-add-display-touch.patch` | 给 on7 dtb 增加 `&mdss`、`&mdss_dsi0` panel 节点、reset/enable gpio、pinctrl，以及 `blsp_i2c5` 上的 Zinitix 触摸节点 |
| `0004-input-zinitix-add-zt7548.patch` | 给 `zinitix` 触摸驱动补上 `zinitix,zt7548` compatible |

CI 里由 `scripts/inject-kernel-patches.py` 把它们注册进 pmaports 的内核包
（写进 `source=` 与 `sha512sums=`，pkgrel+1），再单独 `pmbootstrap build` 该内核包。


## 步骤

### 1. 准备引导（只需做一次）

这一步**不能**用 fastboot —— 此阶段手机里还没有 lk2nd，三星原厂只提供 Download 模式。

```bash
# A. Download 模式 + heimdall
heimdall flash --BOOT lk2nd-msm8916.img
```

```
B. TWRP：Install → Install Image → lk2nd-msm8916.img → 选 Boot
   （别选 Recovery，会覆盖 TWRP）
```

镜像从 https://github.com/msm8916-mainline/lk2nd/releases 取 `lk2nd-msm8916.img`
（msm8916 通用，自动识别机型，支持列表含 SM-G6000）。

装好后重启，长按**音量减**进入 lk2nd 的 fastboot。

### 2. 刷 pmOS 根文件系统

```bash
# lk2nd 会去 userdata 里的 ext2 启动分区找 /extlinux/extlinux.conf，
# 所以只刷整盘镜像，不需要单独刷 kernel/boot.img。
fastboot flash userdata samsung-on7ltechn.img
fastboot reboot
```

镜像因为 `deviceinfo_flash_sparse="true"` 已被 `img2simg` 转成 Android sparse 格式：
文件名看着只有 1.3G，逻辑大小是 11864M。lk2nd 的 fastboot 原生支持
（`app/aboot/aboot.c` 里的 `cmd_flash_mmc_sparse_img`），直接刷即可。

⚠️ 反过来说，**TWRP 的 Install Image / dd 不能直接刷这个文件**，会把 sparse
头当成 raw 写坏分区表。要走 TWRP 必须先 `simg2img` 转成 raw。

**镜像内部布局（msdos 分区表，两个分区）**

| 分区 | 文件系统 | 内容 | 谁读它 |
|---|---|---|---|
| `pmOS_boot` | **ext2** | `extlinux/extlinux.conf`、内核、dtb、initramfs | lk2nd |
| `pmOS_root` | ext4 | 完整根文件系统（含 xfce4） | 内核 |

这条约束不能破：lk2nd 用的是 LK 的 ext2 驱动，只接受
`ro_compat = SPARSE_SUPER | LARGE_FILE` 的超级块，也不认 extents，
**挂不上 ext4**。而 pmbootstrap 给根分区默认格式化 ext4（`^metadata_csum`），
所以内核和 extlinux.conf 一旦落进根分区，lk2nd 就找不到系统。

对应两个已锁定的配置：

- `deviceinfo_boot_filesystem="ext2"`（deviceinfo 里显式写出，防止被改成 fat/ext4）；
- 构建时**不能**加 `--split` —— 加了会把 `/boot` 拆进独立 `boot.img`，
  整盘镜像里就没有 ext2 启动分区了。

### 3. 观察屏幕

| 现象 | 含义 | 下一步 |
|---|---|---|
| 出现 lk2nd 的 “Samsung Galaxy On7” 字样 | 引导正常，问题只在内核/面板 | 看第 4 步 |
| 亮屏但花屏/条纹 | DSI 时序或面板型号不匹配 | 需要新建 `on7ltechn.dts` 指定面板 |
| 全黑、无背光 | 内核没跑到 DRM，或面板未 probe | 看第 4 步 |
| 全黑但有背光 | 面板有电、没有画面输出 | 检查 `dsi_phy`/面板 compatible |
| 直接重启循环 | 内核 panic | 需要 UART 或 `earlycon` 日志 |

### 4. 无屏幕时如何拿日志

pmOS 默认启用 USB 网络（`172.16.42.1`）与 SSH，只要系统起来了就能进去：

```bash
# 电脑这边（Linux/macOS/WSL）
sudo ip addr add 172.16.42.2/24 dev usb0
ssh user@172.16.42.1          # 默认密码 147147
```

进去之后按顺序看：

```bash
# DRM/DSI 是否绑定成功
dmesg | grep -iE "drm|mdss|dsi|panel" | head -40
cat /sys/class/drm/card0-*/status       # 期望 connected

# 面板驱动是否 probe
dmesg | grep -iE "s6d7aa0|ili9881"

# 触摸（i2c 0x20 是否有设备）
i2cdetect -y 0 2>/dev/null || ls /sys/bus/i2c/devices/ | grep -i "0-0020"
dmesg | grep -iE "zinitix|zt7548"

# 背光
ls /sys/class/backlight/
cat /sys/class/backlight/*/max_brightness 2>/dev/null
```

### 5. XFCE

第一次进桌面会慢（约 30~60 秒），属于正常。判断“初始化正常”的最低标准：

- 能进 XFCE 桌面（或至少能 SSH 进去 `systemctl status` 无 failed 服务）
- `dmesg` 里没有 `msm_dsi` / `drm` 的 `-EPROBE_DEFER` 死循环

## 需要验证的四条命令（结果贴回）

```bash
cat /sys/class/drm/card0-DSI-1/status
ls /sys/class/backlight/
dmesg | grep -iE "dsi|panel" | tail -30
dmesg | grep -iE "zinitix|i2c" | tail -20
```

## 常见故障与对策

| 症状 | 可能原因 | 对策 |
|---|---|---|
| `card0-DSI-1` 状态是 `disconnected` | 面板 compatible 没匹配上 | 检查 `msm8916-samsung-on7.dts` 里面板节点，换 `ili9881c` 版本 |
| 有 DRM 无背光 | 背光 gpio 16 未配置 | 在 dts 的 `backlight` 节点确认 `enable-gpios &tlmm 16` |
| 触摸 `i2c 0x20` 无设备 | Zinitix 驱动未编译进内核 | 内核配置加 `CONFIG_TOUCHSCREEN_ZINITIX` |
| 触摸有设备但无事件 | 复位/唤醒 gpio 接反 | 对照 `hardware-notes.md`：复位 19、唤醒 18 |
| XFCE 起不来 | 内存不足（2GB + 桌面） | 换 `console` + `sway`/`phosh` 再试，或加 zram |
