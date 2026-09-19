# LMM 安装与使用脚本

公开入口：[api.lmm.best/scripts](https://api.lmm.best/scripts)。所有根目录脚本都可以单独下载运行，不依赖远程 `source`、API Key 或管理员权限。

| 脚本 | 完成的工作 |
|---|---|
| `pi.sh` / `pi.ps1` | 检查/补齐 Node.js 和 npm，安装已验证版本的 Pi，安装 LMM provider，创建启动入口，引导 `/login` 和 `/model` |
| `dsh.sh` / `dsh.ps1` | 检查/补齐 Node.js，安装 DSH，下载并校验编译好的 LMM 插件，装进指定 profile，引导网页登录 |
| `lmm.sh` / `lmm.ps1` | 安装 LMM CLI 预编译包；也可显式使用已有 Rust 工具链从 crates.io 构建 |
| `lmm-use.sh` / `lmm-use.ps1` | 软件目录、状态、诊断、接入预览、登录、模型目录和退出的快捷入口，保留 CLI 的真实退出码 |

## 开始使用

Linux/macOS（以 Pi 为例，文件名可换成 `dsh.sh`、`lmm.sh`）：

```sh
curl -fsSLo pi.sh https://api.lmm.best/scripts/pi.sh
bash pi.sh
# 网络较慢时
bash pi.sh --network china
# 只检查，不下载、不修改文件
bash pi.sh --check
# 更新到当前脚本固定的已验证版本
bash pi.sh --update
```

Windows PowerShell 5.1+：

```powershell
Invoke-WebRequest https://api.lmm.best/scripts/pi.ps1 -OutFile pi.ps1
powershell -ExecutionPolicy Bypass -File .\pi.ps1
powershell -ExecutionPolicy Bypass -File .\pi.ps1 -Network china
powershell -ExecutionPolicy Bypass -File .\pi.ps1 -Check
```

也可以使用网页的操作系统按钮复制完整命令。安装过程不需要输入授权码或 API Key；首次账号授权由 Pi、DSH 或 LMM CLI 的原生登录流程完成。

默认只安装，不自动启动交互界面或模型任务。`--launch` / `-Launch` 可以安装后启动。DSH 默认 Web profile；`--profile headless` / `-Profile headless` 仅给该 profile 安装插件，登录应先通过共享同一个 `DSH_HOME` 的 Web profile 完成。

## 安装位置、重复运行与恢复

- Linux/macOS：`${XDG_DATA_HOME:-~/.local/share}/lmm-tools`。
- Windows：`%LOCALAPPDATA%\lmm-tools`。
- 自定义：环境变量 `LMM_INSTALL_ROOT`，或 `--root PATH` / `-Root PATH`。
- 客户端安装到按版本隔离的目录。仅在客户端和插件步骤成功后切换管理的启动入口；不会覆盖系统 Node 或系统全局 npm 包。
- 重复运行复用已安装客户端和下载缓存，并通过原生包管理器确认插件。`--update` / `-Update` 重新安装脚本固定的版本，保留旧的版本目录。
- 并发安装由锁拒绝。Unix 仅自动回收标记明确、进程已不存在的旧锁；未知锁保留供检查。Windows 使用操作系统文件锁，进程退出会释放。
- 默认不修改 PATH 或终端配置；需要时显式传 `--add-path` / `-AddPath`。Unix 追加带标记的段，已有启动文件先备份、不重复追加；符号链接文件不自动修改。Windows 只追加当前用户 PATH。`--no-path` / `-NoPath` 仍可明确保持不变。
- 修改 PATH 不会改变父终端的环境；安装结束会打印当前终端可立即使用的完整路径和 PATH 命令。使用了 `--add-path` / `-AddPath` 后，新开终端可直接运行工具名；否则使用打印的完整路径。
- 缓存保留在安装目录 `cache` 下；npm 优先复用用户已有 npm 缓存。不会自动清空其他软件的缓存、配置、凭据或会话。

如果某步失败，脚本返回非零并指出阶段。保留的旧启动入口不会因插件下载失败而被新入口覆盖。安装器并不声称能回滚第三方包管理器的全部内部状态。

支持构建白名单的 npm 会显式放行 Pi/DSH 已知必需的原生依赖构建，不使用“允许全部构建”开关；已有 `ignore-scripts=true` 配置会明确阻止安装而不会被偷偷覆盖。预编译 DSH 插件安装跳过其依赖的非必需生命周期脚本，避免 pnpm 的交互批准卡住管道安装。

## 网络慢、代理与镜像

`--network auto` / `-Network auto` 会先比较公共下载源的连接延迟，下载时另外监控低速和停滞；它不是“HEAD 快就一定整文件快”的假设。

- 文件下载：10 秒连接超时，20 秒低于 16 KiB/s 会中断，单次最多 10 分钟；每个源有有界重试，失败后换源。
- 部分文件保留用于断点续传；服务器不支持 Range 时重试完整下载。切换来源时不混用未验证的部分文件。
- 完整缓存每次都重新验证 SHA-256。校验不符的文件不会解压或执行。
- Node、LMM CLI 和 DSH 插件使用 `versions.json` 中固定的官方发布文件哈希。镜像只提供相同字节，不能改变期望哈希。
- Node 备用源为 npmmirror；GitHub 备用公共代理为 ghfast.top、ghproxy.net。它们可能不可用，失败后仍尝试其他源。
- `official` 仅使用官方下载地址；`china` 优先尝试镜像后回退官方。已有自定义 npm registry 配置优先保留；未自定义时根据模式选择 npm 官方或 npmmirror，并仅作用于安装进程。
- npm 设置有界请求超时和重试，自动选择的 registry 失败时尝试另一个；npm 依赖仍遵循该 registry 的包元数据/integrity 信任体系，不能把它等同于安装器内置的独立 SHA-256 固定值。
- 继承 `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY`、系统代理与 CA 环境设置，不关闭 TLS 校验，不写全局 registry/proxy 配置。curl 使用 `-q`，不读取可能包含全局认证头的 `.curlrc`；请用代理/CA 环境变量配置下载器。

示例：

```sh
HTTPS_PROXY=http://127.0.0.1:7890 bash dsh.sh --network auto
bash dsh.sh --network official --no-install-node
```

无法联网时，已安装的 CLI 和完整的已验证下载缓存仍可复用；尚未缓存的 npm 依赖仍需要网络。脚本不会把下载失败当作安装成功。

## LMM CLI 当前功能与平台边界

LMM CLI **仍是 0.1.0 开发预览**。它能进行软件发现、状态线索查询、只读诊断、`setup --dry-run`、浏览器 OAuth 登录和模型/价格目录读取。CLI 内部的实际软件安装、接入、同步、恢复等尚未实现，安装器不会伪装这些功能已完成。

预编译包来自成功的 [三平台 CI 运行](https://github.com/TokenNotIncluded/api.lmm.best/actions/runs/35434517044)：

- Linux x64：要求 glibc 2.39+；不适用于 Alpine/musl 或较旧的 glibc。
- macOS arm64。
- Windows x64。

其他支持源码构建的 x64/arm64 平台可用 `--from-source` / `-FromSource`，要求事先装好 Rust 1.88+ 和平台编译工具。首次构建可能较慢；Cargo 复用缓存。脚本不擅自安装系统包、Xcode 或 Visual Studio，也不绕过操作系统的安全提示。CLI 二进制提供 SHA-256 校验，但没有声称完成 OS 代码签名或 macOS 公证。

```sh
lmm catalog pi
lmm status
lmm doctor --report
lmm setup pi --dry-run
lmm login
lmm models --json
# 或通过使用脚本
bash lmm-use.sh catalog pi
bash lmm-use.sh plan pi
```

`doctor`、`setup --dry-run` 可能返回退出码 3，表示检查/能力尚未完成。使用脚本保留这个返回值。LMM CLI 登录使用系统凭据库；Linux 需要运行中的 Secret Service，SSH/容器不一定满足。`--no-browser` 不是设备码登录，浏览器仍须能访问该主机的本地回调端口。脚本不复制 Pi/DSH 的授权给 CLI，不自动支付或调用模型。

## 维护与验证

版本、下载地址和哈希集中在 `versions.json`。编辑 `templates/install.sh.in`、`templates/install.ps1.in` 后运行：

```sh
python3 tools/generate.py
python3 tools/generate.py --check
shellcheck *.sh
python3 tests/test_installers.py
pwsh -NoProfile -File tests/test-powershell.ps1
```

兼容原有的 `generate.py`、`--install-only` / `-InstallOnly` 和 `--no-bootstrap` / `-NoBootstrap` 入口。新版默认只安装；需要安装后启动 DSH 时显式使用 `--launch` / `-Launch`。

原有网络调优环境变量仍保留：`LMM_RETRIES`、`LMM_CONNECT_TIMEOUT`、`LMM_STALL_TIMEOUT`、`LMM_DOWNLOAD_TIMEOUT`、`LMM_COMMAND_TIMEOUT`、`LMM_CACHE_ROOT`、`LMM_NODE_BASE_URL`、`LMM_NPM_REGISTRY`。另可用 `LMM_MIN_SPEED_BYTES` 调整低速门槛。极慢链路可降低门槛并增加总超时，例如 `LMM_MIN_SPEED_BYTES=128 LMM_DOWNLOAD_TIMEOUT=3600 bash dsh.sh`。自定义源必须是没有内嵌凭据的 HTTPS 地址。

Pi/DSH 安装子进程有总超时和每 15 秒的进度心跳，超时或取消会终止本次子进程树；不会让后台 npm 继续写已经清理的暂存目录。POSIX 整个安装器包在完整函数内，管道传输截断时不会执行半个脚本。

只有根目录的八个 `.sh` / `.ps1` 脚本会被网站仓库同步器导入。模板、测试和维护工具不作为公开安装入口。发布时需同时校验各 API 节点提供的脚本内容，避免负载均衡后出现新旧版本混用。
