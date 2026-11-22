# 构建踩坑记录

## dtc 不接受普通顶层节点

**现象**：内核编译报 `arch/arm64/boot/dts/qcom/msm8916-samsung-on7.dts:306.9-20 syntax error`。

**根因**：dtc 的语法里，**顶层只能有**：
- `/ { ... };`（根节点）
- `&label { ... };`（引用已有节点的覆盖块）
- `/delete-node/`、`/omit-if-no-ref/`

**普通顶层节点**（如 `i2c_fg: i2c_gpio_fg { ... };` 直接放在文件末尾）**不被接受**，即使括号平衡、本地最小 dts 也能复现：

```sh
$ cat > t.dts <<'EOF'
/dts-v1/;
/ {
};
mynode { };
EOF
$ dtc -I dts -O dtb t.dts
Error: t.dts:4.1-7 syntax error
```

**正确写法**：把节点放进 `/ { }` 覆盖块里（作为根节点的子节点）：

```dts
/ {
	i2c_fg: i2c_gpio_fg {
		compatible = "i2c-gpio";
		...
	};
};
```

本仓库的 fuelgauge 节点就是这样放的（见 patch 0003 末尾）。

## 本地复现 CI 的 DTS 编译

pcpp（Python 版 cpp）与 gcc cpp 行为不同，会误报。**用内核同款 gcc 预处理**才准：

```sh
gcc -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
    -I include -I arch/arm64/boot/dts/qcom \
    -o out.i msm8916-samsung-on7.dts
dtc -I dts -O dtb -o out.dtb out.i
```

注意两点：
- `include/dt-bindings/input/linux-event-codes.h` 是**符号链接**（指向 `../../uapi/linux/input-event-codes.h`），用 GitHub raw 下载只会拿到指针文本，要单独下载目标文件。
- gcc `-E` 输出 `# 1 "file"` 行标记；dtc 靠它报告原始文件行号。

## 补丁应用：CI 用 patch -p1，不是 git apply

CI（abuild/pmbootstrap）用 `patch -p1`，**带 fuzz 容错**；`git apply` 是严格匹配。
所以本地用 `git apply --check` 失败（上下文差几行）不代表 CI 失败。

另外补丁文件注意行尾：仓库里部分补丁是 CRLF（Windows 检出），本地 `git apply` 会失败，
CI 在 Linux 上是 LF 不受影响。

## 调试经验

- 加节点后编译失败，先用**最小 dts**（`/dts-v1/; / { }; 节点;`）验证节点语法；
- 最小 dts 通过但完整 dts 失败 → 问题在**位置/上下文**，不在节点内容；
- 用 `gcc -E` 的输出配合 `dtc`，能精确定位到真实物理行（别信 pcpp 的行号）。

## abuild 对包内路径有硬策略

`package()` 里 `install` 的目标路径受 abuild 检查，违反会直接失败（`prepare_subpackages failed`）：

| 禁止 | 原因 | 正确做法 |
|---|---|---|
| `/usr/local/...` | 包不允许装到 `/usr/local` | 用 `/usr/bin`、`/usr/share` 等 |
| `/lib/...` | Alpine 是 usrmerge | 用 `/usr/lib/...` |

## 不要在设备包里重复装主线固件

`firmware-qcom-adreno-a300` 已经提供 `usr/lib/firmware/qcom/a300_{pfp,pm4}.fw`，
设备包再装一遍会导致 install 阶段：

```
ERROR: firmware-qcom-adreno-a300: trying to overwrite ... owned by device-samsung-on7ltechn
```

把固件包写进 `subpackages` 的 `depends` 即可，不要自己 `install`。

## CI 日志收集要抓小写的 log.txt

pmbootstrap 的详细报错在 `work/log.txt`（**小写**），而 `find -name '*.log'` 匹配不到，
导致 CI 只显示 `Couldn't build ... ! Run 'pmbootstrap log' for details.` 而没有原因。
收集时显式加上 `-name 'log.txt'`。

## GitHub Actions 缓存的两个坑

1. **路径不能含 `..`**：`actions/cache` 会报
   `Invalid pattern ... Relative pathing '.' and '..' is not allowed` 并跳过保存。
   把 `WORK_DIR` 放进 `${{ github.workspace }}` 内即可。
2. **ccache 接不通**：pmbootstrap 在 chroot 内以 `pmos` 用户跑 ccache，
   缓存在 chroot 的 `/home/pmos/.ccache`，而 buildroot 每次构建前会被 zap；
   且 pmbootstrap 用独立 env（`env.copy()`），父环境的 `CCACHE_DIR` 传不进去。
   所以缓存 `~/.ccache` 永远 miss。要加速只能缓存下载目录（apk / git）。

## 镜像必须小于 userdata 分区

原厂 `recovery.log` 实测：`/data`（= userdata）= **12561.5 MB**。
pmbootstrap 的镜像大小 = `boot_size + rootfs×1.2 + 50 + extra_space`。

| UI | 镜像 | 结果 |
|---|---|---|
| xfce4 | 11865M | ✅ |
| phosh（extra_space=9700） | 12665M | ❌ 超出 103.5M |
| phosh（extra_space=9400） | 12365M | ✅ 余 196.5M |

换更重的 UI 时必须重新核算 `extra_space`。
