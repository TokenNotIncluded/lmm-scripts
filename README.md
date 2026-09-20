# LMM 安装脚本

安装 Pi、DeepSeek Harness（DSH）及其 LMM 插件，也可安装 LMM CLI 预览版。

## 安装

Linux / macOS：

```sh
curl -fsSL https://api.lmm.best/scripts/menu.sh | bash
```

Windows PowerShell 5.1+：

```powershell
irm https://api.lmm.best/scripts/menu.ps1 | iex
```

选择工具，再选择安装、检查或启动。默认不改 PATH、不启动工具、不登录账号。菜单入口执行远程代码；需要先审查时，下载脚本后再运行。

Pi 在 Windows 上需要 Git Bash，或 Pi 设置中的有效 `shellPath`。脚本只检查，不覆盖设置，也不自动安装系统软件。

## Termux（原生 Android）

先准备 Termux 自己的依赖：

```sh
pkg install bash curl coreutils nodejs npm git
curl -fsSL https://api.lmm.best/scripts/menu.sh | bash
```

安装目录保持在 `$HOME`。脚本确认 Node 是 Android 版本，不下载桌面 Linux 二进制。安装、缓存和临时目录不能放在 `/sdcard`、`/storage`，包括指向共享存储的链接。未设置 `TMPDIR` 时使用 `$PREFIX/tmp`；启动器使用当前 Bash 的绝对路径和明确的 Node 入口。

文本剪贴板另需 Termux:API 应用和 `pkg install termux-api`，不作为强制依赖。浏览器未打开时可用 `termux-open-url` 打开登录地址。脚本不申请存储权限、不清空用户缓存、不执行系统升级。

Pi 的安装方式遵循官方 Termux 文档。DSH 的 Android 原生依赖、LMM CLI 的 Android 源码构建尚未经真机验证；LMM CLI 没有 Android 预编译包。环境模拟测试不等于真机验证。

## 新增工具

菜单也提供 Codex、Claude Code、CC Switch 和 Clash Verge Rev。文件名分别为 `codex`、`claude-code`、`cc-switch`、`clash-verge-rev`，后缀按系统选择 `.sh` / `.ps1`。

```sh
bash codex.sh --dry-run           # 查看安装方式，不安装
bash codex.sh                     # 使用官方安装器
bash claude-code.sh --update      # 官方 stable；--version latest 可改通道
bash claude-code.sh --install-deps # 明确允许安装当前发行版的依赖
```

Windows 对应 `-DryRun`、`-Update`、`-Version`。Codex/Claude 使用上游原生安装目录、PATH 和自动更新策略，不强塞到 LMM 独立 npm 目录；无需 Node。安装不会替你登录、修改模型供应商或关闭沙箱。

Linux CLI 根据 libc 使用官方安装器，依赖命令覆盖 Debian/Ubuntu、Fedora/RHEL、openSUSE、Arch、Alpine、Void；不执行系统升级。Alpine 的 Claude 需要 `libgcc libstdc++ ripgrep`；NixOS 需自行使用 Nix 包环境，不声称通用二进制可直接运行。

Termux 的这两个 CLI 使用已有的 PRoot Linux guest，不是原生 Android 安装。先执行 `pkg install proot-distro`、`proot-distro install ubuntu:24.04`，再运行 `bash codex.sh --install-deps`；另一个 guest 用 `--distro NAME`。安装器不创建/重置 guest；默认 Ubuntu 的依赖可由 `--install-deps` 准备。启动器绑定当前工作目录，参数原样转发；PRoot 不等于完整 Linux 沙箱，真机尚未验证。

桌面工具在 Termux 菜单中隐藏。Linux 使用 deb/rpm、现有 AUR helper；CC Switch 另有 AppImage，Clash Verge Rev 不假设存在 AppImage。macOS 优先复用 Homebrew，否则安装官方 DMG；Windows 分别使用官方 portable ZIP、官方安装窗口。桌面安装可能要求管理员授权，Clash 安装包可能带服务；脚本不自动启用代理、TUN、订阅，也不绕过系统签名提示。

来源和支持边界见 [安装核查](docs/install-sources.md)。

## 安装后怎么用

没有加入 PATH 时，用安装结束打印的完整路径代替下方的工具名。

| 工具 | 启动与登录 | 常用操作 |
|---|---|---|
| Pi | `pi` → `/login` → LMM → 浏览器授权 | `/model` 选模型；`pi -c` 继续会话；`pi list` 查看插件 |
| DSH | `dsh web` → Settings → Models → LMM → Sign in with LMM | `dsh web --no-open` 不自动开浏览器；其他参数见 `dsh --help` |
| LMM CLI | `lmm login` | `lmm catalog pi`、`lmm status`、`lmm doctor --report`、`lmm models --json` |

