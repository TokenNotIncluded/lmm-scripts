[CmdletBinding(PositionalBinding=$false)]
param([string]$Command='help',[Parameter(ValueFromRemainingArguments=$true)][string[]]$CliArgs=@())
$ErrorActionPreference='Stop'
if ($Command -in @('help','--help','-h')) {
  Write-Host @'
LMM CLI quick start (developer preview)
  .\lmm-use.ps1 catalog [keyword]
  .\lmm-use.ps1 status [application]
  .\lmm-use.ps1 doctor [application]      (adds --report)
  .\lmm-use.ps1 plan [application]        (setup --dry-run only)
  .\lmm-use.ps1 login
  .\lmm-use.ps1 models --json
  .\lmm-use.ps1 logout
Install first: https://api.lmm.best/scripts -> lmm.ps1
Login uses the OS credential store. Setup integration is not implemented yet;
planning/doctor can return exit 3, which this wrapper preserves.
'@
  exit 0
}
$root=$env:LMM_INSTALL_ROOT
if (-not $root) { $root=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'lmm-tools' }
$entry=Join-Path $root 'bin\lmm.cmd'
if (!(Test-Path -LiteralPath $entry)) {
  $found=Get-Command lmm -ErrorAction SilentlyContinue
  if (!$found) { Write-Error 'LMM CLI is not installed. Run lmm.ps1 first.'; exit 2 };$entry=$found.Source
}
switch($Command) {
  {$_ -in @('catalog','status','models','login','logout')} { $arguments=@($Command)+$CliArgs }
  'doctor' { $arguments=@('doctor','--report')+$CliArgs }
  'plan' { $arguments=@('setup','--dry-run')+$CliArgs }
  default { Write-Error 'Unknown quick-start command. Use help.';exit 2 }
}
$global:LASTEXITCODE=0
& $entry @arguments
exit $LASTEXITCODE
