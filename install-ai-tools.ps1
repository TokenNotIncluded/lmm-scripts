$ErrorActionPreference = 'Stop'
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'npm is required.' }
npm install --global --ignore-scripts '@openai/codex' 'claude-code'
Write-Host 'AI command-line tools installed: codex, claude.'
