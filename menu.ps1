$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\menu.ps1' }
$tools = @('pi','dsh','lmm','codex','claude-code','cc-switch','clash-verge-rev','codewhale','opencode','cursor-cli','grok-build','gemini','qwen-code','kimi','codebuddy','hermes','openclaw','astrbot','aider','cursor','cherry-studio','ollama','uv','magpie')
$work = Join-Path ([IO.Path]::GetTempPath()) ("lmm-menu-" + [guid]::NewGuid())
try {
  New-Item -ItemType Directory $work | Out-Null
  while ($true) {
    Write-Host "`nInstall / update"
    for ($i=0; $i -lt $tools.Count; $i++) { Write-Host "$($i+1)  $($tools[$i])" }
    $choice = Read-Host '0  Exit'
    if ($choice -eq '0') { break }
    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $tools.Count) { continue }
    $name = $tools[$index-1] + '.ps1'
    $installerArgs = @()
    $tool = $tools[$index-1]
    if ($tool -eq 'codewhale') { $installerArgs = @('menu') }
    if ($tool -in @('cursor-cli','grok-build','gemini','qwen-code','kimi','codebuddy','hermes','openclaw','astrbot','aider')) {
      Write-Host '1  Install / update'
      Write-Host '2  Configure / login (already installed)'
      $action = Read-Host '0  Back'
      if ($action -eq '1') { $installerArgs = @('install') }
      elseif ($action -eq '2') {
        $installerArgs = @('setup')
        if ($tool -eq 'astrbot') {
          $instanceDir = Read-Host 'AstrBot instance directory'
          if (-not $instanceDir) { continue }
          $installerArgs += @('-Directory', $instanceDir)
        }
      } else { continue }
    }
    try {
      $path = Join-Path $work $name
      if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot $name))) {
        $path = Join-Path $PSScriptRoot $name
      } else {
        $revision = '86391c6e604bdbbf1231770529c47d508eca7d45'
        if ($env:LMM_SCRIPTS_REV) { $revision = $env:LMM_SCRIPTS_REV }
        Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/$revision/$name" -OutFile $path
      }
      & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $path @installerArgs
      if ($LASTEXITCODE) { Write-Warning "Installer exited with $LASTEXITCODE" }
    } catch { Write-Warning $_ }
  }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
