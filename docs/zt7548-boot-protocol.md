# ZT7548 原厂启动协议逆向笔记

来源：原厂 boot.img（SM-G6000 CHN，Linux 3.10.49-6695642，2018-10-09 Samsung 构建）。

提取方法：bootimg → zImage → LZ4 legacy 帧（magic `0x184C2102` @0x1773，3 块）→ 内核
Image → vmlinux-to-elf 解出 kallsyms（112872 符号）→ capstone 反汇编。
工具脚本与产物在 `D:\DSH\boot-extract\`（Image、vmlinux.elf、反汇编文本、fw blob）。

后记：反汇编完成后在 LineageOS `android_kernel_samsung_msm8916`（cm-14.1）树里找到了
`zt7548_ts.c`/`zt7548_ts.h` 完整源码（`D:\DSH\stock-driver-src\`），本文所有结论已按
源码校对；反汇编与源码完全一致。

## 关键结论：主线触摸不亮的根因

**boot 序列主线和原厂其实一致**（0xC000=1 → cmd 0xC004 → 0xC002=1 → 0xC001=1，
主线 zinitix.c 363-401 行全都有；早先笔记里"主线缺两步"的说法是对照了错误版本，
已更正）。真正的差异在 **boot 之后的 init 段**，见下方差异表——由 patch 0005 修复。

## 原厂上电序列（zt7548_power_control，重试 4 次，每次间隔 200ms）

```c
pdata->power(1);                  // 稳压 + gpio（zt7548_power: vdd LDO 3.3V 设压 + enable）
for (retry = 0; retry < 4; retry++) {
    write_reg(0xC000, 1);
    usleep_range(...);
    read_data(...);               // 读 chip code（debug 打印）
    usleep_range(10);
    write_cmd(0xC004);            // ← 主线也有（"intn clear"）
    usleep_range(10);
    write_reg(0xC002, 1);         // ← 主线也有（"nvm init"）
    zinitix_delay(2);
    write_reg(0xC001, 1);         // program start
    if (ok) { msleep(150); return 0; }   // ← 主线只等 40ms，差在此
    msleep(200);
}
```

## 原厂初始化序列（mini_init_touch，input_open 时调用）

```c
read_data(0x12C) == 0x55AA        // boot 完成签名检查！不匹配则走完整 init_touch（含固件烧录）
write_cmd(0x0000);                // 软复位（"reset command"，主线用的是 reg 0x10=1，不同！）
write_reg(0x0186, 4);
write_reg(0x00B0, ts_data[0x54]);   // 值来自结构体（DT 解析，待定）
write_reg(0x0015, 5);
write_reg(0x0019, 1);
write_reg(0x0010, ts_data[0x158]);  // 值来自结构体（待定；若该值 != 1 则跳过下一条）
write_cmd(0x0006);
zt7548_set_ta_status();
zt7548_set_optional_mode(1);      // 内部: write_reg(0x0116, cal_mode 相关值)
write_reg(0x00F0, ts_data[0x56]);
write_cmd(0x0003);
usleep_range(10) x10;
write_reg(0x007F, 100);           // "ZT7548_DELAY_RAW_FOR_HOST"
write_reg(0x00F1, 100);
esd_timer_start();
// 失败路径: power_control(0) → power_control(2) → init_touch(0)（全量初始化+固件）
```

## 固件

- 路径 `tsp_zinitix/zt7538_o7.fw`；request_firmware 失败时回退内核内嵌 blob
- 内嵌 blob 已提取: `_fw_tsp_zinitix_zt7538_o7_fw_bin` @0xC0BC2B58，45056 字节
  → 已存为 `D:\DSH\zt7538_o7.fw`（头 8 字节 `48 00 00 40 00 00 00 00`）
- 完整初始化（init_touch）仅在固件版本检查（ts_check_need_upgrade）失败时烧录
  （ts_upgrade_firmware → ts_hw_calibration）——mini_init 路径**不需要**固件下载
- 备用触摸方案: imagis IST3038C（`tsp_imagis/ist3038c_o7.fw`，另一批次机型）

## 与主线 zinitix.c 的差异汇总（patch 0005 修复项）

| 项 | 主线 (BT541) | 原厂 (ZT7548) | patch 0005 |
|---|---|---|---|
| boot 序列 | 0xC000/0xC004/0xC002/0xC001 | 相同 | 不改 |
| boot 后延时 | msleep(40) | **msleep(150)** | ✅ zt7548 走 150ms |
| boot 校验 | 无 | 读 0x12C == **0x55AA** | ✅ 已加（不符则 -EIO） |
| 软复位 | cmd 0x0000 | 相同 | 不改 |
| **分辨率扩展器** | 无此概念 | **0x186 = 4**（坐标 ×4 上报） | ✅ 已加 |
| X/Y 分辨率寄存器 | 写 prop.max_x/y | **从不写**（固件自算） | ✅ zt7548 跳过 |
| touch mode | 0x10 = 2 | **0x10 = 1**（TOUCH_POINT_MODE） | ✅ zt7548 默认 1 |
| optional setting | 无 | 0x116 = m_optional_mode（初值 0） | ✅ 写 0 |
| 软校准 | 无 | cmd 0x0006 | ✅ 已加 |
| ESD 周期中断 | 无 | 0xF1 = SCAN_RATE_HZ×INTERVAL = 100 | ✅ 已加 |
| 固件 | 不加载 | 版本不符时烧录 44KB fw | 暂不移植（mini_init 不需要） |

注意：固件路径 `tsp_zinitix/zt7538_o7.fw`；request_firmware 失败时回退内核内嵌 blob
（已提取: `D:\DSH\zt7538_o7.fw`，45056 字节）。mini_init 路径**不需要**固件下载。
备用触摸方案: imagis IST3038C（`ist3038c_o7.fw`，另一批次机型）。

## 验证清单（patch 0005 刷入后）

1. dmesg 无 "ZT7548 boot checksum mismatch" → boot 成功
2. `grep zinitix /proc/interrupts` 边摸边看计数
3. `evtest` 摸四角：坐标范围应到 2879/5119（0x186=4 生效，DT 的 size 2880/5120 正确）
4. 若 checksum mismatch → 芯片没完成 boot，需查供电时序或移植固件下载路径

## 结果：已验证可用（2026-11-21）

patch 0005 随镜像 `69466b5` 刷入真机（SM-G6000），**触摸正常工作**，
USB 网络（RNDIS）同时打通，SSH 登录、进桌面均正常。

关键修复点复核：
- boot 后 150ms 等待（原 40ms 不够，芯片未完成 boot 会导致后续全部失败）
- 0x186 分辨率扩展器 = 4（坐标 ×4，与 DT 的 2880×5120 对应）
- touch mode = 1（原强校验必须为 2）
- boot 校验 0x12C == 0x55AA、软校准 cmd 0x0006、ESD 周期 0xF1=100

未移植项（不影响手指触摸）：两个电容键（RECENT/BACK，0xB0=2 + icon 事件）、
TA 充电状态检测。
