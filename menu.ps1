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
        Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/848c82c253b5d35712943e5a9990606e4613e7b9/$name" -OutFile $path
      }
      & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $path
      if ($LASTEXITCODE) { Write-Warning "Installer exited with $LASTEXITCODE" }
    } catch { Write-Warning $_ }
  }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
