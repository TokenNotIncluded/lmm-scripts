from pathlib import Path
import json

P = Path(__file__).resolve().parents[1]

def replace(path, old, new):
    file = P / path
    body = file.read_text(encoding='utf-8')
    if body.count(old) != 1:
        raise RuntimeError(f'{path}: expected one match: {old[:100]!r}; found {body.count(old)}')
    file.write_text(body.replace(old, new), encoding='utf-8')

replace('tools/generate.py',
        '"""Compose only the shared code and target adapter needed by each installer."""',
        '"""Generate small installers that load common functions from a pinned revision."""')
replace('tools/generate.py',
        "    'script_version': ('SCRIPT_VERSION', 'ScriptVersion'),",
        "    'script_version': ('SCRIPT_VERSION', 'ScriptVersion'),\n    'library_revision': ('LIB_REVISION', 'LibRevision'),")
replace('tools/generate.py',
        "    versions = json.loads((ROOT / 'versions.json').read_text(encoding='utf-8'))",
        "    versions = json.loads((ROOT / 'versions.json').read_text(encoding='utf-8'))\n    if not re.fullmatch(r'[0-9a-f]{40}', versions['library_revision']):\n        raise ValueError('library_revision must be a full Git commit ID')")
replace('tools/generate.py',
        "parts = ['lib/root.sh', 'lib/hash.sh', 'lib/termux.sh', 'lib/quote.sh']",
        "parts = ['lib/hash.sh', 'lib/termux.sh', 'lib/quote.sh']")
replace('tools/generate.py',
        "            body = template(f'install.{ext}.in').replace('@@LIBRARIES@@', libraries(*parts))",
        '''            shared = libraries(*parts[:-1])
            names = [part.rsplit('/', 1)[1] for part in parts[:-1]]
            loader = template(f'load.{ext}.in') + '\\n' + libraries(parts[-1])
            if ext == 'sh':
                imports = 'for library in ' + ' '.join(names) + '; do\\n  lmm_source_lib "$library" || exit $?\\ndone'
            else:
                imports = "foreach ($library in @(" + ','.join("'" + name + "'" for name in names) + ")) {\\n    . (Get-LmmLibrary $library)\\n  }"
            body = template(f'install.{ext}.in').replace('@@LIBRARIES@@', loader)
            body = body.replace('@@LOAD_LIBRARIES@@', imports)''')
replace('tools/generate.py',
        "body = body.replace('@@CONSTANTS@@', constants(versions, target, ext, body))",
        "body = body.replace('@@CONSTANTS@@', constants(versions, target, ext, body + '\\n' + shared))")
replace('tools/render.py',
        '"""Build-time composition only: published scripts never source remote helpers."""',
        '"""Shared rendering and byte-for-byte checks for installer and menu entry points."""')
replace('templates/install.sh.in', 'ROOT=$(lmm_root)',
        'ROOT=${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}')
replace('templates/install.sh.in',
        'case "$(uname -s)" in Linux|Android)',
        '@@LOAD_LIBRARIES@@\ncase "$(uname -s)" in Linux|Android)')
replace('templates/install.sh.in',
        '# --check never creates directories, downloads, edits PATH or touches credentials.',
        '# --check does not write files; common modules may be fetched into memory.')
replace('templates/install.sh.in',
        'No automatic login or PATH changes. Versions and platform notes: README.md.',
        'Common functions load from GitHub. LMM_LIB_DIR selects local libraries (no fetch).\nNo automatic login or PATH changes. See README.md.')
replace('templates/install.ps1.in',
        'try { Invoke-LmmSetup; exit 0 }',
        '''try {
  if ($Help) { Show-Usage; exit 0 }
  $script:Phase='libraries'
  @@LOAD_LIBRARIES@@
  $script:Phase='arguments'
  Invoke-LmmSetup; exit 0
}''')
replace('templates/install.ps1.in',
        'No automatic login or PATH changes. Pi on Windows requires Bash.',
        'Common functions load from GitHub. LMM_LIB_DIR selects local libraries (no fetch).\nNo automatic login or PATH changes. Pi on Windows requires Bash.')

replace('tests/test_installers.py',
        "  for k in list(self.env):",
        "  self.env['LMM_LIB_DIR']=str(P/'templates/lib')\n  for k in list(self.env):")
