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
| `pi` | 官方安装器安装 Pi，再通过 npm 的 LMM 安装入口清理重复来源 | `pi`，然后 `/login` |
| `dsh` | npm + pnpm，安装当前 GitHub Release 的 LMM 插件；默认 web profile | `dsh web` |
| `codex` | 官方原生安装器，参数直接传给官方 | `codex` |
| `claude-code` | 官方原生安装器，参数直接传给官方 | `claude` |
| `cc-switch` | Linux 发行包/AUR，macOS Homebrew，Windows 官方 MSI | 桌面应用 |
| `clash-verge-rev` | Linux deb/rpm/AUR，macOS Homebrew，Windows WinGet | 桌面应用 |
| `lmm` | 0.1.0 预览版发行包；另支持 `--from-source` / `-FromSource` | 安装结束打印的完整路径 |
| `opencode` | 官方 npm 最新 OpenCode + 独立 LMM OAuth 插件 | `opencode auth login --provider lmm`，然后 `opencode` |
| `codewhale` | 官方 npm 安装 + 固定版本 LMM OAuth 适配器 | `bash codewhale.sh run` / `.\codewhale.ps1 run` |

## 更多 AI 工具

新增入口在菜单第 10–23 项，原来的 1–9 项不变。CLI 子菜单可选安装/更新，或配置/登录；配置操作要求工具已经安装并能从 PATH 找到。单个脚本默认执行 `install`，`help` 查看用法。新增脚本完全独立，下载一个文件即可运行，不需要下载共用实现。

| 文件名（`.sh` / `.ps1`） | 安装方式与平台 | 配置 / 启动 |
|---|---|---|
| `cursor-cli` | Cursor 官方安装器；Linux、macOS，Windows 通过已有 WSL | `setup` 执行 `cursor-agent login`，之后 `cursor-agent`；Windows 在 WSL 内运行 |
| `grok-build` | xAI 官方原生安装器；Linux、macOS、Windows | `setup` 执行 `grok login`，之后 `grok` |
| `gemini` | npm `@google/gemini-cli@latest`；Node 20+ | `setup` 启动 `gemini` 的首次登录界面 |
| `qwen-code` | 阿里 Qwen Code，npm `@qwen-code/qwen-code@latest`；Node 22+ | `setup` 启动 `qwen`，按界面选择认证方式 |
| `kimi` | 月之暗面当前维护的 **Kimi Code CLI** 官方原生安装器 | `setup` 启动 `kimi`，输入 `/login`；Windows 首次运行另需 Git for Windows |
| `codebuddy` | 腾讯 CodeBuddy Code，npm `@tencent-ai/codebuddy-code@latest`；本入口要求 Node 20+ | `setup` 启动 `codebuddy`，可选中国站、国际站或企业登录 |
| `hermes` | Nous Research 官方安装器；安装时跳过 setup | `setup` 执行 `hermes setup`，之后 `hermes` |
| `openclaw` | 官方安装器负责运行时依赖；安装时跳过 onboarding | `setup` 执行 `openclaw onboard`；不额外传入安装后台服务的参数 |
| `astrbot` | `uv tool install --upgrade astrbot --python 3.12`，同时用于安装和更新 | `setup DIRECTORY` 初始化指定实例目录，再在该目录运行 `astrbot run`，通过 WebUI 配置模型与聊天平台 |
| `aider` | Aider 官方安装器，隔离 Python 环境 | `setup` 启动 `aider`；按官方说明配置供应商环境变量、模型或项目配置 |
| `cursor` | Cursor 桌面版：macOS Homebrew；Linux 官方 deb/rpm 或 AppImage；Windows 官方用户安装器 | 在桌面应用内登录与配置，和 Cursor CLI 分开安装 |
| `cherry-studio` | Cherry Studio：macOS Homebrew；Linux/Windows 动态解析官方最新正式 Release | 桌面应用内设置模型服务、API 地址和账号；使用标准版，不混选 CN/便携版资产 |
| `ollama` | Linux 官方安装器、macOS Homebrew formula、Windows 官方安装器 | 需要时运行 `ollama serve`；`ollama run MODEL` 选择模型；本脚本不下载模型 |
| `uv` | Astral 官方安装器，供 AstrBot 等 Python 工具使用 | 重开终端后运行 `uv --version` |

