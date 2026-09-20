from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]

def edit(path, old, new):
    p=root/path; text=p.read_text(encoding='utf-8')
    if text.count(old)!=1: raise ValueError(f'{path}: {old[:80]} matched {text.count(old)} times')
    p.write_text(text.replace(old,new),encoding='utf-8')

for ext,names in [('sh',['release_setup','cleanup','write_launcher','add_path']),('ps1',['Write-Launcher'])]:
    p=root/f'templates/install.{ext}.in'; text=p.read_text(encoding='utf-8'); functions=[]
    for name in names:
        start=re.escape(name)+r'\(\) \{' if ext=='sh' else r'function '+re.escape(name)+r' \{'
        text,count=re.subn(r'^'+start+r'\n.*?^}\n',lambda m: functions.append(m.group(0)) or '',text,count=1,flags=re.M|re.S)
        assert count==1,(ext,name)
    p.write_text(text,encoding='utf-8')
    (root/f'templates/lib/lifecycle.{ext}').write_text('\n'.join(functions),encoding='utf-8')

edit('tools/generate.py','from render import ROOT, emit, libraries, standalone, template','from render import ROOT, emit, libraries, standalone, template\nfrom catalog import EXTERNAL')
edit('tools/generate.py',"            parts.append(f'lib/download.{ext}')", "            parts.append(f'lib/download.{ext}')\n            parts.append(f'lib/lifecycle.{ext}')")
edit('tools/generate.py',"    use = template('use.sh.in')", "    for target in EXTERNAL:\n        for ext in ('sh', 'ps1'):\n            text = template(f'external.{ext}.in').replace('@@TARGET@@', target)\n            text = text.replace('@@REVISION@@', versions['library_revision'])\n            text = text.replace('@@LOADER@@', template(f'load.{ext}.in'))\n            emit(f'{target}.{ext}', text, args.check)\n    use = template('use.sh.in')")
edit('tools/generate.py', "body = standalone(body, 'lmm_install_main')", "body = standalone(body, 'lmm_install_main').replace('lmm_install_main() {', '# State is consumed by fetched modules.\\n# shellcheck disable=SC2034\\nlmm_install_main() {', 1)")
edit('templates/lib/external.sh', 'then bash "$STAGE/install.sh" --release "$VERSION"', 'then CODEX_NON_INTERACTIVE=true bash "$STAGE/install.sh" --release "$VERSION"')
edit('templates/lib/external.sh', 'unset CODEX_HOME CODEX_INSTALL_DIR; bash /mnt/lmm-install/install.sh', 'unset CODEX_HOME CODEX_INSTALL_DIR; CODEX_NON_INTERACTIVE=true bash /mnt/lmm-install/install.sh')
edit('templates/lib/external.sh', '  local manager ext pattern metadata candidate target', '  local manager ext pattern metadata candidate target\n  [ "$LIBC" != musl ] || die "No compatible musl desktop package"')
edit('templates/lib/external.ps1', '  $stage=$null\n', "  $stage=$null\n  $oldNonInteractive=$env:CODEX_NON_INTERACTIVE\n")
edit('templates/lib/external.ps1', "    [Net.ServicePointManager]::SecurityProtocol=$oldTls -bor [Net.SecurityProtocolType]::Tls12", "    [Net.ServicePointManager]::SecurityProtocol=$oldTls -bor [Net.SecurityProtocolType]::Tls12\n    if ($Target -eq 'codex') { $env:CODEX_NON_INTERACTIVE='true' }")
edit('templates/lib/external.ps1', '    [Net.ServicePointManager]::SecurityProtocol=$oldTls\n', '    [Net.ServicePointManager]::SecurityProtocol=$oldTls\n    $env:CODEX_NON_INTERACTIVE=$oldNonInteractive\n')
edit('README.md', '## 安装后怎么用', '''## 新增工具

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

## 安装后怎么用''')
edit('README.md','默认目录：Unix 为', 'Pi/DSH/LMM 的默认目录：Unix 为')
edit('docs/maintenance.md','## 开发与检查', '''## 新增入口与菜单

`tools/catalog.py` 是工具名称、菜单顺序和入口生成的唯一清单。四个新增工具共用 `templates/lib/external.*`；旧安装器的清理、PATH 与启动器逻辑移到 `lifecycle.*`。`--dry-run` / `-DryRun` 只显示选择，不安装；默认仍需获取公共模块，本地测试可设 `LMM_LIB_DIR`。

新增工具的 `--network china` 只为本脚本下载的 GitHub 文件选择备用源，不改变官方安装器内部下载源。依赖安装只在 `--install-deps` 时进行；发行版桌面包本身通过包管理器解析依赖。桌面 `--check` 仅检查入口，不偷偷启动图形程序。

## 开发与检查''')
edit('docs/maintenance.md','python3 tests/test_library_loader.py','python3 tests/test_library_loader.py\npython3 tests/test_external.py\npython3 tests/test_catalog.py')
print('Lifecycle extraction, native installer delegation and docs updated.')
