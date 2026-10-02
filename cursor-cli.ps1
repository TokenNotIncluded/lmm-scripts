param([ValidateSet('install','setup','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\cursor-cli.ps1 [install|setup|help]'; exit 0 }
if ($Action -eq 'setup') { & wsl.exe -- cursor-agent login; exit $LASTEXITCODE }
# Cursor CLI currently documents Windows through WSL, not native PowerShell.
& wsl.exe -- bash -c 'set -e; installer=$(curl --proto "=https" --proto-redir "=https" -fsSL https://cursor.com/install); bash -c "$installer"'
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host "Reopen your terminal, then run: cursor-agent (inside WSL)"
