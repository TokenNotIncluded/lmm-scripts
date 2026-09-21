# Codewhale 一键安装和 LMM 配置

需要 Node.js 22+ 和 npm。Bash 入口单独下载时还需要 curl。脚本不代装 Node，不改 npm registry，不使用 sudo 或 `--force`。安装使用官方的 `npm install --global codewhale@latest`；二进制选择和校验仍由官方 npm 安装器负责。LMM 适配器安装固定 Git 提交 `8c78be0f936fb8f508badabc0195cdb21442a75d`，禁用其 npm 生命周期脚本；不依赖尚未发布的 npm 包。

## 安装并配置

Linux、macOS，或已准备好原生 Node/npm 的 Termux：

```sh
curl -fsSLo codewhale.sh https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/main/codewhale.sh
bash codewhale.sh
```

Windows PowerShell：

```powershell
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/main/codewhale.ps1 -OutFile codewhale.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\codewhale.ps1
```

默认执行 `setup`：安装、检查原生程序、通过浏览器 OAuth 登录，再询问是否选择模型启动。已有授权会保留，不会重新登录覆盖。OAuth 授权仍必须由本人在网页确认；脚本不绕过同意页。拒绝或失败不会被报告为成功。

**服务端必须先合并并部署 api.lmm.best PR #440 中的 `lmm-codewhale` 注册。** 安装成功不是生产登录成功，更不代表已完成计费验收。

## 菜单和独立命令

总菜单新增 `codewhale`：普通环境第 8 项，Termux 第 6 项，原有工具编号不变。进入后可选择安装并配置、仅安装/更新、登录、选模型启动、模型列表、登录状态、余额、用量、撤销授权或检查安装。菜单中的退出登录有二次确认。

```sh
bash codewhale.sh menu
bash codewhale.sh install       # 仅安装，适合自动化；不登录
bash codewhale.sh login
bash codewhale.sh login --no-browser
bash codewhale.sh models
bash codewhale.sh run           # 多模型时按编号选择；0 取消
bash codewhale.sh run --model '<完整目录 ID>' -- exec '检查项目测试'
bash codewhale.sh status
bash codewhale.sh balance
bash codewhale.sh usage
bash codewhale.sh logout        # 撤销失败时由适配器保留凭据
bash codewhale.sh doctor        # 原生程序 --version/--help + 适配器 --help
```

PowerShell 将 `bash codewhale.sh` 换为 `.\codewhale.ps1`。克隆仓库后也可直接运行 `node codewhale.mjs menu`，两个入口共用这一份实现。

非交互环境不能运行 `setup`/`menu`，请显式使用 `install`。非交互启动有多个模型时必须传 `--model`，不猜测模型和分组。`--no-browser` 只是手动打开授权 URL，回环回调仍需浏览器能够访问当前机器，不是 device-code 或 SSH 登录方案。

## 配置和平台边界

脚本只调用适配器，不另外复制 access/refresh token，不覆盖 Codewhale 的 TOML、shell 配置或系统 PATH。已有的 `LMM_ISSUER`、`LMM_CODEWHALE_HOME` 仍由适配器使用。正常启动显式使用官方 npm 解析到的原生二进制，而不是 Windows 的 `codewhale.cmd`；也可通过 `LMM_CODEWHALE_BIN` 指定已有原生程序的绝对路径。

`codewhale-lmm run` 在每次运行时建立临时 provider 配置，结束后清理。它不会合并用户原 TOML 中的自定义运行参数。这是伴随 CLI 接入，不是原生 `/login LMM` 插件。目前只支持目录声明的 Chat Completions 模型。

单独下载的 Bash/PowerShell 入口使用固定提交和 SHA-256 校验共用脚本；下载失败、内容不匹配或子进程失败都会停止后续步骤。克隆源码时使用同目录文件，便于维护；这不是对可修改本地目录的完整性保护。

Termux 先准备 `pkg install nodejs npm`，Codewhale Android 资产和设备支持仍属预览，不把 Linux ARM64 程序冒充 Android 程序。Windows 适配器尚无独立 ACL 加固，不适合共享 Windows 账号。现有系统/包管理器安装发生文件冲突时应先核对，不用强制覆盖绕过。

## 验证

```sh
node --test test-codewhale.mjs
python3 test-codewhale-menu.py
pwsh -NoProfile -File test-codewhale.ps1
```

Node 测试使用模拟 npm、适配器和原生程序；菜单测试实际分配伪终端，覆盖本地/远程入口、原有编号、Termux 隐藏项和失败下载。PowerShell 测试覆盖语法、帮助、引号/反斜杠参数、退出码和校验拒绝。

新增 CI 在 Ubuntu、macOS、Windows 运行离线测试，并使用隔离的 npm prefix 做真实下载安装和无账号启动检查；另覆盖 Windows PowerShell 5.1。CI 结果以对应提交为准。以上都不代替生产账号 OAuth、真实推理和 Termux 真机验收。

接口依据：[官方安装文档](https://github.com/Hmbown/Codewhale/blob/1554ac11846bc3e1423b0ee66591eea2870f10b1/docs/INSTALL.md)、[官方 npm 原生程序解析](https://github.com/Hmbown/Codewhale/blob/1554ac11846bc3e1423b0ee66591eea2870f10b1/npm/codewhale/scripts/run.js)、[LMM 适配器](https://github.com/TokenNotIncluded/codewhale-lmm-provider)。
