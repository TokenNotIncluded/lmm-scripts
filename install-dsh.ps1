$ErrorActionPreference = 'Stop'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 20+ is required.' }
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'npm is required.' }
$major = [int](node -p "process.versions.node.split('.')[0]")
if ($major -lt 20) { throw 'Node.js 20+ is required.' }
npm install --global --ignore-scripts '@tokennotincluded/dsh-lmm-provider'
if ($env:LMM_DSH_PLUGIN) { npm install --global --ignore-scripts $env:LMM_DSH_PLUGIN }
Write-Host 'DSH provider installed.'
