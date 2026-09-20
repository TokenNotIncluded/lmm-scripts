$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'pi.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($definition in $ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) {
  . ([scriptblock]::Create($definition.Extent.Text))
}
# Only these functions are exercised; never invoke the installer or download.
if ($env:OS -ne 'Windows_NT') { Write-Host 'Windows policy tests skipped on non-Windows.'; return }
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('lmm-policy-'+[Guid]::NewGuid().ToString('N'))
$oldAgent=$env:PI_CODING_AGENT_DIR; $oldPrograms=$env:ProgramFiles; $oldPath=$env:PATH
$script:NodeForTest=Join-Path $testRoot 'runtime\node.exe'
function Get-Command {
  param([string]$Name, $CommandType, $ErrorAction)
  if ($Name -eq 'node.exe') { return [pscustomobject]@{ Source=$script:NodeForTest } }
  return $null
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
  $caught=$false
  try { & $Action } catch { $caught=$true; if ($_.Exception.Message -notlike "*$Message*") { throw } }
  if (!$caught) { throw "Expected error containing: $Message" }
}
function Invoke-Bounded([string]$Executable, [string[]]$Arguments) {
  $script:CapturedExe=$Executable; $script:CapturedArgs=$Arguments
}
try {
  $env:PI_CODING_AGENT_DIR=Join-Path $testRoot 'agent'
  $env:ProgramFiles=Join-Path $testRoot 'programs'
  New-Item -ItemType Directory -Path $env:PI_CODING_AGENT_DIR -Force | Out-Null
  Assert-Throws { Assert-PiShell } 'Pi requires Bash'
  $bash=Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
  New-Item -ItemType Directory -Path (Split-Path $bash) -Force | Out-Null
  Set-Content -LiteralPath $bash -Value ''
  Assert-PiShell
  $config=Join-Path $env:PI_CODING_AGENT_DIR 'settings.json'
  @{shellPath=(Join-Path $testRoot 'missing.exe')} | ConvertTo-Json | Set-Content -LiteralPath $config
  Assert-Throws { Assert-PiShell } 'shellPath does not exist'
  $custom=Join-Path $testRoot ('custom '+[char]0x6D4B+[char]0x8BD5+' bash.exe'); Set-Content -LiteralPath $custom -Value ''
  [IO.File]::WriteAllText($config,(@{shellPath=$custom} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  $before=Get-Content -LiteralPath $config -Raw
  Assert-PiShell
  if ((Get-Content -LiteralPath $config -Raw) -ne $before) { throw 'Shell preflight modified settings.' }
  Set-Content -LiteralPath $config -Value '{bad-json'
  Assert-Throws { Assert-PiShell } 'Invalid Pi settings'

  $Root=$testRoot
  $client=Join-Path $Root 'apps\pi\test'
  $package=Join-Path $client 'node_modules\@earendil-works\pi-coding-agent'
  $entry=Join-Path $package 'new-layout\main.js'
  New-Item -ItemType Directory -Path (Split-Path $entry) -Force | Out-Null
  Set-Content -LiteralPath $entry -Value ''
  $manifest=Join-Path $package 'package.json'
  @{bin=@{pi='new-layout/main.js'}} | ConvertTo-Json | Set-Content -LiteralPath $manifest
  $shim=Join-Path $client 'pi.cmd'; Set-Content -LiteralPath $shim -Value '@echo off'
  Invoke-Native $shim @('--version','two words')
  if ($script:CapturedArgs[0] -ne $entry -or $script:CapturedArgs[2] -ne 'two words') { throw 'Package bin resolution or argument boundaries failed.' }
  @{bin=@{pi='../outside.js'}} | ConvertTo-Json | Set-Content -LiteralPath $manifest
  Assert-Throws { Invoke-Native $shim @('--version') } 'escaped its package'
  @{bin=@{pi='new-layout/main.js'}} | ConvertTo-Json | Set-Content -LiteralPath $manifest

  $runtime=Join-Path $Root 'runtime'
  New-Item -ItemType Directory -Path $runtime -Force | Out-Null
  $launcher=Join-Path $Root 'bin\pi.cmd'
  New-Item -ItemType Directory -Path (Split-Path $launcher) -Force | Out-Null
  @('@echo off','rem Managed by LMM installers','set "PATH=%~dp0..\runtime;%PATH%"','"%~dp0..\apps\pi\test\pi.cmd" %*') | Set-Content -LiteralPath $launcher
  Invoke-Native $launcher @('--version')
  if ($env:PATH.Split(';')[0] -ne $runtime) { throw 'Managed runtime PATH was not restored for -Check.' }
  if ($script:CapturedArgs[0] -ne $entry) { throw 'Managed launcher did not resolve its package entry.' }
  Write-Host 'Windows Bash lookup, configuration preservation, package bin containment and managed runtime checks passed.'
} finally {
  $env:PI_CODING_AGENT_DIR=$oldAgent; $env:ProgramFiles=$oldPrograms; $env:PATH=$oldPath
  Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
