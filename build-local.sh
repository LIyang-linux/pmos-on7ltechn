#!/usr/bin/env bash
# 本地构建 postmarketOS（Linux / WSL2）
# 用法：./build-local.sh [workdir]
set -euo pipefail

WORKDIR="${1:-$HOME/.pmos-on7ltechn}"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
PMB_DIR="$WORKDIR/pmbootstrap"

mkdir -p "$WORKDIR"

if [ ! -d "$PMB_DIR" ]; then
    echo "==> 拉取 pmbootstrap"
    git clone --depth=1 https://gitlab.postmarketos.org/postmarketOS/pmbootstrap "$PMB_DIR"
fi

cd "$PMB_DIR"

if [ ! -f "$HOME/.config/pmbootstrap.cfg" ] && [ ! -f "$HOME/.config/pmbootstrap_v3.cfg" ]; then
    echo "==> 首次运行，进入交互式 init（Vendor: samsung / Device: on7ltechn / UI: console）"
    ./pmbootstrap.py init
fi

APORTS="$(./pmbootstrap.py config aports)"
echo "==> 注入设备包到 $APORTS/device/testing/"
mkdir -p "$APORTS/device/testing"
rm -rf "$APORTS/device/testing/device-samsung-on7ltechn"
cp -r "$REPO_ROOT/device-samsung-on7ltechn" "$APORTS/device/testing/"

KAPORT=$(find "$APORTS" -maxdepth 3 -type d -name 'linux-postmarketos-qcom-msm8916' | head -1)
if [ -n "$KAPORT" ]; then
    echo "==> 给 $KAPORT 注入显示/触摸补丁"
    python3 "$REPO_ROOT/scripts/inject-kernel-patches.py" "$KAPORT" "$REPO_ROOT/kernel-patches"

    # 与 CI 保持一致：把面板/触摸驱动编进内核（=y），而不是只做模块。
    # 不这样做的话，initramfs 阶段没有面板驱动，开机看不到 logo。
    CFG=$(ls "$KAPORT"/config-*aarch64 2>/dev/null | head -1 || true)
    if [ -n "$CFG" ]; then
        echo "==> 强制内核配置：$CFG"
        for OPT in CONFIG_DRM_PANEL_SAMSUNG_S6D7AA0 \
                   CONFIG_BACKLIGHT_CLASS_DEVICE \
                   CONFIG_TOUCHSCREEN_ZINITIX; do
            sed -i -e "s/^${OPT}=.*/${OPT}=y/" \
                   -e "s/^# ${OPT} is not set/${OPT}=y/" "$CFG"
            grep -q "^${OPT}=" "$CFG" || echo "${OPT}=y" >> "$CFG"
        done
        # config 在 source= 里，改过就要同步 APKBUILD 的 sha512，否则 abuild 校验失败
        CFGSUM=$(sha512sum "$CFG" | cut -d' ' -f1)
        sed -i -E "s|^[[:space:]]*[0-9a-f]{128}([[:space:]]+[^[:space:]]*config-[^[:space:]]*aarch64[[:space:]]*)$|\t${CFGSUM}\1|" \
            "$KAPORT/APKBUILD"
        grep -q "^[[:space:]]*${CFGSUM}" "$KAPORT/APKBUILD" || {
            echo "!! APKBUILD 里的内核 config 校验和没更新成功" >&2
            exit 1
        }
    else
        echo "!! 未找到内核 config-*aarch64，面板驱动可能未启用" >&2
    fi
fi

./pmbootstrap.py index

echo "==> 编译设备包"
./pmbootstrap.py build device-samsung-on7ltechn

echo "==> 生成镜像（输出在 pmbootstrap 的 work 目录 images/ 下）"
./pmbootstrap.py install --password 147147

echo "==> 完成。先刷 lk2nd，再 fastboot flash userdata <镜像>"
