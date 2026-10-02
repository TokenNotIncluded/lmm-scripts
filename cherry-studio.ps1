param([ValidateSet('install','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\cherry-studio.ps1 [install|help]'; exit 0 }
$cpu = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($cpu) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { throw 'Only x64 and arm64 packages are available.' } }
$release = Invoke-RestMethod https://api.github.com/repos/CherryHQ/cherry-studio/releases/latest
$assets = @($release.assets | Where-Object { $_.name -match "^Cherry-Studio-[0-9].*-win-$arch-setup\.exe$" })
if ($assets.Count -ne 1) { throw 'No unique official Windows installer' }
$url = $assets[0].browser_download_url
if ($url -notlike 'https://github.com/CherryHQ/cherry-studio/releases/download/*') { throw 'Unexpected Cherry Studio download URL' }
$work = Join-Path ([IO.Path]::GetTempPath()) ('lmm-cherry-studio-' + [guid]::NewGuid())
try {
  New-Item -ItemType Directory -Path $work | Out-Null
  $path = Join-Path $work 'setup.exe'
  Invoke-WebRequest -UseBasicParsing $url -OutFile $path
  $process = Start-Process -FilePath $path -Wait -PassThru
  if ($process.ExitCode -ne 0) { exit $process.ExitCode }
  Write-Host 'Launch cherry-studio; configure accounts and providers in the app settings.'
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
