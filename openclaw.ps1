param([ValidateSet('install','setup','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\openclaw.ps1 [install|setup|help]'; exit 0 }
if ($Action -eq 'setup') { & openclaw onboard; exit $LASTEXITCODE }
& ([scriptblock]::Create((Invoke-RestMethod https://openclaw.ai/install.ps1))) -NoOnboard
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host "Reopen your terminal, then run: openclaw"
