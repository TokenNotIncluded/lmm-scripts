param([ValidateSet('install','setup','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\qwen-code.ps1 [install|setup|help]'; exit 0 }
if ($Action -eq 'setup') { & qwen.cmd; exit $LASTEXITCODE }
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue) -or -not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Install Node.js 22+ and npm first.' }
& node -e 'if(Number(process.versions.node.split(".")[0])<22){console.error("Node.js 22+ is required.");process.exit(1)}'
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& npm.cmd install -g @qwen-code/qwen-code@latest
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host 'Reopen your terminal; configure with: .\qwen-code.ps1 setup (starts qwen and its login screen).'
