$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\menu.ps1' }
$tools = @('pi','dsh','lmm','codex','claude-code','cc-switch','clash-verge-rev','codewhale')
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
    if ($tools[$index-1] -eq 'codewhale') { $installerArgs = @('menu') }
    try {
      $path = Join-Path $work $name
      if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot $name))) {
        $path = Join-Path $PSScriptRoot $name
      } else {
        Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/bd0a81de99d28c0ed5701cf290dade1e124dcecd/$name" -OutFile $path
      }
      & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $path @installerArgs
      if ($LASTEXITCODE) { Write-Warning "Installer exited with $LASTEXITCODE" }
    } catch { Write-Warning $_ }
  }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
