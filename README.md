# LMM 安装脚本

根目录直接维护脚本，不生成代码。没有代理配置、测速、镜像、私有 Node、缓存或回滚框架；官方安装器自己的依赖安装和检查保持原样。

```sh
curl -fsSLo menu.sh https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/main/menu.sh
bash menu.sh
```

```powershell
irm https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/main/menu.ps1 | iex
```

也可下载单个脚本运行。安装和更新使用同一入口；之后直接使用工具自己的命令。

| 文件名（`.sh` / `.ps1`） | 安装方式 | 启动 |
|---|---|---|
| `pi` | `pi.dev/install.sh` / `install.ps1`，保留官方交互和依赖处理 | `pi`，然后 `/login` |
| `dsh` | npm + pnpm，加 LMM 插件；默认 web profile | `dsh web` |
| `codex` | 官方原生安装器，参数直接传给官方 | `codex` |
| `claude-code` | 官方原生安装器，参数直接传给官方 | `claude` |
| `cc-switch` | Linux 发行包/AUR，macOS Homebrew，Windows 官方 MSI | 桌面应用 |
| `clash-verge-rev` | Linux deb/rpm/AUR，macOS Homebrew，Windows WinGet | 桌面应用 |
| `lmm` | 0.1.0 预览版发行包；另支持 `--from-source` / `-FromSource` | 安装结束打印的完整路径 |

Pi 的版本、Node、安装位置、权限和 Windows Git Bash 交给官方安装器。官方正常安装后，才从它选出的安装路径接着装 LMM 插件；取消或卸载不继续。现有 LMM alpha 只验证过 Pi 0.85.1，其他版本会明确跳过插件，不偷偷降级宿主。DSH 的宿主和插件继续固定已适配版本；其当前官方 README 使用 npx，没有现行的独立安装脚本，不能拿归档记录中的旧脚本替代。

不写供应商配置、不登录账号、不启用系统代理或 TUN。

## 环境

Unix 入口需要 Bash、curl。Pi 的依赖提示由官方处理；DSH 另需 Node 22.19+（22.x）或 24+、npm。不修改 npm registry。

Codex/Claude 的 Linux、macOS、Windows 安装都用官方脚本，不要求 Node，也不限定 apt 发行版。先满足上游的系统和运行库要求。Alpine 的 Claude 需要 `bash curl libgcc libstdc++ ripgrep`，运行时使用 `USE_BUILTIN_RIPGREP=0 claude`。NixOS 请使用 Nix 包环境，不保证通用二进制可运行。

Linux 桌面安装需要 `jq` 及 apt/dnf/yum/zypper，Arch 复用已安装的 paru/yay；CC Switch 在其他兼容 glibc 的系统上可用 AppImage。桌面软件仍受上游系统版本和运行库限制。macOS 需要已有 Homebrew；Windows Clash 需要已有 WinGet。系统包安装会使用 sudo 或弹出官方授权窗口。

LMM 预览包仅提供 Linux x64（glibc 2.39+）、macOS arm64、Windows x64，安装到 `~/.local/bin`，不自动改 PATH。源码安装需要 Rust 1.88+ 和编译工具；预览版 `setup` 仍不能实际安装应用。

## Termux

Pi 先运行 `pkg install nodejs npm git` 准备 Android 原生依赖，再调用同一个官方安装器；没有 `TMPDIR` 时使用 `$PREFIX/tmp`。DSH 使用同一 npm 安装方式，Android 原生依赖尚未真机验证。

Codex/Claude 使用**已有的 PRoot Linux 环境**，不是 Android 原生二进制。先准备 `proot-distro` 和 Ubuntu guest，并在 guest 中安装 Bash、curl、CA 证书，再运行相应脚本。其他 guest 用 `LMM_DISTRO=名称 bash codex.sh`。安装后进入同一 guest 运行 `codex` / `claude`；不再生成转发启动器，不创建或重置 guest，不关闭沙箱。两个桌面工具不支持 Termux，菜单会隐藏它们。

## 从旧版切换

旧的 `--network`、`--root`、`--check`、`--update` 等自定义参数已移除；不要继续传入。Codex/Claude 只接受各自官方参数，DSH 可传 profile。旧版 `lmm-tools` 目录不会被删除；从 PATH 中移除旧的 `lmm-tools/bin`，避免旧启动器优先于新安装。配置和账号数据不迁移、不清空。

所有安装代码平铺在根目录；只有两个 Unix 桌面入口共用 `desktop.sh`。本地运行用同目录文件，单独下载运行时用固定 Git 提交获取共用脚本；菜单同样固定到完整的安装器提交。不维护生成器或哈希清单。

## 依据与测试

2026-09-21 核查：[Pi 官网安装入口](https://pi.dev/)（[Shell](https://pi.dev/install.sh) / [PowerShell](https://pi.dev/install.ps1)）· [Codex](https://learn.chatgpt.com/docs/codex/cli) · [Claude Code](https://code.claude.com/docs/en/setup) · [Pi Termux](https://pi.dev/docs/latest/termux) · [DSH 当前 README](https://github.com/deepseek-ai/deepseek-harness/blob/master/README.md) · [DSH 插件](https://deepseek-harness.github.io/deepseek-harness/en/develop/basic/publish) · [CC Switch](https://github.com/farion1231/cc-switch#download--installation) · [Clash Verge Rev](https://www.clashverge.dev/install.html)。LMM 插件适配版本见 [Pi 插件](https://github.com/TokenNotIncluded/pi-lmm-provider) 和 [DSH 插件](https://github.com/TokenNotIncluded/dsh-lmm-provider)。

本地检查：`python3 test.py`、`pwsh -NoProfile -File test.ps1`、`shellcheck *.sh`。CI 另做三平台 CLI 实装和 Debian/Alpine 实装；不把模拟测试当作桌面 GUI、Termux 真机、账号登录或代理功能实测。
