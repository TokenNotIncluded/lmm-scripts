# Generated from templates/install.ps1.in and versions.json. PowerShell 5.1+.
[CmdletBinding(PositionalBinding=$false)]
param(
  [string]$Root = '',
  [ValidateSet('auto','official','china')][string]$Network = 'auto',
  [ValidateSet('web','headless')][string]$Profile = 'web',
  [switch]$Check, [switch]$Update, [switch]$Launch, [switch]$NoPath,
  [switch]$NoInstallNode, [switch]$FromSource, [switch]$Help,
  [switch]$AddPath, [switch]$InstallOnly, [switch]$NoBootstrap,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$RunArgs = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Target = 'pi'
$ScriptVersion = '2026.09.20.4'
$LibRevision = '60692bd80622a0d3d80ee501eacb8db139641a3e'
$NodeVersion = '24.21.0'
$PiVersion = '0.85.1'
$PiProviderVersion = '0.1.0-alpha.1'
$NodeHashes = @{
  'linux-x64' = '6e1db87ef58b8819e5d5402eff1536491b18edd8eb7bee5ef7897876e88dc5ff'
  'linux-arm64' = '724282c3b43aec998aa9527380465b45d229e021b58035f5f4f63095eabfe5d5'
  'darwin-x64' = '1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097'
  'darwin-arm64' = 'bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057'
  'win-x64' = '158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541'
  'win-arm64' = '8779b1bde1d39f8d420e3b57aa657b39891af434d3de44a919044cec06785921'
}

function Get-LmmLibrary([string]$Name) {
  if ($env:LMM_LIB_DIR) {
    $text=[IO.File]::ReadAllText((Join-Path $env:LMM_LIB_DIR $Name),[Text.Encoding]::UTF8)
  } else {
    $uri="https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/$LibRevision/templates/lib/$Name"
    $text=$null
    $protocol=[Net.ServicePointManager]::SecurityProtocol
    try {
      [Net.ServicePointManager]::SecurityProtocol=$protocol -bor [Net.SecurityProtocolType]::Tls12
      $options=@{Uri=$uri;UseBasicParsing=$true;TimeoutSec=60;ErrorAction='Stop'}
      $proxyValue=if($env:HTTPS_PROXY){$env:HTTPS_PROXY}else{$env:HTTP_PROXY}
      if ($proxyValue) {
        $proxy=[Uri]$proxyValue
        $options.Proxy=$proxy.GetLeftPart([UriPartial]::Authority)
        if ($proxy.UserInfo) {
          $parts=$proxy.UserInfo.Split(':',2)
          $password=if($parts.Length -eq 2){[Uri]::UnescapeDataString($parts[1])}else{''}
          $secure=ConvertTo-SecureString $password -AsPlainText -Force
          $options.ProxyCredential=New-Object System.Management.Automation.PSCredential([Uri]::UnescapeDataString($parts[0]),$secure)
        }
      }
      for ($attempt=1;$attempt -le 3;$attempt++) {
        try {
          $response=Invoke-WebRequest @options
          $text=[Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
          break
        } catch { if ($attempt -eq 3) { throw "Cannot fetch library $Name at $LibRevision. Check the network or set LMM_LIB_DIR." } }
      }
    } finally { [Net.ServicePointManager]::SecurityProtocol=$protocol }
  }
  if ([string]::IsNullOrWhiteSpace($text)) { throw "Empty library: $Name" }
  return [scriptblock]::Create($text)
}

function Assert-PiShell {
  # Follow Pi's shellPath -> Git Bash -> PATH lookup, without editing settings.
  $agentDirectory=$env:PI_CODING_AGENT_DIR
  if (!$agentDirectory) { $agentDirectory=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.pi\agent' }
  $settingsPath=Join-Path $agentDirectory 'settings.json'
  if (Test-Path -LiteralPath $settingsPath) {
    try { $settings=Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
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
  if ($env:ProgramFiles -and (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') -PathType Leaf)) { return }
  if (Get-Command 'bash.exe' -CommandType Application -ErrorAction SilentlyContinue) { return }
  throw 'Pi requires Bash on Windows. Install Git for Windows, reopen PowerShell, or set shellPath in Pi settings. See https://pi.dev/docs/latest/windows'
}
function Install-Tool {
  Install-Node; Set-NpmNetwork
  Install-Client '@earendil-works/pi-coding-agent' $PiVersion 'pi'
  $script:Phase='Pi LMM provider'
  Invoke-WithRegistryRetry $script:Client @('install',"npm:@tokennotincluded/pi-lmm-provider@$PiProviderVersion")
}

$script:InstalledSuccess=$false
$script:Stage = $null; $script:LockHandle = $null; $script:Phase = 'arguments'
$Retries=3; $ConnectTimeout=10; $StallTimeout=20; $DownloadTimeout=600; $CommandTimeout=1800; $MinSpeed=16384
$script:Cache=$null
$script:PnpmBin=$null
$script:Client = $null; $script:NodeBin = $null; $script:NpmSelected = $false
function Write-Log([string]$Message) { Write-Host "[lmm $Target] $Message" }
function Stop-Setup([string]$Message) { throw $Message }
function Show-Usage {
  Write-Host @"
LMM $Target installer $ScriptVersion
Usage: .\$Target.ps1 [-Check] [-Update] [-Root PATH] [-Network auto|official|china]
                    [-Profile web|headless] [-AddPath] [-NoPath] [-NoInstallNode]
                    [-FromSource] [-Launch] [-Help]
Common functions load from GitHub. LMM_LIB_DIR selects local libraries (no fetch).
No automatic login or PATH changes. Pi on Windows requires Bash.
-FromSource is for the LMM CLI and requires existing Rust 1.88+ and build tools.
"@
}
function Invoke-LmmSetup {
  if ($Help) { Show-Usage; return }
  $script:Retries=Setting 'LMM_RETRIES' 3 10
  $script:ConnectTimeout=Setting 'LMM_CONNECT_TIMEOUT' 10 300
  $script:StallTimeout=Setting 'LMM_STALL_TIMEOUT' 20 86400
  $script:DownloadTimeout=Setting 'LMM_DOWNLOAD_TIMEOUT' 600 86400
  $script:CommandTimeout=Setting 'LMM_COMMAND_TIMEOUT' 1800 86400
  $script:MinSpeed=Setting 'LMM_MIN_SPEED_BYTES' 16384 10485760
  foreach($value in @($env:LMM_NODE_BASE_URL,$env:LMM_NPM_REGISTRY)) { if ($value) { $uri=[Uri]$value; if ($uri.Scheme -ne 'https' -or $uri.UserInfo) { throw 'Custom mirrors require HTTPS without credentials.' } } }

  if ($env:OS -ne 'Windows_NT') { throw 'Use the .sh installer on Linux/macOS.' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  if (-not $Root) { if ($env:LMM_INSTALL_ROOT) { $script:Root=$env:LMM_INSTALL_ROOT } else { $script:Root=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'lmm-tools' } }
  $script:Root=[IO.Path]::GetFullPath($Root)
  $script:Cache=if($env:LMM_CACHE_ROOT){$env:LMM_CACHE_ROOT}else{Join-Path $Root 'cache'}
  if (![IO.Path]::IsPathRooted($script:Cache) -or [IO.Path]::GetPathRoot($script:Cache) -eq $script:Cache) { throw 'Cache root must be an absolute non-root path.' }
  foreach($directory in @($Root,$script:Cache)) { if ((Test-Path -LiteralPath $directory) -and ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing symlink/junction install or cache roots.' } }
  if ($Root.Contains("`r") -or $Root.Contains("`n") -or $Root -eq [IO.Path]::GetPathRoot($Root)) { throw 'Choose a dedicated installation path without newlines.' }
  $arch=$env:PROCESSOR_ARCHITECTURE
  if ($env:PROCESSOR_ARCHITEW6432) { $arch=$env:PROCESSOR_ARCHITEW6432 }
  if ($arch -eq 'ARM64') { $script:Platform='win-arm64' }
  elseif ([Environment]::Is64BitOperatingSystem) { $script:Platform='win-x64' }
  else { throw 'These installers require 64-bit Windows.' }
  if ($FromSource -and $Target -ne 'lmm') { throw '-FromSource is only for LMM CLI.' }
  if ($Target -eq 'pi') { Assert-PiShell }
  if ($Check) {
    Write-Log "Platform: $Platform; root: $Root"
    $entry=Join-Path $Root "bin\$Target.cmd"
    if (Test-Path -LiteralPath $entry) { Invoke-Native $entry @('--version') }
    else { $command=Get-Command $Target -ErrorAction SilentlyContinue; if (!$command) { throw "$Target is not installed" }; Invoke-Native $command.Source @('--version') }
    Write-Log 'Executable check complete; login and model availability are not inferred.'; return
  }
  foreach($dir in @($Root,$script:Cache,(Join-Path $Root 'bin'),(Join-Path $Root 'apps'),(Join-Path $Root 'runtime'))) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  try {
    $script:LockHandle=[IO.File]::Open((Join-Path $Root '.setup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  } catch { throw 'Another LMM installer is running. Wait for it to finish.' }
  try {
    $script:Stage=Join-Path $Root ('.setup-'+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:Stage | Out-Null
    Install-Tool
    $script:Phase='launcher and PATH'; Write-Launcher; $script:InstalledSuccess=$true
    Write-Log "Ready: $(Join-Path $Root "bin\$Target.cmd")"
    Write-Log 'Use the full path above. With -AddPath, new terminals can use the short command.'
    switch($Target) {
      pi { Write-Log 'Run pi, then /login -> LMM -> browser approval -> /model.' }
      dsh { Write-Log 'Run dsh web -> Settings -> Models -> Sign in with LMM -> Open LMM sign-in. Headless profiles share login only when DSH_HOME is the same.' }
      lmm { Write-Log 'Preview commands: lmm catalog; lmm status; lmm doctor --report; lmm login; lmm models --json. Application setup remains dry-run only.' }
    }
    if ($Launch -and -not $InstallOnly) {
      if ($Target -eq 'lmm' -and $RunArgs.Count -eq 0) { $RunArgs=@('--help') }
      $script:Phase='launch'; $script:LockHandle.Dispose(); $script:LockHandle=$null
      if ($Target -eq 'dsh') { & $script:Client --profile $Profile @RunArgs } else { & $script:Client @RunArgs }
      if ($LASTEXITCODE -ne 0) { throw "Client exited with code $LASTEXITCODE" }
    }
  } finally {
    if ($script:Stage -and (Test-Path -LiteralPath $script:Stage)) { Remove-Item -LiteralPath $script:Stage -Recurse -Force }
    if ($script:LockHandle) { $script:LockHandle.Dispose() }
  }
}
$savedEnvironment=@{}
foreach($name in @('PATH','npm_config_cache','npm_config_fetch_retries','npm_config_fetch_timeout','npm_config_prefer_offline','npm_config_fetch_retry_mintimeout','npm_config_fetch_retry_maxtimeout','npm_config_strict_ssl','npm_config_registry','npm_config_store_dir')) { $savedEnvironment[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
try {
  if ($Help) { Show-Usage; exit 0 }
  $script:Phase='libraries'
  foreach ($library in @('common.ps1','download.ps1','lifecycle.ps1','node.ps1')) {
    . (Get-LmmLibrary $library)
  }
  $script:Phase='arguments'
  Invoke-LmmSetup; exit 0
}
catch { Write-Error "Stopped during $script:Phase. $($_.Exception.Message)" -ErrorAction Continue; exit 1 }
finally {
  foreach($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name],'Process') }
  if ($script:InstalledSuccess -and $AddPath -and -not $NoPath) { $env:PATH=(Join-Path $Root 'bin')+';'+$env:PATH }
}
