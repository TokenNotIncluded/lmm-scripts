param([ValidateSet('install','setup','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\codebuddy.ps1 [install|setup|help]'; exit 0 }
if ($Action -eq 'setup') { & codebuddy.cmd; exit $LASTEXITCODE }
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue) -or -not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Install Node.js 20+ and npm first.' }
& node -e 'if(Number(process.versions.node.split(".")[0])<20){console.error("Node.js 20+ is required.");process.exit(1)}'
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& npm.cmd install -g @tencent-ai/codebuddy-code@latest
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Write-Host 'Reopen your terminal; configure with: .\codebuddy.ps1 setup (starts codebuddy and its login screen).'
