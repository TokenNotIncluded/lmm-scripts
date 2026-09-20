from pathlib import Path
import json

P = Path(__file__).resolve().parents[1]

def replace(path, old, new):
    file = P / path
    text = file.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise RuntimeError(f'{path}: expected one match, found {text.count(old)}: {old[:100]}')
    file.write_text(text.replace(old, new), encoding='utf-8')

sh = 'templates/install.sh.in'
ps = 'templates/install.ps1.in'
replace(sh, '''  case "$TARGET" in
    pi) allow='esbuild,@google/genai,protobufjs';;
    dsh) allow='@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs';;
  esac
  INSTALL_ARGS=(install --global --prefix "$work" --no-audit --no-fund "$package@$version")
  if npm install --help 2>/dev/null | grep -q -- '--allow-scripts'; then INSTALL_ARGS+=("--allow-scripts=$allow"); fi
  [ "$(npm config get ignore-scripts 2>/dev/null || true)" != true ] || fail 'Your npm configuration disables required native build scripts. Configure a package-specific build policy before installing this client.'
''', '''  INSTALL_ARGS=(install --global --prefix "$work" --no-audit --no-fund "$package@$version")
  if [ "$TARGET" = pi ]; then
    # https://pi.dev/docs/latest/quickstart: Pi ships a prebuilt CLI.
    INSTALL_ARGS+=(--ignore-scripts)
  else
    allow='@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs'
    if npm install --help 2>/dev/null | grep -q -- '--allow-scripts'; then INSTALL_ARGS+=("--allow-scripts=$allow"); fi
    [ "$(npm config get ignore-scripts 2>/dev/null || true)" != true ] || fail 'DSH needs native build scripts. Review your package-specific build policy; this installer will not override ignore-scripts=true.'
  fi
''')
replace(ps, '''  $allow='esbuild,@google/genai,protobufjs'
  if ($Target -eq 'dsh') { $allow='@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs' }
  $installArgs=@('install','--global','--prefix',$work,'--no-audit','--no-fund',"$Package@$Version")
  $npmHelp=(& npm.cmd install --help 2>$null | Out-String)
  if ($npmHelp.Contains('--allow-scripts')) { $installArgs+=@("--allow-scripts=$allow") }
  if ((& npm.cmd config get ignore-scripts 2>$null | Out-String).Trim() -eq 'true') { throw 'Your npm configuration blocks required native builds. Configure a package-specific build policy first.' }
''', '''  $installArgs=@('install','--global','--prefix',$work,'--no-audit','--no-fund',"$Package@$Version")
  if ($Target -eq 'pi') {
    # https://pi.dev/docs/latest/quickstart: Pi ships a prebuilt CLI.
    $installArgs+=@('--ignore-scripts')
  } else {
    $allow='@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs'
    $npmHelp=(& npm.cmd install --help 2>$null | Out-String)
    if ($npmHelp.Contains('--allow-scripts')) { $installArgs+=@("--allow-scripts=$allow") }
    if ((& npm.cmd config get ignore-scripts 2>$null | Out-String).Trim() -eq 'true') { throw 'DSH needs native build scripts. Review your package-specific build policy; ignore-scripts=true will not be overridden.' }
  }
''')
replace(sh, '''  local dir="$ROOT/runtime/node-v$NODE_VERSION-$PLATFORM" hash archive
''', '''  # Android uses bionic, not the glibc used by the Linux Node archives.
  if [ -n "${TERMUX_VERSION:-}" ] || [[ ${PREFIX:-} == */com.termux/files/usr ]]; then
    fail 'In Termux, install Node with: pkg install nodejs git termux-api; then rerun. Desktop Linux Node archives cannot run on Android.'
  fi
  local dir="$ROOT/runtime/node-v$NODE_VERSION-$PLATFORM" hash archive
''')
replace(sh, '''    hash=$(lmm_hash "$PLATFORM")
''', '''    if [ -n "${TERMUX_VERSION:-}" ] || [[ ${PREFIX:-} == */com.termux/files/usr ]]; then
      fail 'No Android LMM CLI binary is provided. The Linux archive is not compatible with Termux.'
    fi
    hash=$(lmm_hash "$PLATFORM")
''')
replace(ps, '''function Set-RequestProxy($request) {
''', '''function Assert-PiShell {
  # Follow Pi's shellPath -> Git Bash -> PATH lookup, without editing settings.
  $agentDirectory=$env:PI_CODING_AGENT_DIR
  if (!$agentDirectory) { $agentDirectory=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.pi\\agent' }
  $settingsPath=Join-Path $agentDirectory 'settings.json'
  if (Test-Path -LiteralPath $settingsPath) {
    try { $settings=Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json }
    catch { throw "Invalid Pi settings: $settingsPath. Repair the JSON before installing." }
    if ($null -eq $settings) { throw "Invalid Pi settings: $settingsPath" }
    $property=$settings.PSObject.Properties['shellPath']
    if ($property -and $property.Value) {
      $shell=[string]$property.Value
      if (Test-Path -LiteralPath $shell -PathType Leaf) { return }
      if (Get-Command $shell -CommandType Application -ErrorAction SilentlyContinue) { return }
      throw "Pi shellPath does not exist: $shell. Correct it in $settingsPath."
    }
  }
  if ($env:ProgramFiles -and (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Git\\bin\\bash.exe') -PathType Leaf)) { return }
  if (Get-Command 'bash.exe' -CommandType Application -ErrorAction SilentlyContinue) { return }
  throw 'Pi requires Bash on Windows. Install Git for Windows, reopen PowerShell, or set shellPath in Pi settings. See https://pi.dev/docs/latest/windows'
}
function Set-RequestProxy($request) {
''')
replace(ps, '''  if ($Check) {
    Write-Log "Platform: $Platform; root: $Root"
''', '''  if ($Target -eq 'pi') { Assert-PiShell }
  if ($Check) {
    Write-Log "Platform: $Platform; root: $Root"
''')
replace(ps, '''      $line=@(Get-Content -LiteralPath $Command)[-1]
''', '''      $launcherLines=@(Get-Content -LiteralPath $Command)
      foreach ($pathLine in $launcherLines) {
        if ($pathLine -match '^set "PATH=%~dp0\\.\\.\\\\(.+);%PATH%"$') {
          $runtime=[IO.Path]::GetFullPath((Join-Path (Split-Path (Split-Path $Command)) $Matches[1]))
          if (!$runtime.StartsWith($Root + '\\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Managed runtime escaped its root.' }
          if (!(Test-Path -LiteralPath $runtime -PathType Container)) { throw 'Managed runtime is missing. Rerun the installer.' }
          $env:PATH="$runtime;$env:PATH"
        }
      }
      $line=$launcherLines[-1]
''')
replace(ps, '''    switch ([IO.Path]::GetFileName($Command).ToLowerInvariant()) {
      'npm.cmd' { $entry=Join-Path $parent 'node_modules\\npm\\bin\\npm-cli.js' }
      'pi.cmd' { $entry=Join-Path $parent 'node_modules\\@earendil-works\\pi-coding-agent\\dist\\bundle\\cli.js' }
      'pnpm.cmd' { $entry=Join-Path $parent 'node_modules\\pnpm\\bin\\pnpm.cjs' }
      'dsh.cmd' { $entry=Join-Path $parent 'node_modules\\@deepseek-ai\\dsh\\lib\\bin.js' }
      default { throw 'Unsupported command shim; use the managed installer or a native executable.' }
    }
''', '''    $binName=[IO.Path]::GetFileNameWithoutExtension($Command).ToLowerInvariant()
    switch ($binName) {
      'npm' { $packageName='npm' }
      'pi' { $packageName='@earendil-works/pi-coding-agent' }
      'pnpm' { $packageName='pnpm' }
      'dsh' { $packageName='@deepseek-ai/dsh' }
      default { throw 'Unsupported command shim; use the managed installer or a native executable.' }
    }
    $packageRoot=[IO.Path]::GetFullPath((Join-Path $parent ('node_modules/' + $packageName)))
    $manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Raw | ConvertFrom-Json
    $binProperty=$manifest.PSObject.Properties['bin']
    if (!$binProperty) { throw 'Package manifest has no bin entry.' }
    $bins=$binProperty.Value
    $relative=$null
    if ($bins -is [string]) { $relative=$bins }
    elseif ($null -ne $bins -and $bins.PSObject.Properties[$binName]) { $relative=$bins.PSObject.Properties[$binName].Value }
    if ($relative -isnot [string] -or !$relative -or [IO.Path]::IsPathRooted($relative)) { throw 'Invalid package bin entry.' }
    $entry=[IO.Path]::GetFullPath((Join-Path $packageRoot $relative))
    if (!$entry.StartsWith($packageRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Package bin entry escaped its package.' }
''')
replace(sh, '  --update             Reinstall the versions tested by this script', '  --update             Reinstall the versions pinned in versions.json')
replace(sh, '''Installs in user space. Existing system Node, npm configuration and login data
are not replaced. Downloads are cached, resumed and SHA-256 checked. Proxy/CA
settings are inherited. No login, paid call or OS package install is automatic.
''', '''No automatic login or PATH changes. Versions and platform notes: README.md.
''')
replace(ps, '''Per-user installation; no administrator, login or paid model call is required.
Downloads are cached, resumed, retried and SHA-256 checked. Existing system Node,
npm proxy/registry configuration and credentials are preserved.
''', '''No automatic login or PATH changes. Pi on Windows requires Bash.
''')
replace('tests/test_installers.py', "  print('https://registry.npmjs.org/' if a[-1]=='registry' else os.environ['LMM_TEST_CACHE']);sys.exit(0)", "  print('https://registry.npmjs.org/' if a[-1]=='registry' else os.environ.get('npm_config_ignore_scripts','false') if a[-1]=='ignore-scripts' else os.environ['LMM_TEST_CACHE']);sys.exit(0)")
versions = P / 'versions.json'
v = json.loads(versions.read_text())
v['script_version'] = '2026.09.20.1'
versions.write_text(json.dumps(v, indent=2) + '\n')
