# Offline fixtures only: no network, package install, GUI launch or user config.
$ErrorActionPreference = 'Stop'
foreach ($name in @('magpie.ps1', 'menu.ps1', 'test-magpie.ps1')) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('magpie-test-' + [guid]::NewGuid())
$keys = @('OS', 'PROCESSOR_ARCHITEW6432', 'PROCESSOR_ARCHITECTURE', 'MAGPIE_CLI', 'MAGPIE_BIN_DIR')
$saved = @{}
foreach ($key in $keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key) }
$checks = 0
$script:bytes = [Text.Encoding]::UTF8.GetBytes('magpie offline fixture')
$sha = [Security.Cryptography.SHA256]::Create()
try { $script:digest = ([BitConverter]::ToString($sha.ComputeHash($script:bytes))).Replace('-', '').ToLowerInvariant() }
finally { $sha.Dispose() }
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-RestMethod {
    param($Uri, [switch]$UseBasicParsing)
    $script:requests++
    Assert ($Uri -ceq 'https://api.github.com/repos/yetone/magpie/releases/latest') 'Wrong release endpoint'
    if ($script:mode -eq 'release-failure') { throw 'release-failure' }
    $asset = [pscustomobject]@{
        name = $script:assetName
        browser_download_url = "https://github.com/yetone/magpie/releases/download/v1.2.3/$script:assetName"
        digest = 'sha256:' + $script:digest
    }
    switch ($script:mode) {
        'foreign' { $asset.browser_download_url = 'https://evil.invalid/magpie.exe' }
        'wrong-tag' { $asset.browser_download_url = $asset.browser_download_url.Replace('v1.2.3', 'v9.9.9') }
        'missing-hash' { $asset.digest = $null }
        'bad-hash' { $asset.digest = 'sha256:' + ('0' * 64) }
    }
    $assets = @($asset)
    if ($script:mode -eq 'missing') { $assets = @() }
    if ($script:mode -eq 'duplicate') { $assets = @($asset, $asset) }
    [pscustomobject]@{ tag_name = 'v1.2.3'; draft = ($script:mode -eq 'draft'); prerelease = ($script:mode -eq 'prerelease'); assets = $assets }
}
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing)
    $script:downloads++
    Assert ($Uri -ceq "https://github.com/yetone/magpie/releases/download/v1.2.3/$script:assetName") 'Wrong asset URL'
    [IO.File]::WriteAllBytes($OutFile, $script:bytes)
    if ($script:mode -eq 'download-failure') { throw 'download-failure' }
}
function Start-Process { throw 'Installer must not start the application' }
function Case([string]$Mode = 'success', [string]$Arch = 'AMD64', [string]$Native = '', [switch]$Cli, [switch]$Fresh, [string]$Action = 'install') {
    $script:mode = $Mode; $script:requests = 0; $script:downloads = 0
    $env:OS = 'Windows_NT'; $env:PROCESSOR_ARCHITECTURE = $Arch; $env:PROCESSOR_ARCHITEW6432 = $Native
    $env:MAGPIE_CLI = ''; $env:MAGPIE_BIN_DIR = ''
    if ($Mode -eq 'non-windows') { $env:OS = 'Linux' }
    if ($Mode -eq 'env-cli') { $env:MAGPIE_CLI = '1' }
    $cpu = if ($Native) { $Native } else { $Arch }
    $cpu = if ($cpu -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $flavor = if ($Cli -or $env:MAGPIE_CLI) { '-cli' } else { '' }
    $script:assetName = "magpie$flavor-windows-$cpu.exe"
    $directory = Join-Path $root ("case with spaces " + $script:checks)
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $target = Join-Path $directory 'magpie.exe'
    if (-not $Fresh) { [IO.File]::WriteAllText($target, 'old-version') }
    $failure = $null
    $arguments = @{ Action = $Action; BinDir = $directory; Cli = $Cli }
    if ($Mode -eq 'env-directory') { $env:MAGPIE_BIN_DIR = $directory; $arguments.Remove('BinDir') }
    try { & (Join-Path $PSScriptRoot 'magpie.ps1') @arguments }
    catch { $failure = $_ }
    $success = $Mode -in @('success', 'env-cli', 'env-directory')
    if ($Action -eq 'help') {
        Assert (-not $failure -and $script:requests -eq 0) 'Help used the network or failed'
        Assert ([IO.File]::ReadAllText($target) -eq 'old-version') 'Help changed the installation'
    } elseif ($success) {
        Assert (-not $failure) "Install failed: $failure"
        Assert ($script:requests -eq 1 -and $script:downloads -eq 1) 'Unexpected downloads'
        Assert ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ieq $script:digest) 'Wrong installed bytes'
    } else {
        Assert ($null -ne $failure) "$Mode should fail"
        Assert ([IO.File]::ReadAllText($target) -eq 'old-version') "$Mode changed the existing installation"
        if ($Mode -notin @('bad-hash', 'download-failure')) { Assert ($script:downloads -eq 0) "$Mode downloaded an executable" }
        if ($Mode -in @('unsupported', 'non-windows')) { Assert ($script:requests -eq 0) "$Mode used the network" }
    }
    Assert (@(Get-ChildItem -LiteralPath $directory -Force -Filter '.magpie-install-*').Count -eq 0) 'Staging directory leaked'
    $script:checks++
}
try {
    Case -Fresh
    Case -Action update
    Case -Arch ARM64
    Case -Arch x86 -Native ARM64
    Case -Cli
    Case -Mode env-cli
    Case -Mode env-directory
    Case -Action help
    Case -Mode unsupported -Arch x86
    Case -Mode non-windows
    foreach ($mode in @('release-failure', 'missing', 'duplicate', 'foreign', 'wrong-tag', 'missing-hash', 'bad-hash', 'draft', 'prerelease', 'download-failure')) { Case -Mode $mode }
    Write-Host "Passed $checks Magpie PowerShell cases."
} finally {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
