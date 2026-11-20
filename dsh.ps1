param([ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_-]*$')][string]$Profile = 'web')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\dsh.ps1 [-Profile name]' }
npm.cmd install -g @deepseek-ai/dsh@latest pnpm@latest
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$dshRoot = $env:DSH_HOME
if ([string]::IsNullOrWhiteSpace($dshRoot)) { $dshRoot = Join-Path $HOME '.dsh' }
elseif ($dshRoot -match '^~([\\/]|$)') { $dshRoot = Join-Path $HOME $dshRoot.Substring(1).TrimStart('/','\') }
$cache = Join-Path $dshRoot 'lmm-provider-packages'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$info = Get-Item -LiteralPath $cache -Force
if (-not $info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe DSH cache' }
$cache = $info.FullName
$expected = '21bc853b321906550cf529cecc83719e6d14fd70041cc7cb92e4aecd6316d3f1'
$plugin = Join-Path $cache ($expected + '.tgz')
$work = Join-Path $cache ('.download-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $download = Join-Path $work 'plugin.tgz'
  Invoke-WebRequest -UseBasicParsing 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/v0.1.0-alpha.9/dsh-lmm-provider.tgz' -OutFile $download
  if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expected) { throw 'DSH checksum mismatch.' }
  if (-not (Test-Path -LiteralPath $plugin)) { [IO.File]::Move($download, $plugin) }
  $info = Get-Item -LiteralPath $plugin -Force
  if ($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $plugin -Algorithm SHA256).Hash -ne $expected) { throw 'DSH checksum mismatch.' }
  dsh.cmd plugin --profile $Profile add $plugin --ignore-scripts
  exit $LASTEXITCODE
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
