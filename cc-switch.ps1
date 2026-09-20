$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\cc-switch.ps1' }
$arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
switch ($arch) {
  'AMD64' { $pattern = '-Windows\.msi$' }
  'ARM64' { $pattern = '-Windows-arm64\.msi$' }
  default { throw 'CC Switch requires x64 or arm64 Windows.' }
}
$assets = @((Invoke-RestMethod https://api.github.com/repos/farion1231/cc-switch/releases/latest).assets | Where-Object name -Match $pattern)
if ($assets.Count -ne 1) { throw 'No unique official Windows installer.' }
$file = Join-Path ([IO.Path]::GetTempPath()) ("cc-switch-" + [guid]::NewGuid() + '.msi')
try {
  Invoke-WebRequest -UseBasicParsing $assets[0].browser_download_url -OutFile $file
  $process = Start-Process msiexec.exe -ArgumentList @('/i', "`"$file`"") -Wait -PassThru
  if ($process.ExitCode -notin 0,3010) { throw "Installer exited with $($process.ExitCode)" }
} finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
