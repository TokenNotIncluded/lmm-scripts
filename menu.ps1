$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\menu.ps1' }
$tools = @('pi','dsh','lmm','codex','claude-code','cc-switch','clash-verge-rev')
$work = Join-Path ([IO.Path]::GetTempPath()) ("lmm-menu-" + [guid]::NewGuid())
try {
  New-Item -ItemType Directory $work | Out-Null
  while ($true) {
    Write-Host "`nInstall / update"
    for ($i=0; $i -lt $tools.Count; $i++) { Write-Host "$($i+1)  $($tools[$i])" }
    $choice = Read-Host '0  Exit'
    if ($choice -eq '0') { break }
    if ($choice -notmatch '^[1-7]$') { continue }
    $name = $tools[[int]$choice-1] + '.ps1'
    try {
      $path = Join-Path $work $name
      if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot $name))) {
        $path = Join-Path $PSScriptRoot $name
      } else {
        Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/b7b066e5ca0e8a16b13c37a308419bc475cd459b/$name" -OutFile $path
      }
      & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $path
      if ($LASTEXITCODE) { Write-Warning "Installer exited with $LASTEXITCODE" }
    } catch { Write-Warning $_ }
  }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
