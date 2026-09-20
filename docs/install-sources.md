# 安装方式核查

核查日期：2026-09-20。只采用项目官方文档、官方仓库和发布包；社区教程用于定位问题，不作为自动执行来源。

| 工具 | 依据 | 本项目处理 |
|---|---|---|
| Codex | [CLI](https://developers.openai.com/codex/cli/)、[官方安装器](https://github.com/openai/codex/tree/main/scripts/install) | 原生 sh/PowerShell 安装器，`--release` / `-Release` 传版本；默认 latest，无需 npm。Linux 由上游选择架构及 libc；本项目不维护另一套二进制命名。 |
| Claude Code | [Setup](https://code.claude.com/docs/en/setup) | 官方原生安装器，默认 stable。Linux 包括 glibc/musl；Alpine 需要 `libgcc libstdc++ ripgrep` 和 `USE_BUILTIN_RIPGREP=0`。Windows 不把 Git Bash 写成硬性前提。 |
| CC Switch | [README](https://github.com/farion1231/cc-switch)、[Releases](https://github.com/farion1231/cc-switch/releases) | deb/rpm/AppImage、macOS Homebrew/DMG、Windows portable ZIP。核查到 v3.20.3；按运行时 release 的真实 asset 列表选择 x64/arm64，不混用签名文件。 |
| Clash Verge Rev | [安装文档](https://www.clashverge.dev/install.html)、[Releases](https://github.com/clash-verge-rev/clash-verge-rev/releases)、[Homebrew](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/c/clash-verge-rev.rb) | deb/rpm、现有 AUR helper、macOS Homebrew/DMG、Windows setup。核查到 v2.5.2，不杜撰 AppImage。macOS Intel 包后缀为 x64。 |
| Pi | [Quickstart](https://pi.dev/docs/latest/quickstart)、[Termux](https://pi.dev/docs/latest/termux)、[Windows](https://pi.dev/docs/latest/windows) | 保留官方 npm `--ignore-scripts`；Termux 使用原生 Node/npm；Windows 检查 Bash。LMM 插件属于本站集成，不冒称官方内置。 |
| DSH | [README](https://github.com/deepseek-ai/deepseek-harness)、[CLI](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/cli/README.md) | 保留 `dsh web` 与 profile 插件安装方式，原生构建策略单独处理。源码运行需先 build，不等同于发布包安装。 |
| LMM CLI | [项目](https://github.com/TokenNotIncluded/api.lmm.best) | 保持预览版范围：安装器安装 CLI，但 CLI 的 setup 只生成计划。未改变账号存储和 OAuth。 |

## Linux 与 Termux

Codex、Claude 不依赖发行版提供足够新的 Node。依赖安装显式使用 `--install-deps`，支持 apt、dnf/yum、zypper、pacman、apk、xbps；不进行整机升级。NixOS 需要它自己的 Nix 包环境，32 位 CPU 不在这两个官方原生 CLI 的范围内。

Claude 的新 npm 包也使用平台原生组件，不能靠 npm 就声称 Android 原生可用。Termux 入口采用 [PRoot-Distro 官方用法](https://github.com/termux/proot-distro)：用户先准备 guest，脚本再在该 guest 中运行官方安装器。`--distro` 选择已有环境，默认 ubuntu；`--install-deps` 只自动准备 Debian/Ubuntu guest 的依赖，其他 guest 按自身包管理器准备。不修改 Android 路由，不关闭 Agent 沙箱，不复制账号文件。PRoot 没有独立内核，安装成功也不表示所有沙箱能力可用。

`--dry-run` / `-DryRun` 只展示路由，不是实装验证；桌面 `--check` 只检查安装入口。真实 Android 设备、图形交互、登录及模型调用需要另外验证。官方安装器和桌面安装包仍执行自身的签名、权限与更新流程；本项目没有另外增加公共库哈希清单。
