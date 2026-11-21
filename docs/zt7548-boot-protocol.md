# ZT7548 原厂启动协议逆向笔记

来源：原厂 boot.img（SM-G6000 CHN，Linux 3.10.49-6695642，2018-10-09 Samsung 构建）。

提取方法：bootimg → zImage → LZ4 legacy 帧（magic `0x184C2102` @0x1773，3 块）→ 内核
Image → vmlinux-to-elf 解出 kallsyms（112872 符号）→ capstone 反汇编。
工具脚本与产物在 `D:\DSH\boot-extract\`（Image、vmlinux.elf、反汇编文本、fw blob）。

## 关键结论：主线触摸不亮的根因

主线 `zinitix.c` 是按 BT541 协议写的；ZT7548 的 boot 协议和寄存器语义都不同。
原厂 `zt7548_ts.c`（编在原厂内核里）的流程与之有实质差异，芯片大概率卡在
boot/handshake 阶段（I2C 写会被 ACK，所以 dmesg 可能完全安静）。

## 原厂上电序列（zt7548_power_control，重试 4 次，每次间隔 200ms）

```c
pdata->power(1);                  // 稳压 + gpio（zt7548_power: vdd LDO 3.3V 设压 + enable）
for (retry = 0; retry < 4; retry++) {
    write_reg(0xC000, 1);         // ✓ 主线有
    usleep_range(...);
    read_data(...);               // 读 chip code（仅 debug 打印 "chip code = 0x%x"）
    usleep_range(10);
    write_cmd(0xC004);            // ✗ 主线缺失！2 字节裸写（不带寄存器地址）
    usleep_range(10);
    write_reg(0xC002, 1);         // ✗ 主线缺失！
    zinitix_delay(2);             // ~2ms
    write_reg(0xC001, 1);         // ✓ 主线有（program start）
    if (ok) { msleep(150); return 0; }
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

## 与主线 zinitix.c 的差异汇总

| 项 | 主线 (BT541) | 原厂 (ZT7548) |
|---|---|---|
| boot | 0xC000=1 → 0xC001=1 → msleep(50) | 0xC000=1 → **cmd 0xC004** → **0xC002=1** → 0xC001=1 → msleep(150)，重试 4 次 |
| boot 校验 | 读 0xF0 版本号 | 读 0x12C == 0x55AA |
| 软复位 | write 0x0010 = 1 | write_cmd(0x0000)（裸写） |
| touch mode | write 0x0100 = 2 | 一套完全不同的寄存器（0x186/0xB0/0x15/0x19/0x10/0x116/0xF0/0xF1/0x7F） |
| 固件 | 不加载 | 版本不符时烧录 44KB fw |

## 修复计划（patch 0005）

1. 第一步（最小改动）: 在 `zinitix_send_power_on_sequence` 的 zt7548 分支补上
   `write_cmd(0xC004)`（2 字节裸写）和 `write_reg(0xC002, 1)`，msleep 150ms，重试 4 次
2. 上机验证：dmesg 看 chip code / 版本读取是否成功、`/proc/interrupts` 是否有中断
3. 若 boot 成功但无事件 → 按 mini_init 序列改写 init 寄存器段
4. 若 0x12C != 0x55AA → 需要移植固件下载（ts_upgrade_firmware 协议，后续逆向）
