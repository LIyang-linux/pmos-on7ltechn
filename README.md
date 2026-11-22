# postmarketOS 移植：Samsung Galaxy On7（SM-G6000 / on7ltechn）

Samsung Galaxy On7 国行版（SM-G6000 / `on7ltechn`，MSM8916，2GB RAM）的 postmarketOS
设备包、内核补丁与 CI。与 LineageOS 的移植（`lineage-on7ltechn`）分开维护。

上游已有同代 On7 的移植，但**已归档**：`device/archived/device-samsung-on7`（最后依赖主线内核
`linux-postmarketos-qcom-msm8916`）。本包以它为基线，只做机型差异。

- 上游设备页: <https://wiki.postmarketos.org/wiki/Samsung_Galaxy_On7_(2015)_(samsung-on7)>
- 上游设备包: `pmaports/device/archived/device-samsung-on7`（dtb 为 `qcom/msm8916-samsung-on7`）
- 主线内核: <https://github.com/msm8916-mainline/linux>

## 目录结构

```
.
├── device-samsung-on7ltechn/   # 设备包（APKBUILD + deviceinfo + modules-initfs）
├── kernel-patches/             # 主线内核补丁
│   ├── 0002-drm-panel-s6d7aa0-add-bv050hdm.patch      # 面板驱动新增 BV050HDM 变体
│   ├── 0003-arm64-dts-qcom-on7-add-display-touch.patch # dtb 补 mdss/dsi/panel + 触摸节点
│   └── 0004-input-zinitix-add-zt7548.patch            # zinitix 驱动加 compatible
├── scripts/inject-kernel-patches.py   # 把补丁注册进 pmaports 的内核包
├── build-local.sh              # 本地构建脚本（WSL / Linux）
├── docs/
│   ├── hardware-notes.md       # 从原厂 DTS 提取的面板/触摸/GPIO 事实
│   ├── bringup-display.md      # 显示与初始化的验证步骤
│   └── dts/o7lte-chn-rev03-zt7548.dts   # 原厂下游 DTS（G6000 rev03）
└── .github/workflows/build-pmos.yml     # "校验打包" + "构建镜像" 两个 job
```

## 为什么需要内核补丁

上游 `msm8916-samsung-on7.dts` **没有任何显示节点**——没有 `&mdss`、没有 DSI panel、
没有背光。lk2nd 能显示（它自带下游面板驱动），但内核启动后 DSI 从不初始化，结果就是
只有背光、没有画面。这是第一次刷机的实际现象。

所以三个补丁缺一不可：

| 补丁 | 作用 |
|---|---|
| `0002` | 给 `panel-samsung-s6d7aa0` 增加 `samsung,s6d7aa0x62-bv050hdm` 变体：初始化序列、720×1280@60 时序、DCS 背光；probe 时把 `power`（PM8916 S4）拉到 2.1V |
| `0003` | dtb 里补 `&mdss`、`&mdss_dsi0` 的 panel 节点（reset gpio25、enable gpio16）、pinctrl，以及 `blsp_i2c5` 上的 Zinitix 触摸节点（irq gpio13、avdd gpio8、vddo L6） |
| `0004` | 给 `zinitix` 驱动补 `zinitix,zt7548` compatible（芯片本身与原厂 ZT7538 走同一套协议） |

面板型号来自 lk2nd 日志：`lcd_id=0x59b810` → `S6D7AA0X62 / BV050HDM`。

## 现状

| 组件 | 本机型（G6000） | 说明 |
|---|---|---|
| 引导（lk2nd） | ✅ 已通 | 通用 `lk2nd-msm8916.img`，自动识别 SM-G6000 |
| 系统启动 | ✅ 已通 | ext2 `/boot` + ext4 根分区，lk2nd 读取 `extlinux.conf` |
| 显示 | ✅ 已通 | 面板补丁（0002/0003）生效，画面与背光正常 |
| 触摸 | ✅ 已通 | ZT7548 init 序列补丁（0005）生效，实测触摸正常 |
| WiFi | 待验证 | 依赖 `firmware-samsung-on7-wcnss-nv`（源在 pastebin，偶发拉不到） |
| 电池 / 充电 | 待做 | SM5703 MUIC 可能已可用，电量计型号需确认 |
| 音频 | 待做 | 需补 WCD 音频路由与 UCM |
| 加速度计 | 待做 | 需确认型号并补 IIO 驱动/设备树 |
| GPS | 待做 | 依赖 modem/gnss 子系统 |
| 调制解调器 | 不可行 | 主线内核无高通 hexagon modem 方案 |
| 相机 | 待做 | 主线无相机驱动，需要 VFE/CSI + sensor，工作量最大 |
| FDE | 待做 | 依赖可用的 boot 分区方案 |

## 刷机

前提：先刷好 lk2nd，之后每次只需要刷 userdata。

```bash
# 首次（三星 Download 模式，用 heimdall；或 TWRP 里 Install Image 选 Boot）
heimdall flash --BOOT lk2nd-msm8916.img

# 之后每次更新系统：长按音量减进 lk2nd 的 fastboot
fastboot flash userdata samsung-on7ltechn.img
fastboot reboot
```

**不要刷 boot.img**：lk2nd 会从 userdata 的 ext2 启动分区读 `/extlinux/extlinux.conf`
并加载内核，整盘镜像里已经包含内核和 dtb。