DSH 插件按 profile 安装，默认 `web`。使用 `headless` 前，先在相同 `DSH_HOME` 的 Web profile 完成登录。不要把 Pi、DSH 的凭据文件复制给其他客户端。

LMM CLI 的实际软件安装、接入、恢复尚未完成；`lmm setup pi --dry-run` 仅预览。`doctor` / `setup --dry-run` 返回 3 时不代表全部成功。Linux 登录需要可用的 Secret Service，SSH 或容器中不一定具备。

## 直接运行与更新

```sh
curl -fsSLo pi.sh https://api.lmm.best/scripts/pi.sh
bash pi.sh                         # 安装
bash pi.sh --check                 # 只检查，不代表登录成功
bash pi.sh --update                # 重装固定版本，不追踪 latest
bash pi.sh --launch                # 安装后启动
bash pi.sh --add-path              # 明确允许加入用户 PATH
bash pi.sh --network china         # 镜像优先；官方源可用 official
bash pi.sh --help                  # 全部参数
```

Windows 对应参数为 `-Check`、`-Update`、`-Launch`、`-AddPath`、`-Network china`、`-Help`：

```powershell
Invoke-WebRequest https://api.lmm.best/scripts/pi.ps1 -OutFile pi.ps1
powershell -ExecutionPolicy Bypass -File .\pi.ps1
powershell -ExecutionPolicy Bypass -File .\pi.ps1 -Check
```

安装 DSH 或 LMM CLI 时，把文件名中的 `pi` 换成 `dsh` 或 `lmm`。DSH 可选 `--profile headless` / `-Profile headless`。固定版本见 [versions.json](versions.json)，宿主与插件须一起验证后升级。

## 公共函数加载

默认从 `versions.json` 的 `library_revision` 获取 GitHub 公共模块。Shell 完整获取文件后通过 `source <(...)` 导入；PowerShell 使用对应的点导入。没有公共模块哈希清单，不内嵌另一套备用库。下载失败就停止，不执行部分响应。

`--help` / `-Help` 不联网。`--check` / `-Check` 不修改安装文件，但默认需要联网加载公共模块。断网或调试时，明确指定同版本的本地公共目录：

```sh
LMM_LIB_DIR="$PWD/templates/lib" bash pi.sh --check
```

```powershell
$env:LMM_LIB_DIR = Join-Path $PWD 'templates/lib'
.\pi.ps1 -Check
```

本地目录缺少模块时直接报错，不偷偷转为联网。这里只控制公共函数的来源；安装客户端仍可能需要下载软件包。`--network` 控制软件包来源，不改变公共模块的 GitHub 地址。客户端安装完成后的启动入口不需要重新获取这些模块。

## 环境与故障

Pi/DSH/LMM 的默认目录：Unix 为 `${XDG_DATA_HOME:-~/.local/share}/lmm-tools`，Windows 为 `%LOCALAPPDATA%\lmm-tools`；可用 `LMM_INSTALL_ROOT` 或 `--root` / `-Root` 修改。不覆盖系统 Node 或全局 npm 包。

Pi 使用官方的 `npm install --ignore-scripts`，接受已有的 `ignore-scripts=true`。DSH 的原生构建策略单独处理，不解除用户的构建限制。Node 要求为 22.19+ 的 22.x 或 24+。

下载失败时检查 HTTPS 代理和证书，尝试 `--network official` 或 `china`，不要关闭 TLS 校验。Alpine / musl 需要先安装系统提供的兼容 Node/npm。

LMM CLI 预编译包仅提供 Linux x64（glibc 2.39+）、macOS arm64、Windows x64。其他平台可在准备 Rust 1.88+ 和编译工具后尝试 `--from-source`，不保证所有平台都能构建。

公共函数、生成方式、缓存、PATH 恢复和卸载注意事项见 [维护说明](docs/maintenance.md)。安装器运行时从固定 Git 提交加载公共函数，不再把它们复制进每个发布脚本。

## 文档依据

[Pi 安装](https://pi.dev/docs/latest/quickstart) · [Windows](https://pi.dev/docs/latest/windows) · [Termux](https://pi.dev/docs/latest/termux) · [Pi 包管理](https://pi.dev/docs/latest/packages) · [DSH 官方 README](https://github.com/deepseek-ai/deepseek-harness/blob/master/README.md)

[Termux 执行环境](https://github.com/termux/termux-packages/wiki/Termux-execution-environment) · [Termux Node/npm 包定义](https://github.com/termux/termux-packages/blob/master/packages/nodejs/build.sh) · [LMM Pi 插件](https://github.com/TokenNotIncluded/pi-lmm-provider) · [LMM DSH 插件](https://github.com/TokenNotIncluded/dsh-lmm-provider)

隔离目录、镜像、固定版本和 LMM 登录是本项目的集成选择，不是官方安装器。
