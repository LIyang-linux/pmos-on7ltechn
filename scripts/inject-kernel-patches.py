#!/usr/bin/env python3
"""把 kernel-patches/*.patch 注册进 pmaports 的主线内核包。

不覆盖 prepare()，而是像上游补丁一样加入 source= 与 sha512sums=，
这样 abuild 会用同样的 cwd 和 -p1 规则应用，避免路径假设出错。

用法: inject-kernel-patches.py <kernel-aport-dir> <patch-dir>
"""
import hashlib
import pathlib
import re
import shutil
import sys

MARK = "# on7ltechn-display"


def block_insert(text: str, key: str, lines: list[str]) -> str:
    """在 source=/sha512sums= 块中插入行，兼容单行与多行写法。"""
    m = re.search(rf'^{key}="(.*?)"', text, re.S | re.M)
    if not m:
        raise SystemExit(f"{key}= 未找到")
    body = m.group(1)
    if "\n" in body:              # 多行块：插到块首
        content = "\n" + "".join(f"\t{l}\n" for l in lines) + body.lstrip("\n")
    else:                          # 单行：插到行首
        content = " ".join(lines) + " " + body
    new = f'{key}="' + content + '"'
    return text[:m.start()] + new + text[m.end():]


def main() -> int:
    aport = pathlib.Path(sys.argv[1]).resolve()
    patch_dir = pathlib.Path(sys.argv[2]).resolve()
    patches = sorted(patch_dir.glob("*.patch"))
    if not patches:
        raise SystemExit("没有找到补丁文件")

    for p in patches:                      # abuild 从 $startdir 取源码
        shutil.copy2(p, aport / p.name)

    apkbuild = aport / "APKBUILD"
    text = apkbuild.read_text()
    if MARK in text:
        print("已注入过，跳过")
        return 0

    names, sums = [], []
    for p in patches:
        digest = hashlib.sha512(p.read_bytes()).hexdigest()
        names.append(p.name)
        sums.append(f"{digest}  {p.name}")

    text = block_insert(text, "source", names)
    text = block_insert(text, "sha512sums", sums)
    # 标记只能在引号外，否则会被当成一个叫 "#" 的源文件
    text += f"\n{MARK}\n"
    text = re.sub(r"^pkgrel=(\d+)",
                  lambda m: f"pkgrel={int(m.group(1)) + 1}",
                  text, count=1, flags=re.M)
    apkbuild.write_text(text)
    print(f"已注入 {len(names)} 个补丁: {', '.join(names)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