例如，在本仓库目录运行：

```sh
bash menu.sh
bash qwen-code.sh install
bash qwen-code.sh setup
bash hermes.sh setup
bash astrbot.sh setup "$HOME/astrbot-instance"
cd "$HOME/astrbot-instance"
astrbot run
```

Windows：

```powershell
.\menu.ps1
.\qwen-code.ps1 install
.\qwen-code.ps1 setup
.\astrbot.ps1 setup -Directory "$HOME\astrbot-instance"
Set-Location "$HOME\astrbot-instance"
astrbot run
```

安装和配置分开执行：安装完成后先按上游提示重开终端，再执行 `setup`。不收集或代写 API Key，不批量覆盖工具的配置；登录、供应商选择和密钥保存交给各工具自己的界面。上游安装器可能安装依赖、修改 PATH、要求认证或启动服务（例如 Ollama 的 Linux 安装器），这些行为仍由上游决定。AstrBot 使用 uv 隔离环境，不向系统 Python 执行 pip 安装；uv 缺失时先运行 `uv.sh` / `uv.ps1`，更新仍用同一个 AstrBot 安装入口。实例目录已经包含 `data` 时，setup 跳过初始化，保留现有数据与配置。

桌面 Linux 安装需要 curl、jq 和相应包管理器；没有 deb/rpm 包管理器时安装 AppImage 到 `~/.local/bin`，运行依赖（例如 FUSE）仍需满足上游要求，不关闭 Electron 沙箱。macOS 需要已有 Homebrew。新增原生二进制/桌面入口拒绝直接在 Termux 安装；npm 和 uv 路线不承诺 Android 兼容，因此新增入口暂不进入 Termux 菜单。

