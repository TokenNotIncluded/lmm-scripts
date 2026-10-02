param([ValidateSet('install','setup','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\hermes.ps1 [install|setup|help]'; exit 0 }
if ($Action -eq 'setup') { & hermes setup; exit $LASTEXITCODE }
& ([scriptblock]::Create((Invoke-RestMethod https://hermes-agent.nousresearch.com/install.ps1))) -SkipSetup
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host "Reopen your terminal, then run: hermes"
