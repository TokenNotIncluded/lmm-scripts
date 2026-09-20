$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
. (Join-Path $project 'templates/lib/external.ps1')
$cases=@(
  @('cc-switch','x64','CC-Switch-v3.20.3-Windows-Portable.zip'),
  @('cc-switch','arm64','CC-Switch-v3.20.3-Windows-arm64-Portable.zip'),
  @('clash-verge-rev','x64','Clash.Verge_2.5.2_x64-setup.exe'),
  @('clash-verge-rev','arm64','Clash.Verge_2.5.2_arm64-setup.exe')
)
foreach ($case in $cases) {
  $pattern=Get-ExternalAssetPattern $case[0] $case[1]
  if ($case[2] -notmatch $pattern -or ($case[2]+'.sig') -match $pattern) { throw "Wrong asset pattern: $pattern" }
  $other=if($case[1] -eq 'x64'){'arm64'}else{'x64'}
  if ($case[2] -match (Get-ExternalAssetPattern $case[0] $other)) { throw 'Selected another architecture' }
}
$engine=(Get-Process -Id $PID).Path
foreach ($tool in @('codex','claude-code','cc-switch','clash-verge-rev')) {
  & $engine -NoProfile -File (Join-Path $project "$tool.ps1") -Help
  if ($LASTEXITCODE -ne 0) { throw "Help failed: $tool" }
  if ((Get-Item (Join-Path $project "$tool.ps1")).Length -gt 4000) { throw 'Entry should remain small' }
}
if ($env:OS -eq 'Windows_NT') {
  $path=Join-Path ([IO.Path]::GetTempPath()) ('lmm-plan-'+[Guid]::NewGuid())
  function Receive-ExternalFile { throw 'Dry run attempted a download' }
  foreach ($tool in @('codex','claude-code','cc-switch','clash-verge-rev')) {
    $plan=Invoke-ExternalSetup -Target $tool -Root $path -DryRun
    if (!$plan) { throw 'Missing installation plan' }
    if (Test-Path $path) { throw 'Dry run wrote files' }
  }
}
Write-Host 'External help, package architecture and no-install plans passed.'
