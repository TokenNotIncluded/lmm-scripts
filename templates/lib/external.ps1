# Native upstream installers; desktop apps are never launched implicitly.
function Get-ExternalEntry([string]$Command, [string]$Root) {
  $paths=@((Join-Path $Root "bin\$Command.cmd"), (Join-Path $HOME ".local\bin\$Command.exe"))
  if ($Command -eq 'codex') {
    if ($env:CODEX_INSTALL_DIR) { $paths+=Join-Path $env:CODEX_INSTALL_DIR 'codex.exe' }
    $paths+=Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'
  }
  if ($Command -eq 'clash-verge') {
    foreach ($base in @($env:LOCALAPPDATA,$env:ProgramFiles,${env:ProgramFiles(x86)})) {
      if ($base) { foreach ($folder in @('Clash Verge','Programs\Clash Verge')) { $paths+=Join-Path $base "$folder\clash-verge.exe" } }
    }
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
      foreach ($item in @(Get-ItemProperty $key -ErrorAction SilentlyContinue)) {
        if ($item.PSObject.Properties['DisplayName'] -and $item.DisplayName -like 'Clash Verge*' -and $item.PSObject.Properties['InstallLocation'] -and $item.InstallLocation) {
          $paths+=Join-Path $item.InstallLocation 'clash-verge.exe'
        }
      }
    }
  }
  foreach ($path in $paths) { if (Test-Path -LiteralPath $path -PathType Leaf) { return $path } }
  $found=Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { return $found.Source }
  return $null
}
function Get-ExternalAssetPattern([string]$Target, [string]$Architecture) {
  if ($Target -eq 'cc-switch') {
    if ($Architecture -eq 'arm64') { return '-Windows-arm64-Portable\.zip$' }
    return '-Windows-Portable\.zip$'
  }
  return "_${Architecture}-setup\.exe$"
}
function Receive-ExternalFile([string]$Url, [string]$Path) {
  $urls=@($Url)
  if ((Get-Variable Network -ErrorAction SilentlyContinue) -and $Network -eq 'china' -and $Url.StartsWith('https://github.com/')) { $urls=@("https://ghfast.top/$Url",$Url) }
  foreach ($source in $urls) {
    for ($attempt=1; $attempt -le 3; $attempt++) {
      try {
        Invoke-WebRequest -UseBasicParsing -Uri $source -OutFile $Path -TimeoutSec 600 -ErrorAction Stop
        if ((Get-Item -LiteralPath $Path).Length -eq 0) { throw 'Empty download' }
        return
      } catch { if ($attempt -eq 3 -and $source -eq $urls[-1]) { throw }; Start-Sleep -Seconds 1 }
    }
  }
}
function Invoke-ExternalSetup {
  param([string]$Target,[string]$Root,[string]$Version,[string]$Network='official',
    [switch]$Check,[switch]$Update,[switch]$Launch,[switch]$DryRun,[string[]]$RunArgs=@())
  if ($env:OS -ne 'Windows_NT') { throw 'Use the .sh installer on Linux/macOS/Termux.' }
  if (!$Root) { $Root=if($env:LMM_INSTALL_ROOT){$env:LMM_INSTALL_ROOT}else{Join-Path $env:LOCALAPPDATA 'lmm-tools'} }
  $Root=[IO.Path]::GetFullPath($Root)
  if ($Root -eq [IO.Path]::GetPathRoot($Root) -or $Root -eq $HOME -or $Root -match '[\r\n]') { throw 'Choose a dedicated install directory' }
  if ((Test-Path -LiteralPath $Root) -and ((Get-Item -LiteralPath $Root).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing a linked install root' }
  $architecture=$env:PROCESSOR_ARCHITECTURE
  if ($env:PROCESSOR_ARCHITEW6432) { $architecture=$env:PROCESSOR_ARCHITEW6432 }
  switch ($architecture) { 'ARM64' { $arch='arm64' } 'AMD64' { $arch='x64' } default { throw 'x64 or ARM64 Windows is required' } }
  $url=$null; $repo=$null
  switch ($Target) {
    'codex' { $command='codex'; $url='https://chatgpt.com/codex/install.ps1' }
    'claude-code' { $command='claude'; $url='https://claude.ai/install.ps1' }
    'cc-switch' { $command='cc-switch'; $repo='farion1231/cc-switch' }
    'clash-verge-rev' { $command='clash-verge'; $repo='clash-verge-rev/clash-verge-rev' }
    default { throw 'Unknown tool' }
  }
  if ($Version) { $Update=$true }
  if (!$Version) { $Version=if($Target -eq 'claude-code'){'stable'}else{'latest'} }
  if ($Version -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.+-]*$') { throw 'Invalid version' }
  if ($DryRun) {
    if ($url) { Write-Output "$Target windows/$arch official:$url version:$Version" }
    else { Write-Output "$Target windows/$arch release:$repo pattern:$(Get-ExternalAssetPattern $Target $arch)" }
    return
  }
  $entry=Get-ExternalEntry $command $Root
  if ($Check) {
    if (!$entry) { throw "$command is not installed" }
    if ($url) { & $entry --version; if ($LASTEXITCODE -ne 0) { throw 'Executable check failed' } }
    else { Write-Output "Installed: $entry" }
    return
  }
  $stage=$null
  $oldTls=[Net.ServicePointManager]::SecurityProtocol
  try {
    [Net.ServicePointManager]::SecurityProtocol=$oldTls -bor [Net.SecurityProtocolType]::Tls12
    if (!$entry -or $Update) {
      $stage=Join-Path ([IO.Path]::GetTempPath()) ('lmm-'+[Guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $stage | Out-Null
      if ($url) {
        $installer=Join-Path $stage 'install.ps1'; Receive-ExternalFile $url $installer
        $shell=(Get-Process -Id $PID).Path
        if ($Target -eq 'codex') { & $shell -NoProfile -ExecutionPolicy Bypass -File $installer -Release $Version }
        else { & $shell -NoProfile -ExecutionPolicy Bypass -File $installer $Version }
        if ($LASTEXITCODE -ne 0) { throw "Official installer exited with $LASTEXITCODE" }
      } else {
        $release=if($Version -eq 'latest'){'latest'}else{'tags/v'+$Version.TrimStart('v')}
        $metadata=Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/$release" -TimeoutSec 60
        $pattern=Get-ExternalAssetPattern $Target $arch
        $assets=@($metadata.assets | Where-Object { $_.name -match $pattern })
        if ($assets.Count -ne 1) { throw "Expected one $arch asset matching $pattern" }
        $asset=$assets[0]; $file=Join-Path $stage $asset.name
        Receive-ExternalFile $asset.browser_download_url $file
        if ($Target -eq 'cc-switch') {
          $app=Join-Path $stage 'app'; Expand-Archive -LiteralPath $file -DestinationPath $app
          $binaries=@(Get-ChildItem -LiteralPath $app -Recurse -File -Filter 'cc-switch.exe')
          if ($binaries.Count -ne 1) { throw 'Expected one cc-switch.exe in portable archive' }
          $relative=$binaries[0].FullName.Substring($app.Length).TrimStart('\')
          $destination=Join-Path $Root ('apps\cc-switch\'+[Guid]::NewGuid().ToString('N'))
          $launcher=Join-Path $Root 'bin\cc-switch.cmd'
          if ((Test-Path -LiteralPath $launcher) -and !(Select-String -LiteralPath $launcher -SimpleMatch 'Managed by LMM installers' -Quiet)) { throw 'Refusing existing launcher' }
          New-Item -ItemType Directory -Path (Split-Path $destination),(Split-Path $launcher) -Force | Out-Null
          Move-Item -LiteralPath $app -Destination $destination
          $binary=Join-Path $destination $relative
          $within=$binary.Substring($Root.Length).TrimStart('\')
          $text="@echo off`r`nrem Managed by LMM installers`r`nsetlocal DisableDelayedExpansion`r`n`"%~dp0..\$within`" %*`r`n"
          $pending=Join-Path (Split-Path $launcher) ('launcher-'+[Guid]::NewGuid().ToString('N')+'.tmp')
          [IO.File]::WriteAllText($pending,$text,[Text.UTF8Encoding]::new($false))
          Move-Item -LiteralPath $pending -Destination $launcher -Force
        } else {
          Write-Output 'Complete the official installer window; system service/UAC prompts belong to Clash Verge Rev.'
          $process=Start-Process -FilePath $file -Wait -PassThru
          if ($process.ExitCode -notin @(0,1641,3010)) { throw "Installer exited with $($process.ExitCode)" }
          if ($process.ExitCode -ne 0) { Write-Output 'Windows restart requested by installer.' }
        }
      }
      $entry=Get-ExternalEntry $command $Root
      if (!$entry) { throw 'Installer finished but executable was not found; inspect its installation directory.' }
      if ($url) { & $entry --version; if ($LASTEXITCODE -ne 0) { throw 'Installed binary did not run' } }
    }
    Write-Output "Ready: $entry"
    if ($Launch) { & $entry @RunArgs; if ($LASTEXITCODE -ne 0) { throw "Program exited with $LASTEXITCODE" } }
  } finally {
    [Net.ServicePointManager]::SecurityProtocol=$oldTls
    if ($stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