file = P / 'tests/test_official_policy.py'
text = file.read_text(encoding='utf-8')
start = text.index('    def test_shared_helpers_are_embedded_once_and_remain_offline(self):')
end = text.index('    def test_every_generated_shell_help_is_standalone(self):', start)
text = text[:start] + '''    def test_shared_helpers_are_loaded_not_copied(self):
        for target in ('pi', 'dsh', 'lmm'):
            body = (P / f'{target}.sh').read_text(encoding='utf-8')
            for definition in ('lmm_is_termux() {', 'sha256() {', 'lmm_root() {', 'download() {'):
                self.assertNotIn(definition, body)
            self.assertIn('lmm_source_lib "$library"', body)
            self.assertNotIn('@@LIBRARIES@@', body)
        menu = (P / 'menu.sh').read_text(encoding='utf-8')
        self.assertEqual(menu.count('lmm_is_termux() {'), 1)
        fixtures.subprocess.run(['python3', str(P / 'tools/generate_menus.py'), '--check'], check=True)

''' + text[end:]
file.write_text(text, encoding='utf-8')
replace('tests/test-powershell.ps1',
        "$Target='test';$Network='official';$Update=$false;$script:Phase='test'",
        "foreach($library in Get-ChildItem (Join-Path $project 'templates/lib') -Filter '*.ps1') { . $library.FullName }\n$Target='test';$Network='official';$Update=$false;$script:Phase='test'")
replace('tests/test-official-policy.ps1',
        '# Only these functions are exercised; never invoke the installer or download.',
        "foreach($library in Get-ChildItem (Join-Path $project 'templates/lib') -Filter '*.ps1') { . $library.FullName }\n# Only these functions are exercised; never invoke the installer or download.")
replace('.github/workflows/test.yml',
        '          python3 tests/test_official_policy.py',
        '          python3 tests/test_official_policy.py\n          python3 tests/test_library_loader.py')
replace('.github/workflows/test.yml',
        '          ./tests/test-official-policy.ps1',
        '          ./tests/test-official-policy.ps1\n          ./tests/test-library-loader.ps1')
replace('.github/workflows/test.yml',
        '          .\\tests\\test-official-policy.ps1',
        '          .\\tests\\test-official-policy.ps1\n          .\\tests\\test-library-loader.ps1')

versions = P / 'versions.json'
v = json.loads(versions.read_text())
v['script_version'] = '2026.09.20.3'
v['library_revision'] = 'ce6aea96cd73d633424daaa6e2e25ac18fd33b5c'
versions.write_text(json.dumps(v, indent=2) + '\n', encoding='utf-8')
replace('README.md',
        '发布脚本仍可单文件运行，不需要另外下载公共函数库。',
        '安装器运行时从固定 Git 提交加载公共函数，不再把它们复制进每个发布脚本。')
replace('README.md', '## 环境与故障', '''## 公共函数加载

默认从 `versions.json` 的 `library_revision` 获取 GitHub 公共模块。Shell 完整获取文件后通过 `source <(...)` 导入；PowerShell 使用对应的点导入。没有公共模块哈希清单，不内嵌另一套备用库。下载失败就停止，不执行部分响应。

`--help` / `-Help` 不联网。`--check` / `-Check` 不修改安装文件，但默认需要联网加载公共模块。断网或调试时，明确指定同版本的本地公共目录：

```sh
LMM_LIB_DIR="$PWD/templates/lib" bash pi.sh --check
```

```powershell
$env:LMM_LIB_DIR = Join-Path $PWD 'templates/lib'
.\\pi.ps1 -Check
```

本地目录缺少模块时直接报错，不偷偷转为联网。这里只控制公共函数的来源；安装客户端仍可能需要下载软件包。`--network` 控制软件包来源，不改变公共模块的 GitHub 地址。客户端安装完成后的启动入口不需要重新获取这些模块。

## 环境与故障''')
replace('docs/maintenance.md',
        '`tools/generate.py` 只组装当前工具需要的代码、版本和哈希。',
        '`tools/generate.py` 保留入口与工具差异，生成当前工具所需的公共模块加载调用。')
replace('docs/maintenance.md',
        '`.sh` 与 `.ps1` 都保留单文件入口，不在运行时下载或 `source` 公共库；网站现有同步清单无需增加运行时文件。Windows/Linux/macOS 的编码和完整脚本校验保持不变。',
        '`.sh` 与 `.ps1` 入口通过 GitHub 固定提交获取 `templates/lib/`，不内嵌公共库；网站同步清单无需新增公共文件。模块不维护额外哈希，原有软件包和菜单的校验逻辑保留。`LMM_LIB_DIR` 可明确改用本地目录，缺文件即失败。')
replace('docs/maintenance.md',
        '菜单的 `revision` 固定到含有目标脚本的提交，',
        '公共模块的提交由 `versions.json` 中的 `library_revision` 指定。修改公共库时先提交公共库，再更新这个引用并重新生成入口；只改入口时无需修改公共模块版本。测试比较该提交中的公共文件与当前源码，避免忘记更新引用。\n\n菜单的 `revision` 固定到含有目标脚本的提交，')
replace('docs/maintenance.md',
        'python3 tests/test_official_policy.py',
        'python3 tests/test_official_policy.py\npython3 tests/test_library_loader.py')
replace('docs/maintenance.md',
        'pwsh -NoProfile -File tests/test-official-policy.ps1',
        'pwsh -NoProfile -File tests/test-official-policy.ps1\npwsh -NoProfile -File tests/test-library-loader.ps1')
