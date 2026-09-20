# LMM 安装脚本

Pi、DSH、LMM CLI、Codex、Claude Code、CC Switch、Clash Verge Rev 的安装入口。

## 菜单

Linux / macOS / Termux：

```sh
curl -fsSL https://api.lmm.best/scripts/menu.sh | bash
```

Windows PowerShell 5.1+：

```powershell
irm https://api.lmm.best/scripts/menu.ps1 | iex
```

选择工具，再选安装、更新、检查或启动。默认不启动应用、不登录账号。Pi/DSH/LMM 默认不改 PATH；新增工具使用官方安装位置和更新策略，官方安装器可能修改用户 PATH。桌面软件可能要求管理员授权，不自动配置订阅、启用代理或关闭系统安全提示。

菜单会执行下载的代码。需要先审查时，下载脚本后再运行。`bash menu.sh --list` / `.\menu.ps1 -List` 只列出工具。

## 工具与平台

脚本文件名如下，Unix 使用 `.sh`，Windows 使用 `.ps1`。

| 文件名 | 安装方式 | 平台说明 |
|---|---|---|
| `pi` | 固定 npm 版本及 LMM 插件 | Linux、macOS、Windows、原生 Termux；Windows 需要 Bash |
| `dsh` | 固定 npm 版本及 profile 内的 LMM 插件 | Linux、macOS、Windows；Android 原生依赖未验证 |
| `lmm` | 固定预编译包；可显式从源码构建 | Linux x64、macOS arm64、Windows x64；开发预览，无 Android 包 |
| `codex` | 官方原生安装器，默认 latest | Linux、macOS、Windows；Termux 走 PRoot Linux |
| `claude-code` | 官方原生安装器，默认 stable | Linux、macOS、Windows；Termux 走 PRoot Linux |
| `cc-switch` | deb/rpm、现有 AUR helper、AppImage；macOS Homebrew/DMG；Windows portable ZIP | 桌面平台；Termux 不显示 |
| `clash-verge-rev` | deb/rpm、现有 AUR helper；macOS Homebrew/DMG；Windows 官方安装窗口 | 桌面平台；不提供 AppImage 路径，Termux 不显示 |

Codex、Claude 原生安装不需要 Node。Linux 的依赖准备覆盖 Debian/Ubuntu、Fedora/RHEL、openSUSE、Arch、Alpine、Void；只有显式传 `--install-deps` 才安装系统依赖，不执行整机升级。Alpine 的 Claude 另需 `libgcc libstdc++ ripgrep`，启动器保留 `USE_BUILTIN_RIPGREP=0`。NixOS 需使用自身的 Nix 包环境，不支持直接套用通用二进制安装器。

官方依据和具体限制见 [安装方式核查](docs/install-sources.md)。模拟测试通过不代表所有发行版、硬件和图形环境都已实测。

## 直接运行

先下载对应脚本，或在仓库目录执行：

```sh
bash codex.sh --dry-run           # 预览安装方式
bash codex.sh                     # 安装；已有入口则复用
bash codex.sh --check             # 检查可执行程序
bash codex.sh --update            # 再次运行官方安装器
bash claude-code.sh --version latest
bash claude-code.sh --install-deps
```

Windows 对应 `-DryRun`、`-Check`、`-Update`、`-Version`，例如 `powershell -ExecutionPolicy Bypass -File .\codex.ps1 -Check`。

四个新增工具均支持 `--launch` / `-Launch`、`--root` / `-Root`。`--root` 管理本站创建的辅助启动器和便携版，不改变官方原生客户端的安装目录。`--dry-run` 不安装，但默认仍会获取公共函数。桌面工具的检查只确认入口存在，不自动启动图形界面。

Pi/DSH/LMM 的原有参数保持不变：`--check`、`--update`、`--launch`、`--add-path`、`--network auto|official|china`。其更新重装 [versions.json](versions.json) 固定版本，不追踪 latest；宿主与 LMM 插件需要一起验证后升级。全部参数见各脚本的 `--help` / `-Help`。

## Termux

先准备基础工具：`pkg install bash curl coreutils`。安装目录、缓存和临时文件留在私有目录，不放到 `/sdcard` 或 `/storage`。未设置 `TMPDIR` 时使用 `$PREFIX/tmp`，启动器使用当前 Bash 的绝对路径。

Pi 另需 `pkg install nodejs npm git`；脚本检查 Android 原生 Node，不下载桌面 Linux Node。剪贴板可选 Termux:API 应用和 `pkg install termux-api`。浏览器未打开时用 `termux-open-url` 打开登录地址。

Codex、Claude 使用已有的 PRoot guest：

```sh
pkg install proot-distro
proot-distro install ubuntu:24.04
bash codex.sh --install-deps
bash claude-code.sh --install-deps
```

默认 guest 名称为 `ubuntu`，其他已安装环境用 `--distro NAME`。脚本不创建或重置 guest；`--install-deps` 仅自动准备 Debian/Ubuntu guest 的依赖。启动器把当前目录绑定到 guest 的 `/workspace`，原样转发参数。PRoot 不是独立 Linux 内核，不保证所有沙箱能力可用；没有关闭 Agent 沙箱作为替代。

Android 真机、DSH Android 原生依赖和 LMM CLI Android 源码构建尚未验证。CC Switch、Clash Verge Rev 在 Termux 菜单中隐藏。

## 使用与维护

Pi：启动后 `/login` → LMM → 浏览器授权，再用 `/model` 选模型。DSH：`dsh web` → Settings → Models → LMM；headless 登录先在同一 `DSH_HOME` 的 Web profile 完成。Codex、Claude 按各自的官方登录提示操作，安装器不代填账号或模型配置。

LMM CLI 目前提供 `catalog`、`status`、`doctor --report`、`login`、`models --json`。`setup --dry-run` 只预览，不执行软件接入；退出码 3 不表示全部成功。Linux 登录需要可用的 Secret Service，SSH/容器不一定具备。

Pi/DSH/LMM 默认目录为 `${XDG_DATA_HOME:-~/.local/share}/lmm-tools` 或 `%LOCALAPPDATA%\lmm-tools`，不覆盖系统 Node/npm 包。没有加入 PATH 时使用安装结束打印的完整路径。

公共函数从固定 GitHub 提交加载，不再内嵌到每个安装器，也不另设公共库哈希清单。本地开发可设 `LMM_LIB_DIR="$PWD/templates/lib"`；帮助页不联网，检查模式可能获取公共函数。下载失败会停止，不把半个文件当作成功安装。

网络源、生成、缓存恢复、PATH 和卸载说明见 [维护文档](docs/maintenance.md)。
