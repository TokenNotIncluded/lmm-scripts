$ErrorActionPreference = 'Stop'
foreach ($file in Get-ChildItem $PSScriptRoot -Filter '*.ps1') {
  $tokens=$null; $errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if ($errors.Count) { throw ($errors | Out-String) }
}
$engine = (Get-Process -Id $PID).Path
$checks = 0
function Check([string]$File,[string]$Setup,[int]$Code,[string]$Pattern,[string]$Arguments='') {
  $ErrorActionPreference = 'Continue'
  $path=(Join-Path $PSScriptRoot $File).Replace("'","''")
  $codeText = "`$ErrorActionPreference='Stop'; `$LASTEXITCODE=0; $Setup`n& '$path' $Arguments; exit `$LASTEXITCODE"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($codeText))
  $output = & $engine -NoProfile -NonInteractive -EncodedCommand $encoded *>&1 | Out-String
  if ($LASTEXITCODE -ne $Code -or $output -notmatch $Pattern) { throw "$File expected exit $Code / $Pattern, received $LASTEXITCODE : $output" }
  $script:checks++
}
$piSetup = @'
$env:PI_TEST_INSTALLER = 'function Get-PiBinDir { "official-bin" }; $env:PI_VENDOR_ENV="ready"'
$env:PI_TEST_VERSION = '0.87.1'
function Invoke-RestMethod {
  if ($args[0] -ne 'https://pi.dev/install.ps1') { throw 'wrong installer URL' }
  return $env:PI_TEST_INSTALLER
}
function Join-Path {
  param($Path,$ChildPath)
  if ($Path -ne 'official-bin' -or $ChildPath -ne 'pi.cmd') { throw 'wrong installed path' }
  return 'official-pi'
}
function official-pi {
  if ($env:PI_VENDOR_ENV -ne 'ready') { throw 'official environment lost' }
  $global:LASTEXITCODE=0
  if ($args[0] -eq '--version') { $env:PI_TEST_VERSION }
  else { Write-Output ($args -join '|') }
}
function Write-Warning { param($Message) Write-Output $Message }
function npm.cmd {
  if ($env:LMM_PI_BIN -ne 'official-pi') { throw 'official Pi path was not forwarded' }
  Write-Output ($args -join '|'); $global:LASTEXITCODE=0
}
function pi.cmd { throw 'must not invoke stale pi on PATH' }
'@
Check 'pi.ps1' $piSetup 0 'lmm-pi-provider\|npm:@tokennotincluded/pi-lmm-provider'
Check 'pi.ps1' ($piSetup+"`n`$env:PI_TEST_INSTALLER='Write-Output cancelled; exit 0'") 0 'cancelled'
Check 'pi.ps1' ($piSetup+"`n`$env:PI_TEST_INSTALLER='Write-Output failed; exit 9'") 9 'failed'
Check 'pi.ps1' ($piSetup+"`n`$env:PI_TEST_VERSION='0.88.0'; function official-pi { if (`$args[0] -ne '--version') { throw 'unsupported plugin must not run' }; `$env:PI_TEST_VERSION }") 0 'plugin skipped'
Check 'pi.ps1' ($piSetup+"`nfunction official-pi { if (`$args[0] -ne '--version') { throw 'plugin must not run' }; `$global:LASTEXITCODE=8 }") 8 ''
Check 'pi.ps1' ($piSetup+"`nfunction npm.cmd { Write-Output plugin-failed; `$global:LASTEXITCODE=7 }") 7 'plugin-failed'
Check 'pi.ps1' "function Invoke-RestMethod { throw 'download-failed' }" 1 'download-failed'
$npmFailure = @'
function npm.cmd { Write-Output 'npm failed'; $global:LASTEXITCODE=9 }
function dsh.cmd { throw 'plugin must not run' }
'@
Check 'dsh.ps1' $npmFailure 9 'npm failed'
$npmSuccess = @'
function npm.cmd { Write-Output ($args -join '|'); $global:LASTEXITCODE=0 }
function dsh.cmd { Write-Output ($args -join '|'); $global:LASTEXITCODE=0 }
'@
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
Write-Output "PowerShell syntax and $checks command-contract checks passed."
