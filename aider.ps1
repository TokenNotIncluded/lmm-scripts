param([ValidateSet('install','setup','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\aider.ps1 [install|setup|help]'; exit 0 }
if ($Action -eq 'setup') { & aider; exit $LASTEXITCODE }
& ([scriptblock]::Create((Invoke-RestMethod https://aider.chat/install.ps1)))
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host "Reopen your terminal, then run: aider"
