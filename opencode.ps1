$ErrorActionPreference = 'Stop'
$node = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$nodeVersion = & $node -p 'process.versions.node'
if ($LASTEXITCODE) { exit $LASTEXITCODE }
if ([int]($nodeVersion.Split('.')[0]) -lt 22) { throw 'Node.js 22+ with npm is required.' }
# Windows PowerShell 5.1 drops embedded quotes in native @args calls.
# Build an argv-equivalent command line, without cmd.exe or Invoke-Expression.
function ConvertTo-NativeArgument([string]$Value) {
  $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
  $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}
$work = $null
try {
  $helper = $null
  if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'opencode.mjs') -PathType Leaf)) {
    $helper = Join-Path $PSScriptRoot 'opencode.mjs'
  } else {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('lmm-opencode-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $work | Out-Null
    $helper = Join-Path $work 'opencode.mjs'
    Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/e2efbe13fd4e8c0cb9d31ed95ae6d432415aed25/opencode.mjs' -OutFile $helper
    if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash -ne 'ded76c114f7c8a692c9d7fa7828828b86ad7d0591aa01fd19be1c2ceecfd95a4') {
      throw 'OpenCode setup script checksum mismatch; nothing was executed.'
    }
  }
  $start = New-Object System.Diagnostics.ProcessStartInfo
  $start.FileName = $node
  $start.UseShellExecute = $false
  $start.WorkingDirectory = $PWD.Path
  $start.Arguments = ((@($helper) + @($args) | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
  $child = [Diagnostics.Process]::Start($start)
  try { $child.WaitForExit(); $code = $child.ExitCode } finally { $child.Dispose() }
  exit $code
} finally {
  if ($work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
