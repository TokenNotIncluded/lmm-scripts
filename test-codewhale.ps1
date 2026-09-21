$ErrorActionPreference = 'Stop'
$engine = (Get-Process -Id $PID).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('lmm-powershell-' + [guid]::NewGuid())
function Assert-True($Value, $Message) { if (-not $Value) { throw $Message } }
function Literal([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
try {
  New-Item -ItemType Directory $work | Out-Null
  foreach ($name in @('codewhale.ps1', 'menu.ps1')) {
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "$name parse failed"
  }
  $output = & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'codewhale.ps1') --help
  Assert-True ($LASTEXITCODE -eq 0) 'Local help failed'
  Assert-True (($output -join "`n") -match 'Codewhale \+ LMM') 'Help was not printed'

  $wrapper = Join-Path $work 'codewhale.ps1'
  $helper = Join-Path $work 'codewhale.mjs'
  $receipt = Join-Path $work 'args.json'
  Copy-Item (Join-Path $PSScriptRoot 'codewhale.ps1') $wrapper
  $env:LMM_SCRIPT_TEST_RECEIPT = $receipt
  [IO.File]::WriteAllText($helper, 'import fs from "node:fs"; fs.writeFileSync(process.env.LMM_SCRIPT_TEST_RECEIPT, JSON.stringify(process.argv.slice(2))); process.exit(17);')
  $task = 'literal "quoted" $(not-a-command); & | C:\path with spaces\'
  $expected = @('run', '--model', 'lmm:ZGVmYXVsdA:bW9kZWw', '--', 'exec', $task)
  $driver = Join-Path $work 'driver.ps1'
  $arguments = ($expected | ForEach-Object { Literal $_ }) -join ','
  # The extra driver must splat the argument array and propagate the nested script's exit.
  [IO.File]::WriteAllText($driver, ('$forwarded = @(' + $arguments + '); & ' + (Literal $wrapper) + ' @forwarded; exit $LASTEXITCODE'))
  & $engine -NoProfile -ExecutionPolicy Bypass -File $driver
  Assert-True ($LASTEXITCODE -eq 17) 'Child exit status was lost'
  $received = @(Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json)
  Assert-True ($received.Count -eq $expected.Count) 'Argument count changed'
  for ($i=0; $i -lt $expected.Count; $i++) { Assert-True ($received[$i] -ceq $expected[$i]) "Argument $i changed" }

  # A detached download must be rejected before its contents execute.
  Remove-Item -LiteralPath $helper
  $marker = Join-Path $work 'executed'
  $env:LMM_SCRIPT_TEST_MARKER = $marker
  $driverCode = @'
function Invoke-WebRequest {
  param([switch]$UseBasicParsing, [Parameter(Position=0)][string]$Uri, [string]$OutFile)
  [IO.File]::WriteAllText($OutFile, 'import fs from "node:fs";fs.writeFileSync(process.env.LMM_SCRIPT_TEST_MARKER,"BAD");')
}
'@
  [IO.File]::WriteAllText($driver, $driverCode + "`n& " + (Literal $wrapper) + " --help")
  $preference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $engine -NoProfile -ExecutionPolicy Bypass -File $driver 2>$null
    $failureCode = $LASTEXITCODE
  } finally { $ErrorActionPreference = $preference }
  Assert-True ($failureCode -ne 0) 'Mismatched helper was accepted'
  Assert-True (-not (Test-Path -LiteralPath $marker)) 'Unverified downloaded code executed'
  Write-Host 'PowerShell checks passed: parser, help, literal argv/exit status, checksum refusal.'
} finally {
  Remove-Item Env:LMM_SCRIPT_TEST_RECEIPT -ErrorAction SilentlyContinue
  Remove-Item Env:LMM_SCRIPT_TEST_MARKER -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
