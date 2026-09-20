from pathlib import Path
import json, re
P = Path.cwd()

def read(path): return (P/path).read_text(encoding='utf-8')
def write(path, text):
    f=P/path; f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text, encoding='utf-8', newline='\n')
def once(text, old, new):
    assert text.count(old)==1, (old[:120], text.count(old))
    return text.replace(old,new)
def take(text, name, ext):
    pattern = rf'(?m)^{re.escape(name)}\(\) \{{' if ext=='sh' else rf'(?m)^function {re.escape(name)}(?=[( {{])'
    m=re.search(pattern,text); assert m, name
    line_end=text.find('\n',m.start())
    if text[m.start():line_end].rstrip().endswith('}'):
        end=line_end+1
    else:
        end=text.index('\n}',line_end)+2
        if text[end:end+1]=='\n': end+=1
    return text[:m.start()]+text[end:], text[m.start():end]
def take_many(text, names, ext):
    parts=[]
    for name in names:
        text, part=take(text,name,ext); parts.append(part)
    return text,''.join(parts)

write('templates/lib/root.sh', '''lmm_root() {
  printf '%s\\n' "${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}"
}
''')
write('templates/lib/termux.sh', '''# Native Termux uses Android/bionic, not desktop Linux/glibc.
lmm_is_termux() {
  [ -n "${TERMUX_VERSION:-}${TERMUX_APP__PACKAGE_NAME:-}" ] ||
    case "${PREFIX:-}" in */com.termux/files/usr) true;; *) false;; esac
}
lmm_temp_root() {
  if [ -n "${TMPDIR:-}" ]; then printf '%s\\n' "$TMPDIR"
  elif lmm_is_termux; then printf '%s/tmp\\n' "${PREFIX:-$HOME/.cache/lmm-tools}"
  else printf '/tmp\\n'; fi
}
lmm_check_storage() {
  lmm_is_termux || return 0
  local resolved
  # realpath -m also resolves missing paths and symlinked storage aliases.
  command -v realpath >/dev/null 2>&1 || {
    printf 'Termux needs coreutils: pkg install coreutils\\n' >&2; return 1;
  }
  resolved=$(realpath -m -- "$1") || return 1
  case "$resolved/" in
    /sdcard/*|/storage/*|/mnt/sdcard/*|/mnt/media_rw/*|/mnt/runtime/*|/mnt/user/*|/mnt/pass_through/*)
      printf 'Use Termux private storage under HOME, not shared storage: %s\\n' "$1" >&2
      return 1;;
  esac
}
''')
sh=read('templates/install.sh.in')
sh=once(sh, 'ROOT=${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}', 'ROOT=$(lmm_root)')
sh=once(sh, 'CACHE=${LMM_CACHE_ROOT:-$ROOT/cache}', 'case "$ROOT" in /*) ;; *) ROOT="$PWD/$ROOT";; esac\nCACHE=${LMM_CACHE_ROOT:-$ROOT/cache}')
sh=once(sh, 'case "$(uname -s)" in Linux) OS=linux;; Darwin) OS=darwin;; *) fail \'This script supports Linux/macOS. On Windows use the .ps1 script.\';; esac\ncase "$(uname -m)" in x86_64|amd64) ARCH=x64;; arm64|aarch64) ARCH=arm64;; *) fail \'Unsupported CPU; use the documented source build on this platform.\';; esac\nPLATFORM="$OS-$ARCH"', '''case "$(uname -s)" in Linux|Android) OS=linux;; Darwin) OS=darwin;; *) fail 'Use the .ps1 script on Windows.';; esac
if lmm_is_termux; then OS=android; fi
case "$(uname -m)" in
  x86_64|amd64) ARCH=x64;; arm64|aarch64) ARCH=arm64;;
  armv7l|armv8l|arm) [ "$OS" = android ] || fail '32-bit desktop Linux is not supported'; ARCH=arm;;
  i386|i686) [ "$OS" = android ] || fail '32-bit desktop Linux is not supported'; ARCH=ia32;;
  *) fail 'Unsupported CPU';;
esac
PLATFORM="$OS-$ARCH"
lmm_check_storage "$ROOT" || exit 1
lmm_check_storage "$CACHE" || exit 1
if [ "$OS" = android ] && [ "$TARGET" != lmm ]; then
  compatible_node || fail 'In Termux, install native Node/npm: pkg install nodejs npm git; then rerun. Desktop Node cannot run on Android.'
  command -v git >/dev/null 2>&1 || fail 'Pi/DSH need git: pkg install git'
fi''')
sh=once(sh, '''node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit((a===22&&b>=19)||a>=24?0:1)' >/dev/null 2>&1''', '''node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(((a===22&&b>=19)||a>=24)&&(process.argv[1]!=="android"||process.platform==="android")?0:1)' "$OS" >/dev/null 2>&1''')
sh=once(sh, '''  # Android uses bionic, not the glibc used by the Linux Node archives.
  if [ -n "${TERMUX_VERSION:-}" ] || [[ ${PREFIX:-} == */com.termux/files/usr ]]; then
    fail 'In Termux, install Node with: pkg install nodejs git termux-api; then rerun. Desktop Linux Node archives cannot run on Android.'
  fi
''', '''  [ "$OS" != android ] || fail 'In Termux, run pkg install nodejs npm git; desktop Node archives are incompatible.'
''')
sh=once(sh, '''    if [ -n "${TERMUX_VERSION:-}" ] || [[ ${PREFIX:-} == */com.termux/files/usr ]]; then''', '''    if [ "$OS" = android ]; then''')
sh=once(sh, 'umask 077\nmkdir -p', '''umask 077
if [ "$OS" = android ]; then
  TMPDIR=$(lmm_temp_root); lmm_check_storage "$TMPDIR" || exit 1
  mkdir -p "$TMPDIR"; export TMPDIR
  if [ "$TARGET" = dsh ]; then log 'DSH native dependencies have not been validated on Android.'; fi
fi
mkdir -p''')
sh=once(sh, '  "$work/bin/$entry" --version >/dev/null', '  node "$work/bin/$entry" --version >/dev/null')
sh=once(sh, '    bounded "$work/bin/pnpm" --version', '    bounded node "$work/bin/pnpm" --version')
sh=once(sh, "    printf '#!/usr/bin/env bash\\n# Managed by LMM installers.\\n'", '''    if [ "$OS" = android ]; then printf '#!%s\\n' "$BASH"
    else printf '#!/usr/bin/env bash\\n'; fi
    printf '# Managed by LMM installers.\\n' ''')
