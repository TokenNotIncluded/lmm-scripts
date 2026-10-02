param([ValidateSet('install','help')][string]$Action = 'install')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Too many arguments' }
if ($Action -eq 'help') { Write-Host 'Usage: .\ollama.ps1 [install|help]'; exit 0 }
$work = Join-Path ([IO.Path]::GetTempPath()) ('lmm-ollama-' + [guid]::NewGuid())
try {
  New-Item -ItemType Directory -Path $work | Out-Null
  $path = Join-Path $work 'OllamaSetup.exe'
  Invoke-WebRequest -UseBasicParsing https://ollama.com/download/OllamaSetup.exe -OutFile $path
  $process = Start-Process -FilePath $path -Wait -PassThru
  if ($process.ExitCode -ne 0) { exit $process.ExitCode }
  Write-Host 'Reopen your terminal. Use ollama run MODEL to choose a model; this script does not download models.'
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
