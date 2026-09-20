# 维护与恢复

## 下载与文件

下载保留缓存和断点；完整文件每次校验 SHA-256。校验失败的压缩包不会执行。官方发布文件的地址和哈希在 `versions.json`，镜像不能改变期望哈希。npm 依赖仍依赖所选 registry 的元数据和 integrity，不能等同于这里单独固定的文件哈希。

默认 `auto` 比较公共源延迟，传输期间另设低速、停滞和总超时。`official` 仅使用官方下载地址，`china` 镜像优先。已有自定义 registry 优先保留，安装过程不写全局 npm 配置，不关闭 TLS 校验。

配置项：`LMM_RETRIES`、`LMM_CONNECT_TIMEOUT`、`LMM_STALL_TIMEOUT`、`LMM_DOWNLOAD_TIMEOUT`、`LMM_COMMAND_TIMEOUT`、`LMM_MIN_SPEED_BYTES`、`LMM_CACHE_ROOT`、`LMM_NODE_BASE_URL`、`LMM_NPM_REGISTRY`。继承代理/CA 环境；自定义下载源须使用无内嵌凭据的 HTTPS URL。

重复安装复用客户端及缓存。更新采用独立目录，客户端和插件安装成功后才切换启动入口；插件失败不覆盖旧入口。第三方包管理器的内部状态不保证可自动回滚。不要直接删除不认识的安装锁或覆盖没有 `.lmm-managed` 标记的目录。

## PATH、卸载与账号

默认不修改终端启动文件。`--add-path` 在 Unix 追加带标记的 PATH 段并备份已有文件，不自动修改符号链接；Windows 只修改用户 PATH。新终端才会读到持久化 PATH。

安装器暂不提供自动卸载。只删除某个工具的受管启动入口和对应 `apps/<工具>` 目录；Node、pnpm 和缓存可能由其他工具共享，不能随手删除整个根目录。需要移除 PATH 时，删掉 Unix 启动文件中的 `LMM tools PATH` 段，或 Windows 用户 PATH 中对应的 `bin` 项。

Pi 插件可用原生命令 `pi remove npm:@tokennotincluded/pi-lmm-provider` 移除。DSH 插件维护以 `dsh plugin --help` 和当前 profile 的原生设置为准。删除客户端不等于退出账号；先在客户端退出，需要撤销授权时再到 LMM 账号管理中撤销。保留 `~/.pi/agent`、`DSH_HOME` 的设置与会话，除非你明确要删除这些数据。

## 开发与检查

```sh
python3 tools/generate.py
python3 tools/generate.py --check
python3 tools/generate_menus.py --check
shellcheck *.sh
python3 tests/test_installers.py
python3 tests/test_official_policy.py
pwsh -NoProfile -File tests/test-powershell.ps1
pwsh -NoProfile -File tests/test-official-policy.ps1
```

只修改模板和版本清单，再生成根目录脚本。公开脚本必须能独立运行；不要添加远程 `source` 依赖。

菜单的 `revision` 固定到含有目标脚本的提交，并按该提交计算 SHA-256。更新安装器后，先提交安装器，再更新 `tools/generate_menus.py` 中的 `revision` 并生成菜单，避免入口仍取旧代码。线上同步由网站仓库负责；源码提交和线上节点同步是两回事。

CI 区分模拟故障测试、真实安装测试和登录测试。前两者通过不代表真实账号 OAuth、模型调用或所有操作系统已经验证；本仓库不在 CI 中提交账号凭据或发起付费模型调用。

兼容参数 `--install-only` / `-InstallOnly`、`--no-bootstrap` / `-NoBootstrap`、顶层 `generate.py` 继续保留。