sh=once(sh, '''    printf 'exec %s "$@"\\n' "$(quote_sh "$CLIENT")"''', '''    if [ "$TARGET" = lmm ]; then printf 'exec %s "$@"\\n' "$(quote_sh "$CLIENT")"
    else printf 'exec %s %s "$@"\\n' "$(quote_sh "$NODE_BIN/node")" "$(quote_sh "$CLIENT")"; fi''')
sh, hash_source=take(sh,'sha256','sh')
write('templates/lib/hash.sh', '''sha256() {
  local digest
  if command -v sha256sum >/dev/null 2>&1; then digest=$(sha256sum "$1") || return; printf '%s\\n' "${digest%% *}"
  elif command -v shasum >/dev/null 2>&1; then digest=$(shasum -a 256 "$1") || return; printf '%s\\n' "${digest%% *}"
  elif command -v openssl >/dev/null 2>&1; then digest=$(openssl dgst -sha256 "$1") || return; printf '%s\\n' "${digest##* }"
  else printf 'Install a SHA-256 tool.\\n' >&2; return 1; fi
}
''')
sh, quote=take(sh,'quote_sh','sh'); write('templates/lib/quote.sh',quote)
sh, network=take_many(sh,['rank_urls','urls_for','download'],'sh')
network=once(network, "cat \"$probe_dir\"/* | sort -n -k1,1 -k2,2 | awk '{print $2}'", "cat \"$probe_dir\"/* | sort -n -k1,1 -k2,2 | while read -r elapsed index; do printf '%s\\n' \"$index\"; done")
write('templates/lib/download.sh',network)
sh, node=take_many(sh,['compatible_node','ensure_node','configure_npm','bounded','with_registry_retry','install_client'],'sh'); write('templates/lib/node.sh',node)
sh, pnpm=take(sh,'ensure_pnpm','sh'); sh, lmm=take(sh,'install_lmm','sh')
start=sh.index('if [ "$TARGET" = lmm ]; then install_lmm\n')
end=sh.index("PHASE='launchers and PATH'",start)
sh=sh[:start]+'install_tool\n'+sh[end:]
sh=once(sh,'@@CONSTANTS@@','@@CONSTANTS@@\n@@LIBRARIES@@')
start=sh.index('  if [ "$TARGET" != lmm ]; then\n    if compatible_node;')
end=sh.index("  log 'Executable check complete",start)
write('templates/lib/node-check.sh',sh[start:end])
sh=sh[:start]+'@@NODE_CHECK@@\n'+sh[end:]
sh=sh.replace('# Generated from templates/install.sh.in and versions.json. No sudo, no API keys.', '# Generated from templates/ and versions.json. Edit the source, not this file.')
write('templates/install.sh.in',sh)
write('templates/tools/pi.sh', '''install_tool() {
  ensure_node; configure_npm
  install_client @earendil-works/pi-coding-agent "$PI_VERSION" pi
  PHASE='Pi LMM provider'
  with_registry_retry node "$CLIENT" install "npm:@tokennotincluded/pi-lmm-provider@$PI_PROVIDER_VERSION"
  if [ "$OS" = android ]; then log 'Optional clipboard: install the Termux:API app and pkg install termux-api. Open login links with termux-open-url.'; fi
}
''')
write('templates/tools/dsh.sh',pnpm+'''install_tool() {
  ensure_node; configure_npm; ensure_pnpm
  install_client @deepseek-ai/dsh "$DSH_VERSION" dsh
  PHASE='DSH LMM provider'
  local artifact="$CACHE/${DSH_PROVIDER_URL##*/}"
  download "$DSH_PROVIDER_URL" "$artifact" "$DSH_PROVIDER_SHA256"
  with_registry_retry node "$CLIENT" plugin --profile "$PROFILE" add "$artifact" --ignore-scripts --store-dir "$CACHE/pnpm"
}
''')
write('templates/tools/lmm.sh',lmm+'install_tool() { install_lmm; }\n')
ps=read('templates/install.ps1.in')
ps, common=take_many(ps,['Setting','QuoteArgument','Stop-InstallChild','Invoke-Bounded','Invoke-Native','Get-Hash'],'ps1')
write('templates/lib/common.ps1',common)
ps, network=take_many(ps,['Set-RequestProxy','New-DownloadRequest','Get-RankedUrls','Get-DownloadUrls','Receive-Stream','Get-VerifiedFile'],'ps1')
write('templates/lib/download.ps1',network)
ps, node=take_many(ps,['Test-Node','Install-Node','Set-NpmNetwork','Invoke-WithRegistryRetry','Install-Client'],'ps1')
write('templates/lib/node.ps1',node)
ps, shell=take(ps,'Assert-PiShell','ps1'); ps, pnpm=take(ps,'Install-Pnpm','ps1'); ps, lmm=take(ps,'Install-Lmm','ps1')
start=ps.index("    if ($Target -eq 'lmm') { Install-Lmm }\n")
end=ps.index("    $script:Phase='launcher and PATH'",start)
run=ps[start:end]
dsh_start=run.index('        Install-Pnpm\n')
dsh_end=run.rindex('\n      }\n    }')
dsh_body=run[dsh_start:dsh_end]
write('templates/tools/pi.ps1',shell+'''function Install-Tool {
  Install-Node; Set-NpmNetwork
  Install-Client '@earendil-works/pi-coding-agent' $PiVersion 'pi'
  $script:Phase='Pi LMM provider'
  Invoke-WithRegistryRetry $script:Client @('install',"npm:@tokennotincluded/pi-lmm-provider@$PiProviderVersion")
}
''')
write('templates/tools/dsh.ps1',pnpm+'function Install-Tool {\n  Install-Node; Set-NpmNetwork\n'+dsh_body+'\n}\n')
write('templates/tools/lmm.ps1',lmm+'function Install-Tool { Install-Lmm }\n')
ps=ps[:start]+'    Install-Tool\n'+ps[end:]
ps=once(ps,'@@CONSTANTS@@','@@CONSTANTS@@\n@@LIBRARIES@@')
write('templates/install.ps1.in',ps)
menu=read('templates/menu.sh.in')
menu,_=take(menu,'hash_file','sh')
menu=menu.replace('hash_file ', 'sha256 ')
menu=once(menu, 'set -u\n', 'set -u\n@@LIBRARIES@@\n')
menu=once(menu,'root=${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}', 'root=$(lmm_root)')
menu=once(menu,'work=$(mktemp -d "${TMPDIR:-/tmp}/lmm-menu.XXXXXXXX") || exit 1', '''umask 077
temp_root=$(lmm_temp_root)
lmm_check_storage "$temp_root" || exit 1
mkdir -p "$temp_root" || exit 1
work=$(mktemp -d "$temp_root/lmm-menu.XXXXXXXX") || exit 1''')
write('templates/menu.sh.in',menu)
use=read('lmm-use.sh')
use=once(use, 'ROOT=${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}', '@@LIBRARIES@@\nROOT=$(lmm_root)')
write('templates/use.sh.in',use)
test=read('tests/test_installers.py')
test=once(test,"for name in ['curl','uname','node','npm']:","for name in ['curl','uname','node','npm','realpath']:")
test=once(test,"if name=='uname':print('Linux' if '-s' in a else 'x86_64')", "if name=='uname':print(os.environ.get('LMM_TEST_OS','Linux') if '-s' in a else os.environ.get('LMM_TEST_ARCH','x86_64'))\nelif name=='realpath':print(os.path.realpath(a[-1]))")
test=once(test," if '-e' in a:sys.exit(0 if os.environ.get('LMM_TEST_NODE_OK','1')=='1' else 1)", """ if '-e' in a:
  ok=os.environ.get('LMM_TEST_NODE_OK','1')=='1'
  if a[-1]=='android':ok=ok and os.environ.get('LMM_TEST_NODE_PLATFORM','android')=='android'
  sys.exit(0 if ok else 1)
 if a and Path(a[0]).is_file():os.execv('/bin/bash',['bash',a[0]]+a[1:])""")
