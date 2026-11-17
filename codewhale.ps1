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
    Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/967563d3e00a53c9deaddb7276247407935598ad/codewhale.mjs' -OutFile $helper
    if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash -ne 'e30adefd8b94d9806a437a98b9c669759c1c13e78a50485b43e68f98b854d2f7') {
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
