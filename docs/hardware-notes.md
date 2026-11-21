# 硬件事实记录（来自原厂下游 DTS）

来源：`o7lte-chn-rev03-zt7548.dts`（国行 SM-G6000，rev03），7713 行。

## 显示

| 项 | 下游 DTS 值 | 主线对应 |
|---|---|---|
| 面板 1 | `ss_dsi_panel_S6D7AA0X62_BV050HDM_HD` | `panel-samsung-s6d7aa0`（上游无此变体，由补丁 0002 新增） |
| 面板 2 | `ss_dsi_panel_ILI9881C_SKI550002_HD` | `panel-ilitek-ili9881c` |
| 分辨率 | 720 x 1280（0x2d0 x 0x500） | 同 |
| 模式 | `dsi_video_mode`，60fps | 同 |
| DSI 控制器 | `qcom,mdss_dsi@1a98000` | `dsi@1a98000` |
| PLL | `qcom,mdss_dsi_pll@1a98300` | `dsi_phy@1a98300` |
| 背光使能 | gpio 16 | 同 |
| 复位 | gpio 25 | 同 |

结论：**上游 `msm8916-samsung-on7.dts` 没有任何显示节点**（无 `&mdss`、无 DSI panel、无背光），
dtb 不能直接复用；显示链路要靠 `kernel-patches/0003` 补上，面板驱动变体由 `0002` 补上。

## 触摸

| 项 | 值 |
|---|---|
| 控制器 | Zinitix ZT7548 |
| compatible | `zinitix,zt7548_ts` |
| 总线 | i2c@78b9000（BLSP1 QUP5，即 `blsp_i2c5`） |
| 地址 | 0x20 |
| 中断 | gpio 13（补丁用 `IRQ_TYPE_EDGE_FALLING`） |
| 复位 | gpio 19（下游写作 scl-gpio，mainline 驱动不使用） |
| 唤醒 | gpio 18（下游写作 sda-gpio，mainline 驱动不使用） |
| 供电 | `avdd-supply` + `vddo-supply` |
| 上报分辨率 | 2880 x 5120（即 720x1280 的 4 倍单位） |
| 固件 | `zt7538_o7.fw`（下游放在 `/system/etc/firmware`） |
| 型号串 | `G600` |

主线驱动：`drivers/input/touchscreen/zinitix.c`（msm8916-mainline 分支，上游标注 “needs testing”）。

## 其它（待确认）

| 组件 | 下游线索 | 状态 |
|---|---|---|
| 电量计 | 未在本次 DTS 中确认 | 待查 |
| 加速度计 | 未在本次 DTS 中确认 | 待查 |
| 音频 | WCD 段存在，codec 配置未提取 | 待查 |
| 相机 | 未提取 | 待查 |

## 分区（实测）

| 分区 | 大小 | 来源 |
|---|---|---|
| `userdata`（`/dev/block/bootdevice/by-name/userdata`） | **12561.5 MB（12.26 GiB）** | 原厂 recovery 日志的挂载信息 |

注意 `BoardConfig.mk` 里的 `BOARD_USERDATAIMAGE_PARTITION_SIZE := 5016350720`
（≈4.67 GiB）**不是**分区大小，只是 AOSP 生成 `userdata.img` 时用的默认尺寸，
真实分区以上表为准。

刷 pmOS 时整盘镜像（`pmOS_boot` 256M + `pmOS_root`）必须略小于 12.26 GiB，
对应 `pmbootstrap` 配置 `boot_size = 256`、`extra_space = 10000`（约 11.6 GiB）。
