$ErrorActionPreference = 'Stop'
foreach ($file in Get-ChildItem $PSScriptRoot -Filter '*.ps1') {
  $tokens=$null; $errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if ($errors.Count) { throw ($errors | Out-String) }
}
$engine = (Get-Process -Id $PID).Path
function Check([string]$File,[string]$Setup,[int]$Code,[string]$Pattern,[string]$Arguments='') {
  $ErrorActionPreference = 'Continue'
  $path=(Join-Path $PSScriptRoot $File).Replace("'","''")
  $output = & $engine -NoProfile -NonInteractive -Command "`$ErrorActionPreference='Stop'; `$LASTEXITCODE=0; $Setup`n& '$path' $Arguments; exit `$LASTEXITCODE" 2>&1 | Out-String
  if ($LASTEXITCODE -ne $Code -or $output -notmatch $Pattern) { throw "$File expected exit $Code / $Pattern, received $LASTEXITCODE : $output" }
}
$npmFailure = @'
function npm.cmd { Write-Output 'npm failed'; $global:LASTEXITCODE=9 }
function pi.cmd { throw 'plugin must not run' }
function dsh.cmd { throw 'plugin must not run' }
'@
Check 'pi.ps1' $npmFailure 9 'npm failed'
Check 'dsh.ps1' $npmFailure 9 'npm failed'
$npmSuccess = @'
function npm.cmd { Write-Output ($args -join '|'); $global:LASTEXITCODE=0 }
function pi.cmd { Write-Output ($args -join '|'); $global:LASTEXITCODE=0 }
function dsh.cmd { Write-Output ($args -join '|'); $global:LASTEXITCODE=0 }
'@
Check 'pi.ps1' $npmSuccess 0 'install\|npm:@tokennotincluded/pi-lmm-provider'
Check 'dsh.ps1' $npmSuccess 0 'plugin\|--profile\|headless' '-Profile headless'
$upstream = @'
function Invoke-RestMethod { return 'param([string]$Version) Write-Output "upstream:$Version"' }
'@
Check 'claude-code.ps1' $upstream 0 'upstream:stable' 'stable'
Check 'codex.ps1' $upstream 0 'upstream:1.2.3' '1.2.3'
Check 'codex.ps1' "function Invoke-RestMethod { throw 'download-failed' }" 1 'download-failed'
Check 'clash-verge-rev.ps1' "function winget { Write-Output (`$args -join '|'); `$global:LASTEXITCODE=9 }" 9 'ClashVergeRev.ClashVergeRev'
Check 'lmm.ps1' "function cargo { Write-Output (`$args -join '|'); `$global:LASTEXITCODE=0 }" 0 'lmm-cli\|--version\|0.1.0\|--locked' '-FromSource'
$msi = @'
$env:PROCESSOR_ARCHITEW6432=''
function Invoke-RestMethod {
  [pscustomobject]@{assets=@(
    [pscustomobject]@{name='CC-Switch-v1-Windows.msi';browser_download_url='https://test.invalid/x64'},
    [pscustomobject]@{name='CC-Switch-v1-Windows-arm64.msi';browser_download_url='https://test.invalid/arm64'},
    [pscustomobject]@{name='CC-Switch-v1-Windows.msi.sig';browser_download_url='https://test.invalid/signature'}
  )}
}
function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing) Write-Output $Uri; Set-Content -LiteralPath $OutFile -Value 'fixture' }
function Start-Process {
  param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru)
  if ($ArgumentList[0] -ne '/i' -or $ArgumentList[1] -notmatch '^".*\.msi"$') { throw 'MSI argument boundaries lost' }
  [pscustomobject]@{ExitCode=0}
}
'@
Check 'cc-switch.ps1' ($msi+"`n`$env:PROCESSOR_ARCHITECTURE='AMD64'") 0 'https://test.invalid/x64'
Check 'cc-switch.ps1' ($msi+"`n`$env:PROCESSOR_ARCHITECTURE='ARM64'") 0 'https://test.invalid/arm64'
Write-Output 'PowerShell syntax and 11 command-contract checks passed.'
