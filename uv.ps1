param([ValidateSet('install','setup','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\uv.ps1 [install|help]'; exit 0 }
if ($Action -eq 'setup') { throw 'uv does not need account setup' }
& ([scriptblock]::Create((Invoke-RestMethod https://astral.sh/uv/install.ps1)))
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host "Reopen your terminal, then run: uv"
