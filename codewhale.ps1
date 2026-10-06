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
  if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'codewhale.mjs') -PathType Leaf)) {
    $helper = Join-Path $PSScriptRoot 'codewhale.mjs'
  } else {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('lmm-codewhale-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $work | Out-Null
    $helper = Join-Path $work 'codewhale.mjs'
    Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/cdf32d6d0e612cb2e22ae93f2f25f744d6145617/codewhale.mjs' -OutFile $helper
    if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash -ne '4138c5d74f1dee3cf089a90bdeef649d42304de7f5f9cd83e28f7d3302f994fb') {
      throw 'Codewhale setup script checksum mismatch; nothing was executed.'
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
