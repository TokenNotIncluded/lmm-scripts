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

Pi 在 Windows 上需要 **Git Bash**，或 Pi 设置中的有效 `shellPath`。脚本只检查，不覆盖你的设置，也不自动安装系统软件。

## 安装后怎么用

没有加入 PATH 时，用安装结束打印的完整路径代替下方的 `pi`、`dsh`、`lmm`。

| 工具 | 启动与登录 | 常用操作 |
|---|---|---|
| Pi | `pi` → `/login` → LMM → 浏览器授权 | `/model` 选模型；`pi -c` 继续会话；`pi list` 查看插件 |
| DSH | `dsh web` → Settings → Models → LMM → Sign in with LMM | `dsh web --no-open` 不自动开浏览器；其他参数见 `dsh --help` |
| LMM CLI | `lmm login` | `lmm catalog pi`、`lmm status`、`lmm doctor --report`、`lmm models --json` |

DSH 插件按 profile 安装，默认 `web`。使用 `headless` 前，先在相同 `DSH_HOME` 的 Web profile 完成登录。不要把 Pi、DSH 的凭据文件复制给其他客户端。

LMM CLI 的实际软件安装、接入、恢复尚未完成；`lmm setup pi --dry-run` 仅预览。`doctor` / `setup --dry-run` 返回 3 时不代表全部成功。Linux 登录需要可用的 Secret Service；SSH 或容器中不一定具备。

## Termux（原生 Android）

先准备 Termux 自己的依赖，不使用桌面 Linux 的 Node 压缩包：

```sh
pkg install bash curl coreutils nodejs npm git
curl -fsSL https://api.lmm.best/scripts/menu.sh | bash
```

安装目录保持在 `$HOME`。脚本检查 Node 是否为 Android 版本；拒绝把安装、缓存或临时目录放在 `/sdcard`、`/storage`，包括指向共享存储的链接。未设置 `TMPDIR` 时使用 `$PREFIX/tmp`，启动器使用当前 Bash 的绝对路径和明确的 Node 入口。

文本剪贴板另需 Termux:API 应用和 `pkg install termux-api`，不作为安装的强制条件。浏览器没有自动打开时，可手动用 `termux-open-url` 打开登录地址。脚本不申请存储权限、不清空缓存、不执行系统升级。

Pi 的安装方式遵循官方 Termux 文档。DSH 的 Android 原生依赖、LMM CLI 的 Android 源码构建尚未经真机验证；LMM CLI 没有 Android 预编译包。不要把环境模拟测试当成真机验证。

## 直接运行与更新

```sh
curl -fsSLo pi.sh https://api.lmm.best/scripts/pi.sh
bash pi.sh                         # 安装
bash pi.sh --check                 # 只检查可执行程序，不代表登录成功
bash pi.sh --update                # 重装脚本固定版本，不追踪上游 latest
bash pi.sh --launch                # 安装后启动
bash pi.sh --add-path              # 明确允许加入用户 PATH
bash pi.sh --network china         # 镜像优先；官方源可用 official
bash pi.sh --help                  # 全部参数
```

Windows 对应参数为 `-Check`、`-Update`、`-Launch`、`-AddPath`、`-Network china`、`-Help`。例如：

```powershell
Invoke-WebRequest https://api.lmm.best/scripts/pi.ps1 -OutFile pi.ps1
powershell -ExecutionPolicy Bypass -File .\pi.ps1
powershell -ExecutionPolicy Bypass -File .\pi.ps1 -Check
```

安装 DSH 或 LMM CLI 时，把文件名中的 `pi` 换成 `dsh` 或 `lmm`。DSH 支持 `--profile headless` / `-Profile headless`。安装脚本固定的版本见 [versions.json](versions.json)；兼容版本升级时同时更新宿主和插件，不单独追新宿主。

## 环境与故障

客户端采用用户目录下的独立安装，不覆盖系统 Node 或全局 npm 包。默认目录：Unix 为 `${XDG_DATA_HOME:-~/.local/share}/lmm-tools`，Windows 为 `%LOCALAPPDATA%\lmm-tools`；可用 `LMM_INSTALL_ROOT` 或 `--root` / `-Root` 修改。

Pi 按官方文档使用 `npm install --ignore-scripts`，接受已有的 `ignore-scripts=true`。DSH 有原生依赖，仍使用单独的构建策略；脚本不会偷偷解除用户的构建限制。Node 要求为 22.19+ 的 22.x 或 24+。

| 情况 | 处理 |
|---|---|
| Windows 提示缺少 Bash | 安装 Git for Windows 后重新打开终端；自定义 Bash 用 Pi 的 `shellPath` |
| 下载失败或停滞 | 检查 HTTPS 代理/证书，尝试 `--network official` 或 `china`；不要关闭 TLS 校验 |
| Termux 的 Pi 安装 | 先用 `pkg install nodejs git termux-api` 安装原生依赖；脚本不会下载桌面 Linux Node 代替 Android Node |
| Alpine / musl | 先用系统包管理器安装兼容的 Node/npm；官方桌面 Node 压缩包使用 glibc |
| LMM CLI 预编译包不兼容 | 当前仅 Linux x64（glibc 2.39+）、macOS arm64、Windows x64；没有 Android 包。已有 Rust 1.88+ 和编译工具时可尝试 `--from-source` |

下载缓存、校验失败处理、PATH 恢复、卸载注意事项和维护命令见 [维护说明](docs/maintenance.md)。

## 文档依据

[Pi 安装](https://pi.dev/docs/latest/quickstart) · [Windows](https://pi.dev/docs/latest/windows) · [Termux](https://pi.dev/docs/latest/termux) · [Pi 包管理](https://pi.dev/docs/latest/packages) · [DSH 官方 README](https://github.com/deepseek-ai/deepseek-harness/blob/master/README.md)

[LMM Pi 插件](https://github.com/TokenNotIncluded/pi-lmm-provider) · [LMM DSH 插件](https://github.com/TokenNotIncluded/dsh-lmm-provider)

官方文档说明宿主的使用方法；这里的隔离目录、镜像、固定版本和 LMM 登录属于本项目的集成选择，不是官方安装器。
