param([ValidateSet('install','setup','help')][string]$Action = 'install', [string]$Directory)
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\astrbot.ps1 [install|setup -Directory PATH|help]'; exit 0 }
if ($Action -eq 'setup') {
  if (-not $Directory) { throw 'Specify an AstrBot instance directory with -Directory PATH' }
  if (-not (Get-Command astrbot -ErrorAction SilentlyContinue)) { throw 'Install AstrBot first and reopen your terminal.' }
  New-Item -ItemType Directory -Force -Path $Directory | Out-Null
  Push-Location -LiteralPath $Directory
  try {
    if (Test-Path -LiteralPath 'data') {
      Write-Host 'This directory already has AstrBot data. Use astrbot run here and configure it in the WebUI.'
      exit 0
    }
    & astrbot init
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
  } finally { Pop-Location }
  Write-Host 'Run astrbot run in this directory; configure providers and chat platforms in the WebUI.'
  exit 0
}
if ($Directory) { throw '-Directory is only supported with setup' }
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { throw 'Install uv first: .\uv.ps1 (or https://docs.astral.sh/uv/).' }
& uv tool install --upgrade astrbot --python 3.12
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host 'Reopen your terminal; initialize with: .\astrbot.ps1 setup -Directory PATH'