write('tests/test_installers.py',test)
v=json.loads(read('versions.json'));v['script_version']='2026.09.20.2';write('versions.json',json.dumps(v,indent=2)+'\n')
menus=read('tools/generate_menus.py')
menus=once(menus, 'import argparse, hashlib, subprocess', 'import argparse, hashlib, subprocess\nfrom render import emit, libraries')
start=menus.index('    data=text.encode(')
menus=menus[:start]+'''    if ext=='sh': text=text.replace('@@LIBRARIES@@',libraries('lib/root.sh','lib/hash.sh','lib/termux.sh'))
    emit(f'menu.{ext}',text,args.check,'utf-8-sig' if ext=='ps1' else 'utf-8')
'''
write('tools/generate_menus.py',menus)
policy=read('tests/test_official_policy.py')
start=policy.index("if __name__ == '__main__':")
policy=policy[:start]+read('tools/_termux_tests.txt')+'\n'+policy[start:]
write('tests/test_official_policy.py',policy)
readme=read('README.md');pos=readme.index('## 直接运行与更新')
readme=readme[:pos]+'''## Termux（原生 Android）

先准备 Termux 自己的依赖，不使用桌面 Linux 的 Node 压缩包：

```sh
pkg install bash curl coreutils nodejs npm git
curl -fsSL https://api.lmm.best/scripts/menu.sh | bash
```

安装目录保持在 `$HOME`。脚本检查 Node 是否为 Android 版本；拒绝把安装、缓存或临时目录放在 `/sdcard`、`/storage`，包括指向共享存储的链接。未设置 `TMPDIR` 时使用 `$PREFIX/tmp`，启动器使用当前 Bash 的绝对路径和明确的 Node 入口。

文本剪贴板另需 Termux:API 应用和 `pkg install termux-api`，不作为安装的强制条件。浏览器没有自动打开时，可手动用 `termux-open-url` 打开登录地址。脚本不申请存储权限、不清空缓存、不执行系统升级。

Pi 的安装方式遵循官方 Termux 文档。DSH 的 Android 原生依赖、LMM CLI 的 Android 源码构建尚未经真机验证；LMM CLI 没有 Android 预编译包。不要把环境模拟测试当成真机验证。

'''+readme[pos:]
write('README.md',readme)
maintenance=read('docs/maintenance.md')
maintenance=maintenance.replace('只修改模板和版本清单，再生成根目录脚本。公开脚本必须能独立运行；不要添加远程 `source` 依赖。', '''公共函数放在 `templates/lib/`，Pi、DSH、LMM 的差异放在 `templates/tools/`。`tools/render.py` 负责共用的文本读取、完整管道包装和生成检查；`tools/generate.py` 只组装当前工具需要的代码、版本和哈希。菜单复用同一份根目录、哈希和 Termux 函数，`lmm-use.sh` 也从模板生成。

只修改这些源文件和版本清单，再生成根目录脚本。`.sh` 与 `.ps1` 都保留单文件入口，不在运行时下载或 `source` 公共库；网站现有同步清单无需增加运行时文件。Windows/Linux/macOS 的编码和完整脚本校验保持不变。''')
write('docs/maintenance.md',maintenance)
