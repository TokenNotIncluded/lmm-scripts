param([ValidateSet('install','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\cursor.ps1 [install|help]'; exit 0 }
$cpu = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($cpu) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { throw 'Only x64 and arm64 packages are available.' } }
$url = (Invoke-RestMethod "https://cursor.com/api/download?platform=win32-$arch-user&releaseTrack=stable").downloadUrl
if ($url -notlike 'https://downloads.cursor.com/*') { throw 'Unexpected Cursor download URL' }
$work = Join-Path ([IO.Path]::GetTempPath()) ('lmm-cursor-' + [guid]::NewGuid())
try {
  New-Item -ItemType Directory -Path $work | Out-Null
  $path = Join-Path $work 'setup.exe'
  Invoke-WebRequest -UseBasicParsing $url -OutFile $path
  $process = Start-Process -FilePath $path -Wait -PassThru
  if ($process.ExitCode -ne 0) { exit $process.ExitCode }
  Write-Host 'Launch cursor; configure accounts and providers in the app settings.'
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
