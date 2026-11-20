$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'dsh.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
# Load functions without executing the installer, npm, downloads, registry
# writes or the main action. The argv regression uses an existing Python only;
# it does not install a wheel or simulate a DSH host.
foreach ($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
  . ([scriptblock]::Create($definition.Extent.Text))
}
$checks = 0
function Expect-Failure([scriptblock]$Block,[string]$Pattern) {
  $caught = $null
  try { & $Block | Out-Null } catch { $caught = $_ }
  if (-not $caught -or $caught.ToString() -notmatch $Pattern) { throw "Expected failure: $Pattern" }
  $script:checks++
}
function Require([bool]$Condition,[string]$Message) {
  if (-not $Condition) { throw $Message }
  $script:checks++
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('lmm-dsh-managed-tests-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($work)
try {
  # Compare each production probe with the single argument received by a real
  # interpreter under both PowerShell versions. No native-command mock is used.
  $nativePython = Find-DshPython
  $probes = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
      ($node.Value.StartsWith('import json,platform,sys;') -or
       $node.Value.StartsWith('import importlib.metadata,json;'))
  },$true))
  Require ($probes.Count -eq 2) 'The two production Python probes were not found.'
  $echoScript = Join-Path $work 'argv-echo.py'
  $expectedArg = Join-Path $work 'expected-argument.txt'
  $encoding = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($echoScript,'import pathlib,sys; sys.exit(0 if len(sys.argv) == 3 and sys.argv[2].encode() == pathlib.Path(sys.argv[1]).read_bytes() else 1)',$encoding)
  foreach ($probe in $probes) {
    [IO.File]::WriteAllText($expectedArg,$probe.Value,$encoding)
    & $nativePython -I $echoScript $expectedArg $probe.Value
    Require ($LASTEXITCODE -eq 0) 'A production Python probe changed at the native argv boundary.'
  }

  & {
    # Use the production writer, reader and existing-home guard with real files.
    # Windows PowerShell 5.1 can emit a JSON array as one pipeline object.
    $readNodes = @($ast.FindAll({
      param($node)
      $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Extent.Text.StartsWith('if (Test-Path -LiteralPath $profileFile)') -and
        $node.Extent.Text.Contains('ConvertFrom-Json')
    },$true))
    $writeNodes = @($ast.FindAll({
      param($node)
      $node -is [Management.Automation.Language.CommandAst] -and
        $node.Extent.Text.StartsWith('Write-DshAtomic $profileFile (ConvertTo-Json')
    },$true))
    $guardNodes = @($ast.FindAll({
      param($node)
      $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Extent.Text.StartsWith('if ((Test-Path -LiteralPath $dshRoot)') -and
        $node.Extent.Text.Contains('$profileKeys -notcontains $profileKey')
    },$true))
    Require ($readNodes.Count -eq 1 -and $writeNodes.Count -eq 1 -and $guardNodes.Count -eq 1) 'Production profile metadata statements were not found uniquely.'
    $readProfiles = [scriptblock]::Create($readNodes[0].Extent.Text)
    $writeProfiles = [scriptblock]::Create($writeNodes[0].Extent.Text)
    $recognizeProfile = [scriptblock]::Create($guardNodes[0].Extent.Text)
    $profileFile = Join-Path $work 'roundtrip-profiles.json'
    $profileA = New-DshDirectory (Join-Path $work 'roundtrip-a')
    $profileB = New-DshDirectory (Join-Path $work 'roundtrip-b')
    $unknownProfile = New-DshDirectory (Join-Path $work 'roundtrip-unknown')
    foreach ($directory in @($profileA,$profileB,$unknownProfile)) {
      [IO.File]::WriteAllText((Join-Path $directory 'keep'),'retain profile data')
    }
    $UseExistingProfile = $false
    $dshRoot = $profileA
    $profileKey = Get-DshProfileKey $dshRoot
    $firstKey = $profileKey
    $profileKeys = @()
    . $writeProfiles
    $profileKeys = @()
    . $readProfiles
    Require ($profileKeys.Count -eq 1 -and ($profileKeys[0] -is [string]) -and $profileKeys -contains $firstKey) 'A saved single profile key did not round trip as a string.'
    . $recognizeProfile
    Require ([IO.File]::ReadAllText((Join-Path $profileA 'keep')) -ceq 'retain profile data') 'Recognizing a saved profile changed its data.'

    $dshRoot = $profileB
    $profileKey = Get-DshProfileKey $dshRoot
    $secondKey = $profileKey
    . $writeProfiles
    $profileKeys = @()
    . $readProfiles
    Require ($profileKeys.Count -eq 2 -and ($profileKeys[0] -is [string]) -and ($profileKeys[1] -is [string]) -and $profileKeys -contains $firstKey -and $profileKeys -contains $secondKey) 'Two saved profile keys did not round trip as strings.'
    foreach ($directory in @($profileA,$profileB)) {
      $dshRoot = $directory
      $profileKey = Get-DshProfileKey $dshRoot
      . $recognizeProfile
    }
    $metadataBefore = [IO.File]::ReadAllText($profileFile)
    $dshRoot = $unknownProfile
    $profileKey = Get-DshProfileKey $dshRoot
    Expect-Failure { . $recognizeProfile } 'unrecognized installation'
    Require ([IO.File]::ReadAllText($profileFile) -ceq $metadataBefore -and [IO.File]::ReadAllText((Join-Path $unknownProfile 'keep')) -ceq 'retain profile data') 'Refusing an unknown profile changed metadata or profile data.'
    Write-DshAtomic $profileFile '["not-a-profile-key"]'
    Expect-Failure { . $readProfiles } 'Invalid managed DSH profile metadata'
  }

  # Real Windows path and junction regressions: no mocked path canonicalization.
  $guardRuntime = Join-Path $work 'not-created-runtime'
  $guardData = Join-Path $guardRuntime 'installs\version\profile'
  Expect-Failure { Assert-DshDataSeparation $guardData $guardRuntime } 'must not overlap'
  Require (-not (Test-Path -LiteralPath $guardRuntime)) 'Overlap guard created the runtime or profile.'
  Expect-Failure { Assert-DshDataSeparation $guardRuntime $guardRuntime } 'must not overlap'
  Expect-Failure { Assert-DshDataSeparation $work $guardRuntime } 'must not overlap'
  Expect-Failure { Assert-DshDataSeparation ($guardData.ToUpperInvariant() + '\') $guardRuntime } 'must not overlap'
  Expect-Failure { Assert-DshDataSeparation (Join-Path $guardRuntime 'temp\..\profile') $guardRuntime } 'must not overlap'
  Assert-DshDataSeparation ($guardRuntime + '-data') $guardRuntime
  Require (-not (Test-Path -LiteralPath ($guardRuntime + '-data'))) 'Sibling-prefix guard wrote a directory.'
  $aliasTarget = New-DshDirectory (Join-Path $guardRuntime 'installs\version\profile')
  [IO.File]::WriteAllText((Join-Path $aliasTarget 'keep'),'profile data')
  $alias = Join-Path $work 'profile-alias'
  New-Item -ItemType Junction -Path $alias -Target $aliasTarget | Out-Null
  try {
    Expect-Failure { Assert-DshDataSeparation $alias $guardRuntime } 'plain directories, not links'
    Expect-Failure { Assert-DshDataSeparation (Join-Path $alias 'future-profile') $guardRuntime } 'plain directories, not links'
    Require ([IO.File]::ReadAllText((Join-Path $aliasTarget 'keep')) -ceq 'profile data') 'Alias rejection changed profile data.'
  } finally { [IO.Directory]::Delete($alias) }
  $installs = New-DshDirectory (Join-Path $work 'installs')
  $id = '0.2.2rc2-a791af95a97be205'
  $shim = Join-Path $work 'dsh.cmd'
  $text = Get-DshShim $id
  Write-DshAtomic $shim $text
  Require ((Read-DshShim $shim) -ceq $id) 'Managed shim did not round trip.'
  Write-DshAtomic $shim 'existing npm command'
  Expect-Failure { Read-DshShim $shim } 'unmanaged'
  Require ([IO.File]::ReadAllText($shim) -ceq 'existing npm command') 'Unmanaged command was overwritten.'
  Write-DshAtomic $shim ($text + 'unexpected command')
  Expect-Failure { Read-DshShim $shim } 'unmanaged'
  Expect-Failure { Get-DshShim '..\outside' } 'Invalid managed'
  Write-DshAtomic $shim $text
  Require (@(Get-ChildItem -LiteralPath $work -Filter '*.new-*').Count -eq 0) 'Atomic write left a temporary file.'

  # Small synthetic payloads exercise integrity and ownership failures; they are
  # not a substitute for installing the real wheel in the Windows job.
  $runtime = New-DshDirectory (Join-Path $installs $id)
  [void](New-DshDirectory (Join-Path $runtime 'Scripts'))
  $package = New-DshDirectory (Join-Path $runtime 'Lib\site-packages\deepseek_harness_runtime')
  $launcher = Join-Path $runtime 'Scripts\dsh.exe'
  $basePython = Join-Path $work 'python.exe'
  $member = Join-Path $package 'payload.bin'
  [IO.File]::WriteAllText($launcher,'synthetic launcher')
  [IO.File]::WriteAllText($basePython,'synthetic Python; never executed')
  [IO.File]::WriteAllText($member,'payload')
  $wheelVersion = '0.2.2rc2'
  $wheelHash = 'a791af95a97be205a73354c6819e95b5fe2ff40a57ef8a78d53c188ee33e9aea'
  $payload = @(@{path='payload.bin';bytes=7;sha256=(Get-FileHash -LiteralPath $member -Algorithm SHA256).Hash})
  $receipt = @{schema=1;id=$id;version=$wheelVersion;wheel_sha256=$wheelHash;base_python=$basePython;launcher_sha256=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash.ToLowerInvariant()}
  Write-DshAtomic (Join-Path $runtime '.lmm-install.json') ($receipt | ConvertTo-Json)
  Require ((Assert-DshRuntime $id) -ceq $launcher) 'A recognized intact runtime was not selected.'
  [IO.File]::WriteAllText($member,'changed')
  Expect-Failure { Assert-DshRuntime $id } 'payload checksum mismatch'
  [IO.File]::WriteAllText($member,'payload')
  [IO.File]::WriteAllText($launcher,'altered launcher')
  Expect-Failure { Assert-DshRuntime $id } 'launcher checksum mismatch'
  [IO.File]::WriteAllText($launcher,'synthetic launcher')
  Remove-Item -LiteralPath $basePython -Force
  Expect-Failure { Assert-DshRuntime $id } 'path is missing'
  # Uninstall ownership remains inspectable even if Python was removed.
  Require ((Read-DshReceipt $id).id -ceq $id) 'Missing Python prevented ownership inspection.'

  $outside = New-DshDirectory (Join-Path $work 'outside')
  [IO.File]::WriteAllText((Join-Path $outside 'keep'),'keep')
  $link = Join-Path $runtime 'linked'
  New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
  Expect-Failure { Remove-DshDirectory $runtime } 'linked'
  # Call the same uninstall function used by the main action. A later descendant
  # junction must not allow either active or previous shim to be removed first.
  $backup = Join-Path $work 'previous.cmd'
  $profileFile = Join-Path $work 'profile-roots.json'
  Write-DshAtomic $backup $text
  Write-DshAtomic $profileFile '[]'
  $current = $id; $previous = $id
  Expect-Failure { Remove-DshManagedHost } 'linked'
  Require ([IO.File]::ReadAllText($shim) -ceq $text) 'Refused uninstall removed the active shim.'
  Require ([IO.File]::ReadAllText($backup) -ceq $text) 'Refused uninstall removed the previous shim.'
  Require ([IO.File]::ReadAllText($profileFile) -ceq '[]') 'Refused uninstall changed metadata.'
  Require (Test-Path -LiteralPath (Join-Path $outside 'keep')) 'Refused uninstall changed unrelated data.'
  Require (Test-Path -LiteralPath (Join-Path $outside 'keep')) 'Deletion followed a junction.'
  [IO.Directory]::Delete($link)
  Remove-DshDirectory $runtime
  Require (-not (Test-Path -LiteralPath $runtime)) 'Owned runtime was not removed.'
  Require (Test-Path -LiteralPath (Join-Path $outside 'keep')) 'Unrelated files were removed.'
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
Write-Output "Managed DSH file and integrity contracts: $checks passed; no host installation performed."
