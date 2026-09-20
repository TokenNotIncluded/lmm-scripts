$ErrorActionPreference = 'Stop'
& ([scriptblock]::Create((Invoke-RestMethod https://claude.ai/install.ps1))) @args
