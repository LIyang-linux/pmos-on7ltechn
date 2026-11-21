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
fi

./pmbootstrap.py index

echo "==> 编译设备包"
./pmbootstrap.py build device-samsung-on7ltechn

echo "==> 生成镜像（输出在 pmbootstrap 的 work 目录 images/ 下）"
./pmbootstrap.py install --password 147147

echo "==> 完成。先刷 lk2nd，再 fastboot flash userdata <镜像>"
