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
Check 'pi.ps1' $piSetup 0 'lmm-pi-provider\|git:github.com/TokenNotIncluded/pi-lmm-provider'
Check 'pi.ps1' ($piSetup+"`n`$env:PI_TEST_INSTALLER='Write-Output cancelled; exit 0'") 0 'cancelled'
Check 'pi.ps1' ($piSetup+"`n`$env:PI_TEST_INSTALLER='Write-Output failed; exit 9'") 9 'failed'
foreach ($version in @('0.88.0', '0.99.2', '1.2.0')) {
  Check 'pi.ps1' ($piSetup+"`n`$env:PI_TEST_VERSION='$version'") 0 'lmm-pi-provider\|git:github.com/TokenNotIncluded/pi-lmm-provider'
}
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
function Invoke-WebRequest { param($Uri,$Method,[switch]$UseBasicParsing) if ($Uri -ne 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/latest' -or $Method -ne 'Head') { throw 'wrong release URL' }; return [pscustomobject]@{BaseResponse=[pscustomobject]@{ResponseUri=[Uri]'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/tag/v0.1.0-alpha.5'}} }
'@
Check 'dsh.ps1' $npmSuccess 0 'plugin\|--profile\|headless.*releases/download/v0.1.0-alpha.5/dsh-lmm-provider.tgz' '-Profile headless'
Check 'dsh.ps1' ($npmSuccess+"`nfunction Invoke-WebRequest { throw 'missing-release' }") 1 'missing-release'
Check 'dsh.ps1' ($npmSuccess+"`nfunction Invoke-WebRequest { [pscustomobject]@{BaseResponse=[pscustomobject]@{ResponseUri=[Uri]'https://evil.invalid/plugin.tgz'}} }") 1 'Unexpected plugin release URL'
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
# New AI tools: download contracts, setup separation, and native exit propagation.
$nativeUrls = @{
  'grok-build'='https://x.ai/cli/install.ps1'
  'kimi'='https://code.kimi.com/kimi-code/install.ps1'
  'hermes'='https://hermes-agent.nousresearch.com/install.ps1'
  'openclaw'='https://openclaw.ai/install.ps1'
  'aider'='https://aider.chat/install.ps1'
  'uv'='https://astral.sh/uv/install.ps1'
}
foreach ($name in $nativeUrls.Keys) {
  $url = $nativeUrls[$name]
  $fixture = "function Invoke-RestMethod { param(`$Uri) if (`$Uri -ne '$url') { throw 'wrong installer URL' }; return 'param([switch]`$SkipSetup,[switch]`$NoOnboard) Write-Output upstream; Write-Output (`$SkipSetup.IsPresent -or `$NoOnboard.IsPresent)' }"
  $pattern = if ($name -in @('hermes','openclaw')) { 'True' } else { 'upstream' }
  Check "$name.ps1" $fixture 0 $pattern
  Check "$name.ps1" "function Invoke-RestMethod { throw 'download-failed' }" 1 'download-failed'
  Check "$name.ps1" "function Invoke-RestMethod { return 'exit 9' }" 9 ''
}
$cursorWsl = @'
function wsl.exe { Write-Output ($args -join '|'); $global:LASTEXITCODE=0 }
'@
Check 'cursor-cli.ps1' $cursorWsl 0 'bash\|-c\|.*https://cursor.com/install'
Check 'cursor-cli.ps1' $cursorWsl 0 'cursor-agent\|login' 'setup'
$packages = @{'gemini'='@google/gemini-cli'; 'qwen-code'='@qwen-code/qwen-code'; 'codebuddy'='@tencent-ai/codebuddy-code'}
foreach ($name in $packages.Keys) {
  $fixture = "function node { `$global:LASTEXITCODE=0 }; function npm.cmd { Write-Output (`$args -join '|'); `$global:LASTEXITCODE=0 }"
  Check "$name.ps1" $fixture 0 ([regex]::Escape('install|-g|'+$packages[$name]+'@latest'))
  Check "$name.ps1" ($fixture+"; function npm.cmd { Write-Output npm-failed; `$global:LASTEXITCODE=8 }") 8 'npm-failed'
  Check "$name.ps1" ($fixture+"; function node { `$global:LASTEXITCODE=7 }; function npm.cmd { throw 'must not install' }") 7 ''
}
$setups = @{'grok-build'='grok'; 'kimi'='kimi'; 'hermes'='hermes'; 'openclaw'='openclaw'; 'aider'='aider'; 'gemini'='gemini.cmd'; 'qwen-code'='qwen.cmd'; 'codebuddy'='codebuddy.cmd'}
foreach ($name in $setups.Keys) {
  $command = $setups[$name]
  $fixture = "function Invoke-RestMethod { throw 'setup must not download' }; function $command { Write-Output configured; `$global:LASTEXITCODE=6 }"
  Check "$name.ps1" $fixture 6 'configured' 'setup'
}
Check 'astrbot.ps1' "function uv { Write-Output (`$args -join '|'); `$global:LASTEXITCODE=0 }" 0 'tool\|install\|--upgrade\|astrbot\|--python\|3.12'
Check 'astrbot.ps1' '' 1 'Specify an AstrBot instance directory' 'setup'
$astrbotSetup = @'
function New-Item { }
function Push-Location { param($LiteralPath) if ($LiteralPath -ne 'instance with spaces') { throw 'directory boundaries lost' } }
function Pop-Location { }
function Test-Path { $false }
function astrbot { Write-Output ($args -join '|'); $global:LASTEXITCODE=0 }
function uv { throw 'setup must not install' }
'@
Check 'astrbot.ps1' $astrbotSetup 0 'init' "setup -Directory 'instance with spaces'"
Check 'astrbot.ps1' ($astrbotSetup+"`nfunction Test-Path { `$true }; function astrbot { throw 'must not reinitialize existing data' }") 0 'already has AstrBot data' "setup -Directory 'instance with spaces'"
$desktopFixture = @'
function Invoke-RestMethod {
  param($Uri)
  if ($Uri -like 'https://cursor.com/api/download*') { return [pscustomobject]@{downloadUrl='https://downloads.cursor.com/setup.exe'} }
  return [pscustomobject]@{assets=@(
    [pscustomobject]@{name='Cherry-Studio-1-win-x64-setup.exe';browser_download_url='https://github.com/CherryHQ/cherry-studio/releases/download/v1/x64.exe'},
    [pscustomobject]@{name='Cherry-Studio-1-win-arm64-setup.exe';browser_download_url='https://github.com/CherryHQ/cherry-studio/releases/download/v1/arm64.exe'},
    [pscustomobject]@{name='Cherry-Studio-CN-1-win-x64-setup.exe';browser_download_url='https://github.com/CherryHQ/cherry-studio/releases/download/v1/cn.exe'}
  )}
}
function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing) Write-Output $Uri; Set-Content -LiteralPath $OutFile -Value fixture }
function Start-Process { param($FilePath,[switch]$Wait,[switch]$PassThru) [pscustomobject]@{ExitCode=0} }
$env:PROCESSOR_ARCHITEW6432=''
'@
foreach ($cpu in @('AMD64','ARM64')) {
  $arch = if ($cpu -eq 'AMD64') { 'x64' } else { 'arm64' }
  Check 'cherry-studio.ps1' ($desktopFixture+"`n`$env:PROCESSOR_ARCHITECTURE='$cpu'") 0 "$arch.exe"
  Check 'cursor.ps1' ($desktopFixture+"`n`$env:PROCESSOR_ARCHITECTURE='$cpu'") 0 'downloads.cursor.com'
}
Check 'ollama.ps1' $desktopFixture 0 'https://ollama.com/download/OllamaSetup.exe'
foreach ($name in @('cursor','cherry-studio','ollama')) {
  Check "$name.ps1" ($desktopFixture+"`n`$env:PROCESSOR_ARCHITECTURE='AMD64'; function Start-Process { [pscustomobject]@{ExitCode=9} }") 9 ''
  Check "$name.ps1" ($desktopFixture+"`n`$env:PROCESSOR_ARCHITECTURE='AMD64'; function Invoke-WebRequest { throw 'download-failed' }") 1 'download-failed'
}
Check 'cursor.ps1' ($desktopFixture+"`n`$env:PROCESSOR_ARCHITECTURE='AMD64'; function Invoke-RestMethod { [pscustomobject]@{downloadUrl='https://evil.invalid/setup.exe'} }") 1 'Unexpected Cursor'
Check 'cherry-studio.ps1' ($desktopFixture+"`n`$env:PROCESSOR_ARCHITECTURE='AMD64'; function Invoke-RestMethod { [pscustomobject]@{assets=@()} }") 1 'No unique official'
# Exercise the actual PowerShell menu with local inert child scripts.
$menuWork = Join-Path ([IO.Path]::GetTempPath()) ('lmm-menu-contract-' + [guid]::NewGuid())
try {
  New-Item -ItemType Directory -Path $menuWork | Out-Null
  Copy-Item (Join-Path $PSScriptRoot 'menu.ps1') (Join-Path $menuWork 'menu.ps1')
  foreach ($name in @('cursor-cli','grok-build','hermes','astrbot')) {
    Set-Content -LiteralPath (Join-Path $menuWork "$name.ps1") -Value 'Write-Output ("ROUTED:" + ($args -join "|"))'
  }
  foreach ($entry in @(@('10','1','install'),@('11','2','setup'),@('16','0',''))) {
    $global:LmmMenuAnswers = [Collections.Generic.Queue[string]]::new()
    $global:LmmMenuAnswers.Enqueue($entry[0]); $global:LmmMenuAnswers.Enqueue($entry[1]); $global:LmmMenuAnswers.Enqueue('0')
    function Read-Host { param($Prompt) return $global:LmmMenuAnswers.Dequeue() }
    $output = & (Join-Path $menuWork 'menu.ps1') | Out-String
    if ($entry[2] -and $output -notmatch ([regex]::Escape('ROUTED:'+$entry[2]))) { throw 'PowerShell menu action routing failed' }
    if (-not $entry[2] -and $output -match 'ROUTED:') { throw 'Menu back unexpectedly ran an installer' }
    $checks++
  }
  $global:LmmMenuAnswers = [Collections.Generic.Queue[string]]::new()
  foreach ($answer in @('18','2','instance with spaces','0')) { $global:LmmMenuAnswers.Enqueue($answer) }
  $output = & (Join-Path $menuWork 'menu.ps1') | Out-String
  if ($output -notmatch 'ROUTED:setup\|-Directory\|instance with spaces') { throw 'AstrBot menu directory routing failed' }
  $checks++
} finally {
  Remove-Variable LmmMenuAnswers -Scope Global -ErrorAction SilentlyContinue
  Remove-Item Function:Read-Host -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $menuWork -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "PowerShell syntax and $checks command-contract checks passed."
