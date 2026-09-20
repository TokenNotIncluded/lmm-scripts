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
$Target = 'lmm'
$ScriptVersion = '2026.09.20.2'
$LmmVersion = '0.1.0'
$LmmReleaseBase = 'https://github.com/TokenNotIncluded/api.lmm.best/releases/download/lmm-cli-v0.1.0'
$LmmHashes = @{
  'linux-x64' = '292a1ff8b599466f52747867a0b14bd14860faefaa085cc60746040cd7eba9b7'
  'darwin-arm64' = '8f6b3a2d08500566b528b7089664420d3395e464c172e3a43dfcb73d37f57b3f'
  'win-x64' = 'd0eb3c3d3fe695eaa8a85de7c3161d0f7f17153064db5c20b8ced09defc574a9'
}

function Setting([string]$Name, [int]$Default, [int]$Maximum) {
    $raw = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($raw)) { return $Default }
    $number = 0
    if ($raw -notmatch '^[1-9][0-9]*$' -or -not [int]::TryParse($raw, [ref]$number) -or $number -gt $Maximum) { throw "$Name must be between 1 and $Maximum." }
    return $number
}
function QuoteArgument([string]$Value) {
    if($Value -notmatch '[\s"]' -and $Value.Length){return $Value}
    return '"' + [regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
}
function Stop-InstallChild($Process) {
    if($Process.HasExited){return}
    $killer=$null
    if($env:SystemRoot){$killer=Join-Path $env:SystemRoot 'System32\taskkill.exe'}
    if($killer -and (Test-Path -LiteralPath $killer)){ & $killer /PID $Process.Id /T /F 2>$null | Out-Null }
    if(-not $Process.HasExited){try{$Process.Kill($true)}catch{$Process.Kill()}}
    [void]$Process.WaitForExit(10000)
}
function Invoke-Bounded([string]$Executable,[string[]]$Arguments) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Executable; $info.UseShellExecute=$false
    if ((Get-Location).Provider.Name -eq 'FileSystem') { $info.WorkingDirectory=(Get-Location).ProviderPath }
    $info.Arguments=($Arguments | ForEach-Object { QuoteArgument $_ }) -join ' '
    $process=New-Object Diagnostics.Process; $process.StartInfo=$info
    $started=$false
    try {
      $started=$process.Start()
      if(-not $started){throw 'Could not start the installation process.'}
      $watch=[Diagnostics.Stopwatch]::StartNew(); $last=0
      while(-not $process.WaitForExit(1000)) {
        if($watch.Elapsed.TotalSeconds -gt $CommandTimeout){
          Stop-InstallChild $process
          throw 'Operation timed out. Increase LMM_COMMAND_TIMEOUT for slow networks and rerun.'
        }
        if($watch.Elapsed.TotalSeconds-$last -ge 15){Write-Log ('Still working: {0:N0}s elapsed.' -f $watch.Elapsed.TotalSeconds);$last=$watch.Elapsed.TotalSeconds}
      }
      $global:LASTEXITCODE=$process.ExitCode
      if($process.ExitCode -ne 0){throw "Installation command failed with exit code $($process.ExitCode)."}
    } finally {
      if($started -and -not $process.HasExited){Stop-InstallChild $process}
      $process.Dispose()
    }
}
function Invoke-Native([string]$Command, [string[]]$Arguments) {
  if ([IO.Path]::GetExtension($Command) -ieq '.cmd') {
    if ((Test-Path -LiteralPath $Command) -and (Select-String -LiteralPath $Command -SimpleMatch 'Managed by LMM installers' -Quiet)) {
      $launcherLines=@(Get-Content -LiteralPath $Command)
      foreach ($pathLine in $launcherLines) {
        if ($pathLine -match '^set "PATH=%~dp0\.\.\\(.+);%PATH%"$') {
          $runtime=[IO.Path]::GetFullPath((Join-Path (Split-Path (Split-Path $Command)) $Matches[1]))
          if (!$runtime.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Managed runtime escaped its root.' }
          if (!(Test-Path -LiteralPath $runtime -PathType Container)) { throw 'Managed runtime is missing. Rerun the installer.' }
          $env:PATH="$runtime;$env:PATH"
        }
      }
      $line=$launcherLines[-1]
      if ($line -match '^"%~dp0\.\.\\(.+)" %\*$') {
        $resolved=[IO.Path]::GetFullPath((Join-Path (Split-Path (Split-Path $Command)) $Matches[1]))
        if (!$resolved.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Managed launcher target escaped its root.' }
        $Command=$resolved
      }
    }
    if ([IO.Path]::GetExtension($Command) -ieq '.cmd') {
    $parent=Split-Path $Command
    $binName=[IO.Path]::GetFileNameWithoutExtension($Command).ToLowerInvariant()
    switch ($binName) {
      'npm' { $packageName='npm' }
      'pi' { $packageName='@earendil-works/pi-coding-agent' }
      'pnpm' { $packageName='pnpm' }
      'dsh' { $packageName='@deepseek-ai/dsh' }
      default { throw 'Unsupported command shim; use the managed installer or a native executable.' }
    }
    $packageRoot=[IO.Path]::GetFullPath((Join-Path $parent ('node_modules/' + $packageName)))
    $manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $binProperty=$manifest.PSObject.Properties['bin']
    if (!$binProperty) { throw 'Package manifest has no bin entry.' }
    $bins=$binProperty.Value
    $relative=$null
    if ($bins -is [string]) { $relative=$bins }
    elseif ($null -ne $bins -and $bins.PSObject.Properties[$binName]) { $relative=$bins.PSObject.Properties[$binName].Value }
    if ($relative -isnot [string] -or !$relative -or [IO.Path]::IsPathRooted($relative)) { throw 'Invalid package bin entry.' }
    $entry=[IO.Path]::GetFullPath((Join-Path $packageRoot $relative))
    if (!$entry.StartsWith($packageRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Package bin entry escaped its package.' }
    if (!(Test-Path -LiteralPath $entry)) { throw 'Client entry is missing. Rerun with -Update.' }
    $Command=(Get-Command node.exe).Source
    $Arguments=@($entry)+$Arguments
    }
  }
  Invoke-Bounded $Command $Arguments
}
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Set-RequestProxy($request) {
            $proxyValue = if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { $env:HTTP_PROXY }
            if ($proxyValue) {
                $proxyUri = [Uri]$proxyValue
                if ($proxyUri.Scheme -notin @('http','https')) { throw 'Use an HTTP(S) proxy with Windows PowerShell; SOCKS needs a local HTTP proxy adapter.' }
                $proxy = New-Object Net.WebProxy($proxyUri.GetLeftPart([UriPartial]::Authority))
                if ($proxyUri.UserInfo) {
                    $parts=$proxyUri.UserInfo.Split(':',2)
                    $password=if ($parts.Length -eq 2) { [Uri]::UnescapeDataString($parts[1]) } else { '' }
                    $proxy.Credentials=New-Object Net.NetworkCredential([Uri]::UnescapeDataString($parts[0]),$password)
                }
                if ($env:NO_PROXY) {
                    $proxy.BypassList=@($env:NO_PROXY.Split(',') | ForEach-Object { $hostName=$_.Trim().TrimStart('.'); if($hostName -eq '*') { '.*' } elseif($hostName) { '^https?://([^/]+\.)?' + [regex]::Escape($hostName) + '(:[0-9]+)?(/|$)' } })
                }
                $request.Proxy=$proxy
            }
}
function New-DownloadRequest([Uri]$Uri) { return [Net.HttpWebRequest]::Create($Uri) }
function Get-RankedUrls([string[]]$Urls) {
  $scores = @(); $index = 0
  foreach ($url in $Urls) {
    $timer = [Diagnostics.Stopwatch]::StartNew(); $score = 999999
    try {
      $request = New-DownloadRequest ([Uri]$url)
      $request.Method = 'HEAD'; $request.Timeout = 4000; $request.AllowAutoRedirect = $true
      Set-RequestProxy $request
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
  $request = New-DownloadRequest ([Uri]$Url)
  $request.Timeout = $ConnectTimeout*1000; $request.ReadWriteTimeout = $StallTimeout*1000; $request.AllowAutoRedirect = $true
  Set-RequestProxy $request
  if ($offset -gt 0) { $request.AddRange($offset) }
  $response = $null; $inputStream = $null; $outputStream = $null
  try {
    $response = $request.GetResponse()
    if ($response.ResponseUri.Scheme -ne 'https') { throw 'Insecure redirect refused.' }
    $mode = [IO.FileMode]::Create
    if ($offset -gt 0 -and [int]$response.StatusCode -eq 206) {
      if ($response.Headers['Content-Range'] -notlike "bytes $offset-*") { throw 'Invalid resume response.' }
      $mode = [IO.FileMode]::Append
    }
    $inputStream = $response.GetResponseStream()
    $outputStream = [IO.File]::Open($Path,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $buffer = New-Object byte[] 65536; $windowBytes = 0L; $total = 0L
    $window = [Diagnostics.Stopwatch]::StartNew(); $overall = [Diagnostics.Stopwatch]::StartNew()
    while (($read = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
      $outputStream.Write($buffer,0,$read); $windowBytes += $read; $total += $read
      if ($overall.Elapsed.TotalSeconds -gt $DownloadTimeout) { throw 'Download timeout.' }
      if ($window.Elapsed.TotalSeconds -ge $StallTimeout -and ($response.ContentLength -lt 0 -or $total -lt $response.ContentLength)) {
        if ($windowBytes / $window.Elapsed.TotalSeconds -lt $MinSpeed) { throw 'Download too slow; changing source.' }
        $window.Restart(); $windowBytes = 0
      }
    }
  } finally {
    if ($outputStream) { $outputStream.Dispose() }; if ($inputStream) { $inputStream.Dispose() }; if ($response) { $response.Close() }
  }
}
function Get-VerifiedFile([string]$Url, [string]$Destination, [string]$Expected) {
  $parsed=[Uri]$Url
  if ($parsed.Scheme -ne 'https' -or $parsed.UserInfo) { throw 'Download URLs must use HTTPS without credentials.' }
  foreach($file in @($Destination,"$Destination.part","$Destination.part.url")) { if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing symlink cache entries.' } }
  if (-not $Update -and (Test-Path -LiteralPath $Destination) -and (Get-Hash $Destination) -eq $Expected) { Write-Log "Cached: $([IO.Path]::GetFileName($Destination))"; return }
  $partial = "$Destination.part"; $sourceFile = "$partial.url"
  if ((Test-Path -LiteralPath $partial) -and (Get-Hash $partial) -eq $Expected) { Move-Item -LiteralPath $partial -Destination $Destination -Force; return }
  if ($env:LMM_NODE_BASE_URL -and $Url.StartsWith('https://nodejs.org/dist/')) { $Url=$Url.Replace('https://nodejs.org/dist',$env:LMM_NODE_BASE_URL.TrimEnd('/')) }
  $sourceNumber = 0
  foreach ($source in @(Get-DownloadUrls $Url)) {
    $sourceNumber++
    if ((Test-Path -LiteralPath $partial) -and (!(Test-Path -LiteralPath $sourceFile) -or (Get-Content -LiteralPath $sourceFile -Raw).Trim() -ne $source)) { Remove-Item -LiteralPath $partial -Force }
    Set-Content -LiteralPath $sourceFile -Value $source -Encoding ASCII
    foreach ($attempt in 1..$Retries) {
      Write-Log "Downloading $([IO.Path]::GetFileName($Destination)) (source $sourceNumber, attempt $attempt)"
      try {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
          Invoke-Native $curl.Source @('-q','--proto','=https','--proto-redir','=https','-fL','--connect-timeout',([string]$ConnectTimeout),'--max-time',([string]$DownloadTimeout),'--speed-time',([string]$StallTimeout),'--speed-limit',([string]$MinSpeed),'--continue-at','-','--output',$partial,$source)
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
    $name="lmm-v$LmmVersion-$Platform.zip"; $archive=Join-Path $script:Cache $name
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
function Install-Tool { Install-Lmm }

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
No automatic login or PATH changes. Pi on Windows requires Bash.
-FromSource is for the LMM CLI and requires existing Rust 1.88+ and build tools.
"@
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
  if ($script:PnpmBin -and $script:PnpmBin.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) {
    $pmRelative=$script:PnpmBin.Substring($Root.Length).TrimStart('\')
    $lines+=@("set `"PATH=%~dp0..\$pmRelative;%PATH%`"")
  }
  $lines+=@("`"%~dp0..\$clientRelative`" %*")
  $temporary=Join-Path $script:Stage 'launcher.cmd'
  [IO.File]::WriteAllLines($temporary,$lines,[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $destination -Force
  if ($AddPath -and -not $NoPath) {
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
try { Invoke-LmmSetup; exit 0 }
catch { Write-Error "Stopped during $script:Phase. $($_.Exception.Message)" -ErrorAction Continue; exit 1 }
finally {
  foreach($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name],'Process') }
  if ($script:InstalledSuccess -and $AddPath -and -not $NoPath) { $env:PATH=(Join-Path $Root 'bin')+';'+$env:PATH }
}
