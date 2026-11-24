# clavis-greeter

一个**完全照抄 [Clavis Shell](https://github.com/StatIndet/quickshell) 锁屏样式**的 greetd 图形登录界面。

> 本项目是 Clavis Shell 的**衍生作品**，遵循 **GPL-3.0-only**（与上游一致）。

Clavis/Quickshell 本身不提供 greeter 能力（它的 `WlSessionLock` 只能在已登录会话里用），
所以这个项目把 Clavis 的锁屏模块原样拿出来，跑在一个最小化的 **niri** 会话里，通过 greetd IPC 完成认证。

```
greetd ──▶ clavis-greeter-session (wrapper)
             └─▶ niri -c niri-greeter.kdl -- quickshell -c /usr/lib/clavis-greeter/shell
                   └─▶ shell.qml (PanelWindow 全屏) ──▶ ClavisLock ──▶ 后端 Python ──▶ greetd IPC
```

## 为什么是 niri 而不是 cage

- 复用**已安装**的 niri，不需要额外合成器（不装 cage）
- greeter 的 **output scale 直接从桌面 niri 配置复制**（如 `scale 1.5`），
  登录界面和桌面锁屏的尺寸/清晰度完全一致
- `PanelWindow` 走 layer-shell，天然全屏、无边框、无间隙

## 依赖

全部来自 Arch 官方仓库：

```
bash  python  niri  quickshell  greetd  oo7
```

可选：`gcr` 提供非 GNOME 桌面下的图形钥匙串解锁提示；正常 PAM 自动解锁不依赖它。

`greetd-agreety` 会作为 `greetd` 的硬依赖自动存在，本项目**不调用它**，但它同时是
`clavis-greeter-rollback` 的兜底方案（文字登录永远可用）。

## 安装

```bash
# 1. 安装包
sudo pacman -U clavis-greeter-*.pkg.tar.zst

# 2. 配置（创建 greeter 账户、复制壁纸/头像、生成 niri 配置、配置 greetd/PAM）
sudo clavis-greeter-setup "$USER"

# 3. 作为目标用户，在自己的桌面会话中启用 oo7 用户服务（不要加 sudo）
systemctl --user enable oo7-daemon.service

# 4. 重启后，从 Clavis greeter 登录
reboot
```

`clavis-greeter-setup` 会做的事：

| 步骤 | 内容 |
|---|---|
| 1 | 创建系统用户 `greeter`（加入 `video` 组） |
| 2 | 写 `/etc/clavis-greeter.conf`（记录目标用户） |
| 3 | 把目标用户的壁纸/头像复制到 `/var/lib/clavis-greeter/`（世界可读） |
| 4 | 准备 greeter 的可写 HOME（`/var/lib/clavis-greeter/home`） |
| 5 | 生成 `/usr/lib/clavis-greeter/shell`（符号链接到已安装的 Clavis shell + 若干 shim） |
| 6 | 从目标用户的 niri 配置提取 `output` 块，生成 `niri-greeter.kdl` |
| 7 | 在 `/etc/pam.d/greetd` 添加 optional 的 oo7 auth/session hooks；修改前备份原文件 |
| 8 | 备份并改写 `/etc/greetd/config.toml` |
| 9 | 启用 `getty@tty2`（应急文字控制台） |
| 10 | 生成 `clavis-greeter-rollback` 回退脚本（若 PAM 是本工具修改的，也会恢复备份） |

## oo7 登录自动解锁

`clavis-greeter-setup` 为 greetd 专用 PAM 栈添加 `auth optional pam_oo7.so` 和
`session optional pam_oo7.so auto_start`。登录密码通过 PAM 暂存并交给 oo7，模块是 `optional`，
所以 oo7 不可用时不应阻止正常登录。首次部署后，以目标用户身份执行
`systemctl --user enable oo7-daemon.service`，让 oo7 在用户会话启动时运行。

**登录钥匙串密码必须与系统登录密码一致**，否则 PAM 会安全地跳过解锁，应用仍可能显示钥匙串提示。
如果两者不同，可运行 `oo7-cli change-secret --collection login`，在本机提示中将钥匙串密码改为登录密码；
不要把密码写进命令或配置文件。

如需在以后通过 `passwd` 修改系统密码时同步钥匙串密码，可选择在
`/etc/pam.d/system-auth` 的 `password` 栈、`pam_unix.so` 后添加：

```pam
password optional pam_oo7.so
```

这会影响所有包含该共享 `system-auth` 栈的密码修改服务，因此本项目安装脚本不会自动改它。

首次验证时，登录后运行 `oo7-cli list-collections`；`login` 行没有 `(locked)` 表示已解锁。
该命令只显示集合状态，不输出密钥内容。

## 卸载 / 回退

```bash
# 回退成文字登录（不依赖本项目，也不依赖任何已删包）
sudo clavis-greeter-rollback
systemctl --user disable oo7-daemon.service
sudo systemctl restart greetd

# 或者 Ctrl+Alt+F2 进应急控制台，登录后执行上面两条
```

彻底卸载：

```bash
sudo pacman -Rns clavis-greeter
sudo rm -rf /var/lib/clavis-greeter /usr/lib/clavis-greeter
# /etc/greetd/config.toml 请自行改回原来的登录管理器
```

## 故障排查

| 现象 | 处理 |
|---|---|
| 登录界面黑屏 | `Ctrl+Alt+F2` → 登录 → `sudo clavis-greeter-rollback && sudo systemctl restart greetd` |
| 界面尺寸不对 | 重新运行 `sudo clavis-greeter-setup "$USER"`（会重新生成含 scale 的 niri 配置） |
| 壁纸/头像不显示 | 检查 `~/.config/clavis/config.json` 的壁纸路径与 `~/.face` 是否存在 |
| 查看 greeter 日志 | `journalctl -b -u greetd` |

## 文件布局

```
/usr/lib/clavis-greeter/
├── build.sh                    # 生成 shell/ 树
├── niri-greeter.kdl            # setup 生成的 niri 配置（含 output scale）
├── backend/greeter-backend.py  # greetd IPC 客户端 + QML stdin/stdout 桥
├── overrides/                  # shell.qml + 4 个 shim / 锁屏副本
├── session/clavis-greeter-session
└── shell/                      # setup 生成（符号链接 + shim 覆盖）
/usr/bin/clavis-greeter-{build,session,setup,rollback}
/etc/clavis-greeter.conf
/var/lib/clavis-greeter/{wallpaper.jpg,avatar,home/}
```

## 设计细节

- **锁屏完全复用上游**：`overrides/ClavisLock.qml` 是 `DefaultLock.qml` 的副本，只有 2 行差异
  （`required property WlSessionLock lock` → `var lock`，并加一行 import），
  保证和 Clavis 锁屏像素级一致。
- **只 shim 3 个读用户 HOME 的服务**：`SystemIdentityService`（用户名/主机名）、
  `AvatarService`（头像）、`WallpaperService`（壁纸），其余模块全部符号链接到真实 Clavis。
- **`Services/` 必须整目录复制**：Quickshell 的模块扫描器不把逐文件符号链接注册为单例，
  会导致 `Type Xxx unavailable` 连锁报错。
- **成功判定靠 marker 文件**：后端在 greetd 接受会话后写 `CLAVIS_GREETER_OK_FILE`，
  wrapper 轮询到该文件才终止 niri 并 `exit 0`，避免 greetd 在认证成功前就切走 VT。

## 许可证 / License

**GPL-3.0-only** —— 与上游 [Clavis Shell](https://github.com/StatIndet/quickshell) 保持一致。

本项目是 Clavis Shell 的衍生作品，具体体现在：

- `overrides/ClavisLock.qml` 直接派生自上游 `Modules/Lock/DefaultLock.qml`
- 运行时通过符号链接复用上游的 `Modules/`、`Widgets/`、`Components/`、`Common/`、`Services/`、`assets/` 等模块
- `build.sh` 生成的 `shell/` 树中包含上游的 `LICENSE` 与 `licenses/` 第三方许可文件

因此任何分发（含打包）都必须遵守 GPL-3.0 条款，并在提供二进制时一并提供完整对应源码。

```
Copyright (C) 2026 wxmyyds
Copyright (C) Clavis Shell contributors (https://github.com/StatIndet/quickshell)

This program is free software: you can redistribute it and/or modify it under
 the terms of the GNU General Public License as published by the Free Software
 Foundation, version 3.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
 PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
 this program.  If not, see <https://www.gnu.org/licenses/>.
```
