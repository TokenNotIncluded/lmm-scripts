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
$Target = 'dsh'
$ScriptVersion = '2026.09.21.1'
$LibRevision = '7a42eebbdf13cb350f25aca8c466b1ec8964df15'
$NodeVersion = '24.21.0'
$PnpmVersion = '11.7.0'
$DshVersion = '0.1.5-rc.2'
$DshProviderUrl = 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/v0.1.0-alpha.2/tokennotincluded-dsh-lmm-provider-0.1.0-alpha.2.tgz'
$DshProviderSha256 = '609eba9f1516cadf7086e44d290752d1361ac607eb1d1cb5682abfa5e806304d'
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

function Install-Pnpm {
  $script:Phase='DSH package manager';$destination=Join-Path $Root "tools\pnpm\$PnpmVersion"
  if ((Test-Path -LiteralPath (Join-Path $destination 'pnpm.cmd')) -and (Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { $script:PnpmBin=$destination }
  elseif ($NoBootstrap) {
    $pm=Get-Command pnpm.cmd -ErrorAction SilentlyContinue
    if (!$pm) { throw 'pnpm is missing; rerun without -NoBootstrap.' }
    Invoke-Native $pm.Source @('--version');$script:PnpmBin=Split-Path $pm.Source
  } else {
    $work=Join-Path $script:Stage 'pnpm';New-Item -ItemType Directory -Path $work | Out-Null
    Invoke-WithRegistryRetry (Get-Command npm.cmd).Source @('install','--global','--prefix',$work,'--ignore-scripts','--no-audit','--no-fund',"pnpm@$PnpmVersion")
    Invoke-Native (Join-Path $work 'pnpm.cmd') @('--version')
    Set-Content -LiteralPath (Join-Path $work '.lmm-managed') -Value $PnpmVersion
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    if (Test-Path -LiteralPath $destination) {
      if (!(Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { throw 'Unowned pnpm installation directory.' }
      $destination+='-reinstall-'+[Guid]::NewGuid().ToString('N')
    }
    Move-Item -LiteralPath $work -Destination $destination;$script:PnpmBin=$destination
  }
  $env:PATH="$script:PnpmBin;$env:PATH"
}
function Install-Tool {
  Install-Node; Set-NpmNetwork
        Install-Pnpm
        Install-Client '@deepseek-ai/dsh' $DshVersion 'dsh'
        $script:Phase='DSH LMM provider'; $archive=Join-Path $script:Cache ($DshProviderUrl.Split('/')[-1])
        Get-VerifiedFile $DshProviderUrl $archive $DshProviderSha256
        # DSH 0.1.5 uses a shell to invoke pnpm on Windows. Passing absolute
        # paths containing spaces loses argument boundaries in that layer.
        # Keep the verified immutable package inside the profile and pass a
        # path-free file: spec; configure the store through environment instead.
        $profileHome=$env:DSH_HOME
        $userDirectory=[Environment]::GetFolderPath('UserProfile')
        if (!$profileHome) { $profileHome=Join-Path $userDirectory '.dsh' }
        elseif ($profileHome -eq '~') { $profileHome=$userDirectory }
        elseif ($profileHome.StartsWith('~/') -or $profileHome.StartsWith('~\')) { $profileHome=Join-Path $userDirectory $profileHome.Substring(2) }
        if (![IO.Path]::IsPathRooted($profileHome)) { $profileHome=Join-Path (Get-Location).ProviderPath $profileHome }
        $profileDirectory=Join-Path ([IO.Path]::GetFullPath($profileHome)) "profiles\$Profile"
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        $packageName='.lmm-provider-'+$DshProviderSha256.Substring(0,16)+'.tgz'
        $profilePackage=Join-Path $profileDirectory $packageName
        if (Test-Path -LiteralPath $profilePackage) {
          if ((Get-Hash $profilePackage) -ne $DshProviderSha256) { throw 'Conflicting installer package in the DSH profile; inspect it before retrying.' }
        } else {
          $pending=Join-Path $profileDirectory ('.lmm-package-'+[Guid]::NewGuid().ToString('N')+'.tmp')
          try { Copy-Item -LiteralPath $archive -Destination $pending; Move-Item -LiteralPath $pending -Destination $profilePackage -Force }
          finally { if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force } }
        }
        $env:npm_config_store_dir=Join-Path $script:Cache 'pnpm'
        Invoke-WithRegistryRetry $script:Client @('plugin','--profile',$Profile,'add',"file:$packageName",'--ignore-scripts')
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
