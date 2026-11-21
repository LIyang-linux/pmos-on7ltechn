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
