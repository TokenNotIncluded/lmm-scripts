# Generated from templates/install.ps1.in and versions.json. PowerShell 5.1+.
[CmdletBinding(PositionalBinding=$false)]
param(
  [string]$Root = '',
  [ValidateSet('auto','official','china')][string]$Network = 'auto',
  [ValidateSet('web','headless')][string]$Profile = 'web',
  [switch]$Check, [switch]$Update, [switch]$Launch, [switch]$NoPath,
  [switch]$NoInstallNode, [switch]$FromSource, [switch]$Help,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$RunArgs = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Target = 'dsh'
$ScriptVersion = '2026.09.19.1'
$NodeVersion = '24.21.0'
$PiVersion = '0.85.1'
$PiProviderVersion = '0.1.0-alpha.1'
$DshVersion = '0.1.5-rc.2'
$DshProviderUrl = 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/v0.1.0-alpha.2/tokennotincluded-dsh-lmm-provider-0.1.0-alpha.2.tgz'
$DshProviderSha256 = '609eba9f1516cadf7086e44d290752d1361ac607eb1d1cb5682abfa5e806304d'
$LmmVersion = '0.1.0'
$LmmReleaseBase = 'https://github.com/TokenNotIncluded/api.lmm.best/releases/download/lmm-cli-v0.1.0'
$NodeHashes = @{
  'linux-x64' = '6e1db87ef58b8819e5d5402eff1536491b18edd8eb7bee5ef7897876e88dc5ff'
  'linux-arm64' = '724282c3b43aec998aa9527380465b45d229e021b58035f5f4f63095eabfe5d5'
  'darwin-x64' = '1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097'
  'darwin-arm64' = 'bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057'
  'win-x64' = '158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541'
  'win-arm64' = '8779b1bde1d39f8d420e3b57aa657b39891af434d3de44a919044cec06785921'
}
$LmmHashes = @{
  'linux-x64' = '292a1ff8b599466f52747867a0b14bd14860faefaa085cc60746040cd7eba9b7'
  'darwin-arm64' = '8f6b3a2d08500566b528b7089664420d3395e464c172e3a43dfcb73d37f57b3f'
  'win-x64' = 'd0eb3c3d3fe695eaa8a85de7c3161d0f7f17153064db5c20b8ced09defc574a9'
}

$script:Stage = $null; $script:LockHandle = $null; $script:Phase = 'arguments'
$script:Client = $null; $script:NodeBin = $null; $script:NpmSelected = $false
function Write-Log([string]$Message) { Write-Host "[lmm $Target] $Message" }
function Stop-Setup([string]$Message) { throw $Message }
function Show-Usage {
  Write-Host @"
LMM $Target installer $ScriptVersion
Usage: .\$Target.ps1 [-Check] [-Update] [-Root PATH] [-Network auto|official|china]
                    [-Profile web|headless] [-NoPath] [-NoInstallNode]
                    [-FromSource] [-Launch] [-Help]
Per-user installation; no administrator, login or paid model call is required.
Downloads are cached, resumed, retried and SHA-256 checked. Existing system Node,
npm proxy/registry configuration and credentials are preserved.
-FromSource is for the LMM CLI and requires existing Rust 1.88+ and build tools.
"@
}
function Invoke-Native([string]$Command, [string[]]$Arguments) {
  $global:LASTEXITCODE = 0
  & $Command @Arguments | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) { throw "Native command failed (exit $LASTEXITCODE) during $script:Phase." }
}
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Test-Node {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $node -or -not $npm) { return $false }
  & $node.Source -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit((a===22&&b>=19)||a>=24?0:1)' 2>$null
  return ($LASTEXITCODE -eq 0)
}
function Get-RankedUrls([string[]]$Urls) {
  $scores = @(); $index = 0
  foreach ($url in $Urls) {
    $timer = [Diagnostics.Stopwatch]::StartNew(); $score = 999999
    try {
      $request = [Net.HttpWebRequest]::Create($url)
      $request.Method = 'HEAD'; $request.Timeout = 4000; $request.AllowAutoRedirect = $true
      $response = $request.GetResponse(); $response.Close(); $score = $timer.ElapsedMilliseconds
    } catch { } finally { $timer.Stop() }
    $scores += [pscustomobject]@{ Url=$url; Score=$score; Order=$index }; $index++
  }
  return @($scores | Sort-Object Score,Order | ForEach-Object { $_.Url })
}
function Get-DownloadUrls([string]$Official) {
  $mirrors = @()
  if ($Official.StartsWith('https://nodejs.org/dist/')) { $mirrors = @($Official.Replace('https://nodejs.org/dist/','https://npmmirror.com/mirrors/node/')) }
  elseif ($Official.StartsWith('https://github.com/')) { $mirrors = @("https://ghfast.top/$Official", "https://ghproxy.net/$Official") }
  if ($Network -eq 'official') { return @($Official) }
  if ($Network -eq 'china') { return @($mirrors) + @($Official) }
  return @(Get-RankedUrls (@($Official) + @($mirrors)))
}
function Receive-Stream([string]$Url, [string]$Path) {
  # Used on older Windows without curl.exe. ReadWriteTimeout bounds stalled reads.
  $offset = 0L
  if (Test-Path -LiteralPath $Path) { $offset = (Get-Item -LiteralPath $Path).Length }
  $request = [Net.HttpWebRequest]::Create($Url)
  $request.Timeout = 10000; $request.ReadWriteTimeout = 20000; $request.AllowAutoRedirect = $true
  if ($offset -gt 0) { $request.AddRange($offset) }
  $response = $null; $inputStream = $null; $outputStream = $null
  try {
    $response = $request.GetResponse()
    if ($response.ResponseUri.Scheme -ne 'https') { throw 'Insecure redirect refused.' }
    $mode = [IO.FileMode]::Create
    if ($offset -gt 0 -and [int]$response.StatusCode -eq 206) { $mode = [IO.FileMode]::Append }
    $inputStream = $response.GetResponseStream()
    $outputStream = [IO.File]::Open($Path,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $buffer = New-Object byte[] 65536; $windowBytes = 0L; $total = 0L
    $window = [Diagnostics.Stopwatch]::StartNew(); $overall = [Diagnostics.Stopwatch]::StartNew()
    while (($read = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
      $outputStream.Write($buffer,0,$read); $windowBytes += $read; $total += $read
      if ($overall.Elapsed.TotalSeconds -gt 600) { throw 'Download timeout.' }
      if ($window.Elapsed.TotalSeconds -ge 20 -and ($response.ContentLength -lt 0 -or $total -lt $response.ContentLength)) {
        if ($windowBytes / $window.Elapsed.TotalSeconds -lt 16384) { throw 'Download too slow; changing source.' }
        $window.Restart(); $windowBytes = 0
      }
    }
  } finally {
    if ($outputStream) { $outputStream.Dispose() }; if ($inputStream) { $inputStream.Dispose() }; if ($response) { $response.Close() }
  }
}
function Get-VerifiedFile([string]$Url, [string]$Destination, [string]$Expected) {
  if (-not $Update -and (Test-Path -LiteralPath $Destination) -and (Get-Hash $Destination) -eq $Expected) { Write-Log "Cached: $([IO.Path]::GetFileName($Destination))"; return }
  $partial = "$Destination.part"; $sourceFile = "$partial.url"
  if ((Test-Path -LiteralPath $partial) -and (Get-Hash $partial) -eq $Expected) { Move-Item -LiteralPath $partial -Destination $Destination -Force; return }
  $sourceNumber = 0
  foreach ($source in @(Get-DownloadUrls $Url)) {
    $sourceNumber++
    if ((Test-Path -LiteralPath $partial) -and (!(Test-Path -LiteralPath $sourceFile) -or (Get-Content -LiteralPath $sourceFile -Raw).Trim() -ne $source)) { Remove-Item -LiteralPath $partial -Force }
    Set-Content -LiteralPath $sourceFile -Value $source -Encoding ASCII
    foreach ($attempt in 1,2) {
      Write-Log "Downloading $([IO.Path]::GetFileName($Destination)) (source $sourceNumber, attempt $attempt)"
      try {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
          Invoke-Native $curl.Source @('-q','--proto','=https','--proto-redir','=https','-fL','--connect-timeout','10','--max-time','600','--speed-time','20','--speed-limit','16384','--continue-at','-','--output',$partial,$source)
        } else { Receive-Stream $source $partial }
        if ((Get-Hash $partial) -ne $Expected) { Remove-Item -LiteralPath $partial -Force; Write-Log 'Checksum mismatch; download will not be executed.'; break }
        Move-Item -LiteralPath $partial -Destination $Destination -Force
        Remove-Item -LiteralPath $sourceFile -Force -ErrorAction SilentlyContinue
        return
      } catch {
        Write-Log 'Transfer failed or stalled. Retrying, then trying another source.'
        if ($attempt -eq 1 -and (Test-Path -LiteralPath $partial)) {
          # Keep a partial for retry; a rejected Range gets a clean retry next source.
          if ($curl -and $LASTEXITCODE -in @(22,33,36)) { Remove-Item -LiteralPath $partial -Force }
        }
      }
    }
  }
  throw 'All download sources failed. Retry -Network official or -Network china; inspect your proxy/CA settings.'
}
function Install-Node {
  $script:Phase = 'Node.js runtime'
  if (Test-Node) { $script:NodeBin = Split-Path (Get-Command node.exe).Source; return }
  $directory = Join-Path $Root "runtime\node-v$NodeVersion-$Platform"
  if (Test-Path -LiteralPath (Join-Path $directory 'node.exe')) { $env:PATH = "$directory;$env:PATH" }
  if (Test-Node) { $script:NodeBin = $directory; return }
  if ($NoInstallNode) { throw 'Need Node 22.19+ (22.x) or Node 24+, including npm.' }
  $hash = $NodeHashes[$Platform]
  if (-not $hash) { throw "No verified Node archive for $Platform" }
  $name = "node-v$NodeVersion-$Platform.zip"; $archive = Join-Path $Root "cache\$name"
  Get-VerifiedFile "https://nodejs.org/dist/v$NodeVersion/$name" $archive $hash
  $unpack = Join-Path $script:Stage 'runtime'; Expand-Archive -LiteralPath $archive -DestinationPath $unpack
  $extracted = Join-Path $unpack "node-v$NodeVersion-$Platform"
  Invoke-Native (Join-Path $extracted 'node.exe') @('--version')
  if (Test-Path -LiteralPath $directory) { throw "Managed runtime is present but unusable; inspect $directory before replacing." }
  Move-Item -LiteralPath $extracted -Destination $directory
  $script:NodeBin = $directory; $env:PATH = "$directory;$env:PATH"
}
function Set-NpmNetwork {
  if (-not $env:npm_config_cache) { $cache=(& npm.cmd config get cache 2>$null | Out-String).Trim(); if ($cache) { $env:npm_config_cache=$cache } else { $env:npm_config_cache=Join-Path $Root 'cache\npm' } }
  $env:npm_config_fetch_retries='2'; $env:npm_config_fetch_timeout='120000'; $env:npm_config_prefer_offline='true'
  $current = (& npm.cmd config get registry 2>$null | Out-String).Trim()
  if ($env:npm_config_registry -or ($current -and $current -ne 'https://registry.npmjs.org/')) { Write-Log 'Keeping your existing npm registry/proxy configuration.'; return }
  $script:NpmSelected = $true
  if ($Network -eq 'china') { $env:npm_config_registry='https://registry.npmmirror.com/' }
  elseif ($Network -eq 'official') { $env:npm_config_registry='https://registry.npmjs.org/' }
  else { $env:npm_config_registry = @(Get-RankedUrls @('https://registry.npmjs.org/','https://registry.npmmirror.com/'))[0] }
  Write-Log 'Registry selection affects this process only, not your global npm configuration.'
}
function Invoke-WithRegistryRetry([string]$Command,[string[]]$Arguments) {
  try { Invoke-Native $Command $Arguments } catch {
    if ($Network -ne 'auto' -or -not $script:NpmSelected) { throw }
    if ($env:npm_config_registry -eq 'https://registry.npmjs.org/') { $env:npm_config_registry='https://registry.npmmirror.com/' } else { $env:npm_config_registry='https://registry.npmjs.org/' }
    Write-Log 'Retrying with the alternate registry and the same cache.'
    Invoke-Native $Command $Arguments
  }
}
function Install-Client([string]$Package,[string]$Version,[string]$Entry) {
  $script:Phase="$Target client"; $destination=Join-Path $Root "apps\$Target\$Version"
  if (-not $Update -and (Test-Path -LiteralPath (Join-Path $destination "$Entry.cmd")) -and (Test-Path -LiteralPath (Join-Path $destination '.lmm-managed')) -and (Get-Content -LiteralPath (Join-Path $destination '.lmm-managed') -Raw).Trim() -eq "$Version|$ScriptVersion") { $script:Client=Join-Path $destination "$Entry.cmd"; return }
  $work=Join-Path $script:Stage 'client'; New-Item -ItemType Directory -Path $work | Out-Null
  $allow='esbuild,@google/genai,protobufjs'
  if ($Target -eq 'dsh') { $allow='@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs' }
  $installArgs=@('install','--global','--prefix',$work,'--no-audit','--no-fund',"$Package@$Version")
  $npmHelp=(& npm.cmd install --help 2>$null | Out-String)
  if ($npmHelp.Contains('--allow-scripts')) { $installArgs+=@("--allow-scripts=$allow") }
  if ((& npm.cmd config get ignore-scripts 2>$null | Out-String).Trim() -eq 'true') { throw 'Your npm configuration blocks required native builds. Configure a package-specific build policy first.' }
  Invoke-WithRegistryRetry (Get-Command npm.cmd).Source $installArgs
  Invoke-Native (Join-Path $work "$Entry.cmd") @('--version')
  Set-Content -LiteralPath (Join-Path $work '.lmm-managed') -Value "$Version|$ScriptVersion"
  New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
  if (Test-Path -LiteralPath $destination) {
    if (!(Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { throw "Refusing unowned directory: $destination" }
    $destination += '-reinstall-' + [Guid]::NewGuid().ToString('N')
  }
  Move-Item -LiteralPath $work -Destination $destination; $script:Client=Join-Path $destination "$Entry.cmd"
}
function Install-Lmm {
  $script:Phase='LMM CLI'; $destination=Join-Path $Root "apps\lmm\$LmmVersion-$Platform"
  if (-not $Update -and (Test-Path -LiteralPath (Join-Path $destination 'lmm.exe')) -and (Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { $script:Client=Join-Path $destination 'lmm.exe'; return }
  $work=Join-Path $script:Stage 'lmm'
  if ($FromSource) {
    $cargo=Get-Command cargo.exe -ErrorAction SilentlyContinue
    if (-not $cargo) { throw 'Source install needs Rust 1.88+ and Visual Studio C++ Build Tools. Install those, then retry -FromSource.' }
    $cargoRoot=Join-Path $script:Stage 'cargo'
    Invoke-Native $cargo.Source @('install','lmm-cli','--version',$LmmVersion,'--locked','--root',$cargoRoot)
    New-Item -ItemType Directory -Path $work | Out-Null
    Copy-Item -LiteralPath (Join-Path $cargoRoot 'bin\lmm.exe') -Destination $work
  } else {
    $hash=$LmmHashes[$Platform]
    if (-not $hash) { throw "No prebuilt LMM CLI for $Platform yet. Use -FromSource with Rust 1.88+ and build tools." }
    $name="lmm-v$LmmVersion-$Platform.zip"; $archive=Join-Path $Root "cache\$name"
    Get-VerifiedFile "$LmmReleaseBase/$name" $archive $hash
    Expand-Archive -LiteralPath $archive -DestinationPath $work
  }
  Invoke-Native (Join-Path $work 'lmm.exe') @('--version')
  Set-Content -LiteralPath (Join-Path $work '.lmm-managed') -Value $LmmVersion
  New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
  if (Test-Path -LiteralPath $destination) {
    if (!(Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { throw "Refusing unowned directory: $destination" }
    $destination += '-reinstall-' + [Guid]::NewGuid().ToString('N')
  }
  Move-Item -LiteralPath $work -Destination $destination; $script:Client=Join-Path $destination 'lmm.exe'
}
function Write-Launcher {
  $destination=Join-Path $Root "bin\$Target.cmd"
  if ((Test-Path -LiteralPath $destination) -and !(Select-String -LiteralPath $destination -SimpleMatch 'Managed by LMM installers' -Quiet)) { throw "Refusing existing launcher: $destination" }
  if (!$script:Client.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Launcher target must remain inside the managed root.' }
  $clientRelative=$script:Client.Substring($Root.Length).TrimStart('\')
  # Keep the .cmd file ASCII: %~dp0 supports Unicode/space-containing user paths
  # without changing the user's console code page. Tail-call batch shims.
  $lines=@('@echo off','rem Managed by LMM installers','setlocal DisableDelayedExpansion')
  if ($script:NodeBin -and $script:NodeBin.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) {
    $nodeRelative=$script:NodeBin.Substring($Root.Length).TrimStart('\')
    $lines+=@("set `"PATH=%~dp0..\$nodeRelative;%PATH%`"")
  }
  $lines+=@("`"%~dp0..\$clientRelative`" %*")
  $temporary=Join-Path $script:Stage 'launcher.cmd'
  [IO.File]::WriteAllLines($temporary,$lines,[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $destination -Force
  if (-not $NoPath) {
    $bin=Join-Path $Root 'bin'; $old=[string][Environment]::GetEnvironmentVariable('Path','User')
    if (@($old -split ';' | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') }).Count -eq 0) {
      try { [Environment]::SetEnvironmentVariable('Path',($old.TrimEnd(';')+';'+$bin).TrimStart(';'),'User') }
      catch { Write-Log 'Could not update user PATH. Use the full launcher path printed below.' }
    }
    $env:PATH="$bin;$env:PATH"
  }
}
function Invoke-LmmSetup {
  if ($Help) { Show-Usage; return }
  if ($env:OS -ne 'Windows_NT') { throw 'Use the .sh installer on Linux/macOS.' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  if (-not $Root) { if ($env:LMM_INSTALL_ROOT) { $script:Root=$env:LMM_INSTALL_ROOT } else { $script:Root=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'lmm-tools' } }
  $script:Root=[IO.Path]::GetFullPath($Root)
  if ($Root.Contains("`r") -or $Root.Contains("`n") -or $Root -eq [IO.Path]::GetPathRoot($Root)) { throw 'Choose a dedicated installation path without newlines.' }
  $arch=$env:PROCESSOR_ARCHITECTURE
  if ($env:PROCESSOR_ARCHITEW6432) { $arch=$env:PROCESSOR_ARCHITEW6432 }
  if ($arch -eq 'ARM64') { $script:Platform='win-arm64' }
  elseif ([Environment]::Is64BitOperatingSystem) { $script:Platform='win-x64' }
  else { throw 'These installers require 64-bit Windows.' }
  if ($FromSource -and $Target -ne 'lmm') { throw '-FromSource is only for LMM CLI.' }
  if ($Check) {
    Write-Log "Platform: $Platform; root: $Root"
    $entry=Join-Path $Root "bin\$Target.cmd"
    if (Test-Path -LiteralPath $entry) { Invoke-Native $entry @('--version') }
    else { $command=Get-Command $Target -ErrorAction SilentlyContinue; if (!$command) { throw "$Target is not installed" }; Invoke-Native $command.Source @('--version') }
    Write-Log 'Executable check complete; login and model availability are not inferred.'; return
  }
  foreach($dir in @($Root,(Join-Path $Root 'cache'),(Join-Path $Root 'bin'),(Join-Path $Root 'apps'),(Join-Path $Root 'runtime'))) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  try {
    $script:LockHandle=[IO.File]::Open((Join-Path $Root '.setup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  } catch { throw 'Another LMM installer is running. Wait for it to finish.' }
  try {
    $script:Stage=Join-Path $Root ('.setup-'+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:Stage | Out-Null
    if ($Target -eq 'lmm') { Install-Lmm }
    else {
      Install-Node; Set-NpmNetwork
      if ($Target -eq 'pi') {
        Install-Client '@earendil-works/pi-coding-agent' $PiVersion 'pi'
        $script:Phase='Pi LMM provider'; Invoke-WithRegistryRetry $script:Client @('install',"npm:@tokennotincluded/pi-lmm-provider@$PiProviderVersion")
      } else {
        Install-Client '@deepseek-ai/dsh' $DshVersion 'dsh'
        $script:Phase='DSH LMM provider'; $archive=Join-Path $Root ('cache\'+($DshProviderUrl.Split('/')[-1]))
        Get-VerifiedFile $DshProviderUrl $archive $DshProviderSha256
        Invoke-WithRegistryRetry $script:Client @('plugin','--profile',$Profile,'add',$archive,'--ignore-scripts','--store-dir',(Join-Path $Root 'cache\pnpm'))
      }
    }
    $script:Phase='launcher and PATH'; Write-Launcher
    Write-Log "Ready: $(Join-Path $Root "bin\$Target.cmd")"
    Write-Log 'Open a new terminal for the updated PATH, or use the full path above.'
    switch($Target) {
      pi { Write-Log 'Run pi, then /login -> LMM -> browser approval -> /model.' }
      dsh { Write-Log 'Run dsh web -> Settings -> Models -> Sign in with LMM -> Open LMM sign-in. Headless profiles share login only when DSH_HOME is the same.' }
      lmm { Write-Log 'Preview commands: lmm catalog; lmm status; lmm doctor --report; lmm login; lmm models --json. Application setup remains dry-run only.' }
    }
    if ($Launch) {
      if ($Target -eq 'lmm' -and $RunArgs.Count -eq 0) { $RunArgs=@('--help') }
      $script:Phase='launch'; $entry=Join-Path $Root "bin\$Target.cmd"
      if ($Target -eq 'dsh') { Invoke-Native $entry (@('--profile',$Profile)+$RunArgs) } else { Invoke-Native $entry $RunArgs }
    }
  } finally {
    if ($script:Stage -and (Test-Path -LiteralPath $script:Stage)) { Remove-Item -LiteralPath $script:Stage -Recurse -Force }
    if ($script:LockHandle) { $script:LockHandle.Dispose() }
  }
}
try { Invoke-LmmSetup } catch { Write-Error "Stopped during $script:Phase. $($_.Exception.Message)" -ErrorAction Continue; exit 1 }
