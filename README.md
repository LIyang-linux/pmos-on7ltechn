# postmarketOS 移植：Samsung Galaxy On7（SM-G6000 / on7ltechn）

Samsung Galaxy On7 国行版（SM-G6000 / `on7ltechn`，MSM8916）的 postmarketOS
设备包、内核补丁与 CI。独立的仓库，与 LineageOS 的移植分开维护。

上游已有同代 On7 的移植，但**已归档**：`device/archived/device-samsung-on7`（分类 archived，
最后依赖主线内核 `linux-postmarketos-qcom-msm8916`）。本包以它为基线，只做机型差异。

- 上游设备页（重定向后）: <https://wiki.postmarketos.org/wiki/Samsung_Galaxy_On7_(2015)_(samsung-on7)>
- 上游设备包: `pmaports/device/archived/device-samsung-on7`（dtb 为 `qcom/msm8916-samsung-on7`）
- 主线内核: <https://github.com/msm8916-mainline/linux>

## 目录结构

```
.
├── device-samsung-on7ltechn/   # 设备包（APKBUILD + deviceinfo + modules-initfs）
├── kernel-patches/             # 主线内核补丁（面板驱动变体 + on7 显示/触摸 dts）
├── scripts/inject-kernel-patches.py
├── build-local.sh              # 本地构建脚本（WSL / Linux）
├── docs/
│   ├── hardware-notes.md       # 从原厂 DTS 提取的面板/触摸/GPIO 事实
│   ├── bringup-display.md      # 第一步：验证显示与初始化
│   └── dts/o7lte-chn-rev03-zt7548.dts   # 原厂下游 DTS（G6000 rev03）
└── .github/workflows/build-pmos.yml     # "校验打包" + "构建镜像（实验性）" 两个 job
```

## 现状

| 组件 | 上游 `samsung-on7` | 本机型（G6000） | 说明 |
|---|---|---|---|
| 显示 | ✅ 工作 | 待验证 | S6D7AA0X62 / ILI9881C 面板，亮度有噪点（上游已知） |
| 触摸 | ⚠️ 需测试 | **待修** | Zinitix ZT7548，上游驱动未合入主线，i2c 0x20 / irq 13 |
| WiFi | ✅ 工作 | 待验证 | 依赖 `firmware-samsung-on7-wcnss-nv` |
| 调制解调器（通话/短信/数据） | ❌ 未实现 | **待做** | 主线内核无高通 modem 支持，工作量最大 |
| GPS | ❌ 未实现 | **待做** | 依赖 modem/gnss 子系统 |
| 电池 / 充电 | ⚠️ 部分 | **待做** | SM5703 MUIC 已可用，电量计需确认 |
| 音频 | ⚠️ 部分 | **待做** | 需补 wcd 音频路由与 UCM 配置 |
| 相机 | ❌ 未实现 | **待做** | 主线无相机驱动 |
| 加速度计 | ❌ 未实现 | **待做** | 需确认型号并写 IIO 驱动/设备树 |
| FDE（全盘加密） | ❌ 未实现 | **待做** | pmOS 的 FDE 依赖可用的 boot 分区方案 |
| 引导 | lk2nd | **待做** | 需先刷 lk2nd，再 fastboot 刷 boot.img |

## TODO

按投入产出排序。**当前只做第 0 步**，其余等基线出来再排。

0. [ ] **验证显示与初始化**（详见 `docs/bringup-display.md`）
       - 用上游 `qcom/msm8916-samsung-on7` dtb 直接启动
       - 判据：`card0-DSI-1` 为 `connected`、背光节点存在、XFCE 能进桌面
       - 原厂 DTS 已核对：面板 S6D7AA0X62 / ILI9881C、触摸 ZT7548 与上游完全一致
1. [ ] 触摸：把 Zinitix ZT7548 驱动编译进内核，确认 `i2c@78b9000` 地址 0x20 能识别
2. [ ] 电池：确认电量计型号，补 `power_supply` 节点，保证能显示电量、能充电
3. [ ] 音频：补 WCD 音频路由，写 UCM
4. [ ] 加速度计：确认型号（BMI160 / K2HH）
5. [ ] GPS：需 modem 侧配合，难度高
6. [ ] 调制解调器：主线无 hexagon modem 方案，短期不可行
7. [ ] 相机：需要 VFE/CSI 与 sensor 驱动，工作量最大
8. [ ] FDE：先确认 boot 分区能容纳 initramfs

## 本地构建

```bash
# 依赖：Linux 或 WSL2，python3、git、openssl、psutils
# 2024-10 起 pmOS 迁移到 gitlab.postmarketos.org
git clone https://gitlab.postmarketos.org/postmarketOS/pmbootstrap
cd pmbootstrap
./pmbootstrap.py init          # Vendor: samsung / Device: on7ltechn / UI: xfce4
./pmbootstrap.py build device-samsung-on7ltechn
./pmbootstrap.py install --password 147147
```

首次需要把本目录的 `device-samsung-on7ltechn` 放进 aports 的 `device/testing/` 下：

```bash
cp -r device-samsung-on7ltechn "$(./pmbootstrap.py config aports)/device/testing/"
./pmbootstrap.py index
```

## CI

`.github/workflows/build-pmos.yml` 两个 job：

| job | 是否阻塞 | 内容 |
|---|---|---|
| `package` | 是 | 校验 `deviceinfo` 关键字段、把设备包打成 artifact |
| `build` | 否（`continue-on-error`） | maximize-build-space → 依赖 → swap 检测 → 拉 pmbootstrap/pmaports → 注入设备包 → `config` 写入设备/UI（非交互）→ `install --password 147147`（不加 `--split`，内核要留在 `/boot` 供 lk2nd 引导）→ 收镜像 → 失败时导出日志 |

`build` 目前是**实验性**的。pmbootstrap 3.x 的 `init` 只有交互模式，且提示词与提问顺序
随版本变化（`Work path` 在无默认值时甚至不带方括号，无法稳定匹配），因此改为**直接写配置文件**
`~/.config/pmbootstrap_v3.cfg`（标准 INI，键名取自 `pmbootstrap config` 的合法项），
并给 `work` 目录写入版本号 `8`。

## 与 LineageOS 14.1 的关系

两个仓库完全独立：

- `lineage-on7ltechn`：Android 7.1.2，日常可用（单卡、通话、短信已通）
- 本仓库：postmarketOS 主线内核，目标“能亮、能用 WiFi”，**短期不具备通话能力**

不建议在 pmOS 尚未跑通显示/触摸前投入 modem 相关工作——投入产出比远低于把 14.1 收尾。