2026-10-02 核对了官方入口：[Cursor CLI](https://docs.cursor.com/en/cli/installation)、[Cursor 桌面版](https://cursor.com/en-US/download)、[Grok Build](https://docs.x.ai/build/overview)、[Gemini CLI](https://github.com/google-gemini/gemini-cli/blob/main/docs/get-started/installation.mdx)、[Qwen Code](https://github.com/QwenLM/qwen-code/blob/main/scripts/installation/INSTALLATION_GUIDE.md)、[Kimi Code CLI](https://github.com/MoonshotAI/kimi-code)、[腾讯 CodeBuddy](https://www.codebuddy.ai/docs/cli/quickstart)、[Hermes](https://hermes-agent.nousresearch.com/docs/)、[OpenClaw](https://docs.openclaw.ai/install)、[AstrBot 安装](https://docs.astrbot.app/en/deploy/astrbot/package.html) / [CLI](https://docs.astrbot.app/en/use/cli.html)、[Aider](https://aider.chat/docs/install.html)、[Cherry Studio](https://github.com/CherryHQ/cherry-studio/releases)、[Ollama](https://ollama.com/download)、[uv](https://docs.astral.sh/uv/getting-started/installation/)。不安装已经宣布停服的 [iFlow CLI](https://github.com/iflow-ai/iflow-cli)，也不使用已经归档的旧 Python Kimi CLI。

Pi 主程序通过官方最新安装器安装；脚本用 npm 的 `@alpha` 入口执行 LMM 插件来源切换，实际安装 GitHub 最新 `main`。入口先确认安装成功，再清理同插件的其他来源；保留无关扩展，失败时保留旧来源。不设 Pi 宿主版本上限。安装 LMM 插件另需 Node.js 22.19+ 和 npm。Pi 的安装位置、权限和 Windows Git Bash 仍由官方安装器处理。

DSH 安装官方 npm `latest` 宿主和 pnpm，LMM 插件安装当前 GitHub Release 的已构建包；其当前官方 README 使用 npx，没有现行的独立安装脚本，不能拿归档记录中的旧脚本替代。

`dsh.sh` / `dsh.ps1` 默认配置 CLI 的 `web` profile，可传入其他 profile。宿主使用官方 `latest`，插件通过 GitHub 当前 Release 解析版本化下载链接，避免安装过时 npm 预览包或缺少构建文件的源码。最新插件已验证官方 DSH `0.2.0-rc.2`，此版本是验证基线，没有人为上限。官方 DSH Desktop `0.1.7-alpha.2` 使用独立的 `desktop` profile，应在桌面端“插件”页安装 `@tokennotincluded/dsh-lmm-provider@0.1.0-alpha.4`；CLI 安装不会进入桌面端。

原有安装器不写供应商配置、不登录账号、不启用系统代理或 TUN。Codewhale 默认 `setup` 会引导用户在浏览器确认 OAuth；`install` 只安装、不登录。两者都不覆盖原配置，见 [Codewhale 安装与配置](CODEWHALE.md)。

## Codewhale

菜单新增第 8 项 `codewhale`（Termux 为第 6 项），进入安装、登录、选模型启动、余额/用量和登出子菜单，原有工具编号不变。可直接运行 `bash codewhale.sh` 或 `.\codewhale.ps1` 完成安装和授权；非交互环境必须显式使用 `install`。需要服务端先部署 `lmm-codewhale` 注册，安装成功不代表生产登录已验证。

## OpenCode

运行 `bash opencode.sh` 或 `.\opencode.ps1` 安装官方最新版 OpenCode（最近验证 **1.18.34**） 和独立仓库 [opencode-lmm-auth](https://github.com/TokenNotIncluded/opencode-lmm-auth) 的最新正式 Release 插件。桌面菜单第 9 项提供同一入口；不限制宿主版本更新；不在 Termux 菜单显示。

需要 Node.js 22.19+、npm、tar；运行时解析官方 GitHub 最新正式 Release，校验仓库、完整源提交、资产地址和 SHA-256，npm 单次安装使用官方 registry，不改变用户 registry 设置。插件放入用户 OpenCode 配置目录（支持 `OPENCODE_CONFIG_DIR` 和 `XDG_CONFIG_HOME`），配置中添加 `file:` 插件入口；保留 JSONC 注释、其他插件和供应商配置，修改前备份，重复安装不重复添加。用户已有手动安装的同名插件时会停止并提示先处理重复来源。

安装后运行 `opencode auth login --provider lmm`，选择 **Sign in with LMM (OAuth)**，在浏览器授权，然后启动或重启 OpenCode。安装器不登录、不保存 API Key、不发起付费请求。服务端需要注册 `lmm-opencode` OAuth 客户端；本地安装与宿主加载验证不代表线上授权、余额和实际模型调用已经通过。

## 环境

Unix 入口需要 Bash、curl。Pi 主程序的依赖提示由官方处理；Pi LMM 插件和 DSH 需要 Node 22.19+（22.x）或 24+、npm；Codewhale LMM 适配器需要 Node 22+ 和 npm。不修改 npm registry。

Codex/Claude 的 Linux、macOS、Windows 安装都用官方脚本，不要求 Node，也不限定 apt 发行版。先满足上游的系统和运行库要求。Alpine 的 Claude 需要 `bash curl libgcc libstdc++ ripgrep`，运行时使用 `USE_BUILTIN_RIPGREP=0 claude`。NixOS 请使用 Nix 包环境，不保证通用二进制可运行。

Linux 桌面安装需要 `jq` 及 apt/dnf/yum/zypper，Arch 复用已安装的 paru/yay；CC Switch 在其他兼容 glibc 的系统上可用 AppImage。桌面软件仍受上游系统版本和运行库限制。macOS 需要已有 Homebrew；Windows Clash 需要已有 WinGet。系统包安装会使用 sudo 或弹出官方授权窗口。

LMM 预览包仅提供 Linux x64（glibc 2.39+）、macOS arm64、Windows x64，安装到 `~/.local/bin`，不自动改 PATH。源码安装需要 Rust 1.88+ 和编译工具；预览版 `setup` 仍不能实际安装应用。

## Termux

Pi 先运行 `pkg install nodejs npm git` 准备 Android 原生依赖，再调用同一个官方安装器；没有 `TMPDIR` 时使用 `$PREFIX/tmp`。DSH 使用同一 npm 安装方式，Android 原生依赖尚未真机验证。Codewhale 使用官方 npm 的 Android 资产选择，不回退为 Linux ARM64 二进制，仍属预览且未完成真机验收。

Codex/Claude 使用**已有的 PRoot Linux 环境**，不是 Android 原生二进制。先准备 `proot-distro` 和 Ubuntu guest，并在 guest 中安装 Bash、curl、CA 证书，再运行相应脚本。其他 guest 用 `LMM_DISTRO=名称 bash codex.sh`。安装后进入同一 guest 运行 `codex` / `claude`；不再生成转发启动器，不创建或重置 guest，不关闭沙箱。两个桌面工具不支持 Termux，菜单会隐藏它们。

## 从旧版切换

旧的 `--network`、`--root`、`--check`、`--update` 等自定义参数已移除；不要继续传入。Codex/Claude 只接受各自官方参数，DSH 可传 profile。旧版 `lmm-tools` 目录不会被删除；从 PATH 中移除旧的 `lmm-tools/bin`，避免旧启动器优先于新安装。配置和账号数据不迁移、不清空。

所有安装代码平铺在根目录；两个 Unix 桌面入口共用 `desktop.sh`，Codewhale 与 OpenCode 两个平台入口分别共用 `codewhale.mjs` 和 `opencode.mjs`。本地运行用同目录文件，单独下载运行时用固定 Git 提交获取共用脚本；Codewhale 和 OpenCode 额外校验 SHA-256。菜单原有入口继续使用固定提交，新增入口在单文件菜单的远程回退中使用 `main`；可通过 `LMM_SCRIPTS_REV=完整提交`（PowerShell 用 `$env:LMM_SCRIPTS_REV`）指定所有远程菜单入口的版本。发布前新入口只能从本地仓库运行，远程回退需等这些文件推送后才可用。不维护生成器或独立哈希清单。

## 依据与测试

2026-09-21 核查：[Pi 官网安装入口](https://pi.dev/)（[Shell](https://pi.dev/install.sh) / [PowerShell](https://pi.dev/install.ps1)）· [Codex](https://learn.chatgpt.com/docs/codex/cli) · [Claude Code](https://code.claude.com/docs/en/setup) · [Pi Termux](https://pi.dev/docs/latest/termux) · [DSH 当前 README](https://github.com/deepseek-ai/deepseek-harness/blob/master/README.md) · [DSH 插件](https://deepseek-harness.github.io/deepseek-harness/en/develop/basic/publish) · [CC Switch](https://github.com/farion1231/cc-switch#download--installation) · [Clash Verge Rev](https://www.clashverge.dev/install.html)。LMM 插件适配版本见 [Pi 插件](https://github.com/TokenNotIncluded/pi-lmm-provider) 和 [DSH 插件](https://github.com/TokenNotIncluded/dsh-lmm-provider)。Codewhale 依据和平台限制见 [专用说明](CODEWHALE.md)。

本地检查：`python3 test.py`、`pwsh -NoProfile -File test.ps1`、`shellcheck *.sh`。Codewhale 另有 `node --test test-codewhale.mjs`、`python3 test-codewhale-menu.py`、`pwsh -NoProfile -File test-codewhale.ps1`。CI 另做三平台 CLI 实装和 Debian/Alpine 实装；不把模拟测试当作桌面 GUI、Termux 真机、账号登录或代理功能实测。

OpenCode 检查：`node --test test-opencode.mjs test-opencode-entry.mjs`、`pwsh -NoProfile -File test-opencode.ps1`、`node test-opencode-install.mjs`。最后一项隔离安装两次并启动真实宿主确认 LMM OAuth 注册，不登录或调用模型。三平台 CI 分别验证官方最新宿主与最近验证的基线宿主，安装器始终安装宿主及插件的官方最新版。

新增入口检查：`python3 test-ai-tools.py`、`python3 test-codewhale-menu.py`、`pwsh -NoProfile -File test.ps1`、`shellcheck *.sh`。测试覆盖安装器地址、下载失败停止执行、官方跳过配置参数、npm/uv 错误返回、配置不触发安装、桌面资产筛选与架构、Windows WSL 路由、AstrBot 路径含空格、菜单保留原编号。CI 的 Unix 检查已加入新增脚本测试；PowerShell 7 与 Windows PowerShell 5.1 均复用扩展后的检查。新增工具尚未逐个做真实安装、账号登录、模型调用或桌面界面验收；这些离线检查不能证明上游安装器和网络在所有平台都可用。
