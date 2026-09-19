$ErrorActionPreference = 'Stop'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 20+ is required.' }
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'npm is required.' }
$major = [int](node -p "process.versions.node.split('.')[0]")
if ($major -lt 20) { throw 'Node.js 20+ is required.' }
npm install --global --ignore-scripts '@mariozechner/pi-coding-agent'
if ($env:LMM_PI_PLUGIN) { npm install --global --ignore-scripts $env:LMM_PI_PLUGIN }
Write-Host 'Pi installed. Run: pi'