镜像由 `img2simg` 转成 Android sparse 格式（`deviceinfo_flash_sparse="true"`），
文件看着 1.3G、逻辑大小约 11.6GiB。lk2nd 的 fastboot 原生支持 sparse；
**TWRP 的 Install Image / dd 不支持**，要走 TWRP 必须先 `simg2img` 转回 raw。

镜像内部分区：

| 分区 | 文件系统 | 内容 | 谁读它 |
|---|---|---|---|
| `pmOS_boot` | **ext2** | `extlinux/extlinux.conf`、内核、dtb、initramfs | lk2nd |
| `pmOS_root` | ext4 | 完整根文件系统（含 phosh） | 内核 |

lk2nd 用的是 LK 的 ext2 驱动，不认 ext4 的 extents，所以启动分区必须是 ext2，
且构建时不能加 `--split`（会把 `/boot` 拆成独立的 boot.img）。

## 本地构建

```bash
# 依赖：Linux 或 WSL2，python3、git、openssl
./build-local.sh          # 自动拉 pmbootstrap、注入设备包与内核补丁、装镜像
```

脚本会做：拉 pmbootstrap → 注入 `device-samsung-on7ltechn` 到 aports →
用 `scripts/inject-kernel-patches.py` 把补丁挂到主线内核包 → `index` → `build` → `install`。
输出在 pmbootstrap 的 work 目录 `images/` 下。

手动步骤等价于：

```bash
cp -r device-samsung-on7ltechn "$(./pmbootstrap.py config aports)/device/testing/"
python3 scripts/inject-kernel-patches.py \
  "$(find "$(./pmbootstrap.py config aports)" -maxdepth 3 -type d \
      -name 'linux-postmarketos-qcom-msm8916' | head -1)" kernel-patches
./pmbootstrap.py index
./pmbootstrap.py build device-samsung-on7ltechn
./pmbootstrap.py install --password 147147
```

## CI

`.github/workflows/build-pmos.yml`，push 到 `main` 触发，两个 job：

| job | 是否阻塞 | 内容 |
|---|---|---|
| `package` | 是 | 校验 `deviceinfo` 关键字段、校验 APKBUILD 的 `sha512sums`、打设备包 artifact |
| `build` | 否（`continue-on-error`） | 依赖 → swap 检测 → 拉 pmbootstrap/pmaports → 注入设备包 → 注入内核补丁并把 `CONFIG_DRM_PANEL_SAMSUNG_S6D7AA0` / `CONFIG_BACKLIGHT_CLASS_DEVICE` / `CONFIG_TOUCHSCREEN_ZINITIX` 强制为 `=y`（并同步 config 的 sha512）→ 编内核 → 编设备包 → `install` 出 sparse 整盘镜像 → 上传 `pmos-image-experimental` 与 `pmos-build-log` |

`build` 是**实验性**的。pmbootstrap 3.x 的 `init` 只有交互模式，提示词与顺序随版本变化，
因此改为直接写 `~/.config/pmbootstrap_v3.cfg` 并给 work 目录写版本号 `8`。

出问题先看 `pmos-build-log` 这个 artifact，里面是 chroot 的 `log.txt` 等日志。

## 调试（进系统后）

pmOS 默认启用 USB 网络（`172.16.42.1`）与 SSH：

```bash
sudo ip addr add 172.16.42.2/24 dev usb0
ssh user@172.16.42.1          # 默认密码 147147
```

### Windows 主机注意：别指望 adb

**pmOS 不运行 adbd**，`adb devices` 永远是空列表、`adb shell` 进不去——设计如此，不是故障。
initramfs 只提供三种 USB gadget：`network`、`mass_storage`、`ACM 串口`。

而 gadget 默认 VID:PID 是 `18D1:D001`（Google 家的 ID）。装了 Google USB Driver 的 Windows
会按 VID/PID 把这块**网卡**认成 “Android ADB Recovery Interface” 并绑到 WinUSB，于是设备
管理器里有个 ADB 设备，但既没有网卡也 ping 不通 `172.16.42.1`。本设备 deviceinfo 已覆盖为
`1d6b:0104` + 强制 `rndis.usb0` 规避此问题。

Windows 下：设备管理器应出现 “USB Ethernet/RNDIS Gadget”；给该网卡配静态 IP
`172.16.42.2/24`（不设网关）；然后 `ssh user@172.16.42.1`。

应急控制台：**开机时按住音量减（或左 Ctrl）**即进入 initramfs debug shell，此时 gadget
会切成 ACM 串口（initramfs 的 `check_keys` 逻辑），Windows 下出现一个 COM 口，PuTTY 以
115200 8N1 打开即可。注意这不是内核 cmdline 参数，没有 `pmos.debug-shell` 这种开关。

```bash
cat /sys/class/drm/card0-DSI-1/status   # 期望 connected
ls /sys/class/backlight/                # 期望有 s6d7aa0 背光节点
dmesg | grep -iE "dsi|panel|s6d7aa0"
dmesg | grep -iE "zinitix|i2c"
```

## 与 LineageOS 的关系

两个仓库完全独立：

- `lineage-on7ltechn`：Android 7.1.2，日常可用（单卡、通话、短信已通）
- 本仓库：postmarketOS 主线内核，屏幕与触摸均已可用，目标“能用 WiFi”，**短期不具备通话能力**
