param(
    [ValidateSet('install', 'update', 'help')][string]$Action = 'install',
    [switch]$Cli,
    [string]$BinDir = $env:MAGPIE_BIN_DIR
)
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\magpie.ps1 [install|update|help] [-Cli] [-BinDir PATH]' }
if ($Action -eq 'help') {
    Write-Host 'Usage: .\magpie.ps1 [install|update|help] [-Cli] [-BinDir PATH]'
    Write-Host 'Windows x64/ARM64. Installs the official release without starting it or changing your configuration.'
    return
}
if ($env:OS -ne 'Windows_NT') { throw 'Use magpie.sh on Linux, macOS or Termux.' }
# The native architecture takes priority over an emulated PowerShell process.
$machine = $env:PROCESSOR_ARCHITEW6432
if (-not $machine) { $machine = $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($machine) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { throw "Unsupported Windows architecture: $machine" }
}
$flavor = if ($Cli -or $env:MAGPIE_CLI) { '-cli' } else { '' }
$name = "magpie$flavor-windows-$arch.exe"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$release = Invoke-RestMethod -UseBasicParsing 'https://api.github.com/repos/yetone/magpie/releases/latest'
if ($release.draft -or $release.prerelease -or -not $release.tag_name) { throw 'Expected an official stable Magpie release.' }
$assets = @($release.assets | Where-Object { $_.name -ceq $name })
if ($assets.Count -ne 1) { throw "The latest release has no unique $name asset." }
$asset = $assets[0]
$url = 'https://github.com/yetone/magpie/releases/download/' + [uri]::EscapeDataString($release.tag_name) + '/' + $name
if ($asset.browser_download_url -cne $url) { throw 'Unexpected Magpie download URL.' }
if ($asset.digest -cnotmatch '^sha256:[0-9a-f]{64}$') { throw 'The release has no valid SHA-256 digest; nothing was installed.' }
$expected = $asset.digest.Substring(7)
if (-not $BinDir) { $BinDir = Join-Path $HOME '.local\bin' }
$BinDir = [IO.Path]::GetFullPath($BinDir)
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
# Stage on the destination volume so replacing an existing binary is atomic.
$work = Join-Path $BinDir ('.magpie-install-' + [guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $download = Join-Path $work $name
    Invoke-WebRequest -UseBasicParsing $url -OutFile $download
    $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash
    if ($actual -ine $expected) { throw 'Magpie SHA-256 mismatch; the existing installation was not changed.' }
    $target = Join-Path $BinDir 'magpie.exe'
    if ([IO.File]::Exists($target)) {
        [IO.File]::Replace($download, $target, $null)
    } else {
        [IO.File]::Move($download, $target)
    }
    Write-Host "Installed magpie $($release.tag_name): $target"
    Write-Host 'Open it to configure providers. Add the install directory to PATH to use magpie from a terminal.'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
