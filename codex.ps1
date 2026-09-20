$ErrorActionPreference = 'Stop'
& ([scriptblock]::Create((Invoke-RestMethod https://chatgpt.com/codex/install.ps1))) @args
