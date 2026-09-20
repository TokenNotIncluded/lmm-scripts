param([switch]$FromSource)
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\lmm.ps1 [-FromSource]' }
if ($FromSource) { cargo install lmm-cli --version 0.1.0 --locked; exit $LASTEXITCODE }
$arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($arch -ne 'AMD64') { throw 'No prebuilt LMM CLI for this architecture; use -FromSource.' }
$work = Join-Path ([IO.Path]::GetTempPath()) ("lmm-" + [guid]::NewGuid())
$bin = Join-Path $HOME '.local\bin'
try {
  New-Item -ItemType Directory $work | Out-Null
  Invoke-WebRequest -UseBasicParsing https://github.com/TokenNotIncluded/api.lmm.best/releases/download/lmm-cli-v0.1.0/lmm-v0.1.0-win-x64.zip -OutFile "$work\lmm.zip"
  Expand-Archive "$work\lmm.zip" -DestinationPath $work
  & "$work\lmm.exe" --version
  if ($LASTEXITCODE) { throw 'LMM CLI cannot run on this system.' }
  New-Item -ItemType Directory $bin -Force | Out-Null
  Copy-Item "$work\lmm.exe" "$bin\lmm.exe" -Force
  Write-Output "$bin\lmm.exe"
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
