$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
foreach($file in Get-ChildItem -LiteralPath $project -Filter '*.ps1') {
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if($errors.Count) { throw ($errors | Out-String) }
}
$source=Join-Path $project 'lmm.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
$functions=$ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst]},$true)
foreach($function in $functions) { . ([scriptblock]::Create($function.Extent.Text)) }
$Target='test';$Network='official';$Update=$false;$script:Phase='test'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('lmm-ps-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$expectedFile=Join-Path $testRoot 'expected';[IO.File]::WriteAllBytes($expectedFile,[Text.Encoding]::UTF8.GetBytes('verified fixture'))
$expected=(Get-FileHash -LiteralPath $expectedFile -Algorithm SHA256).Hash.ToLowerInvariant()
function Get-DownloadUrls { return @('https://test.invalid/artifact') }
function Get-Command { param([string]$Name) if($Name -eq 'curl.exe'){return $null};return Microsoft.PowerShell.Core\Get-Command $Name }
$script:Mode='corrupt';$script:Transfers=0;$script:Resumed=$false
function Receive-Stream([string]$Url,[string]$Path) {
  $script:Transfers++
  if($script:Mode -eq 'corrupt') { [IO.File]::WriteAllBytes($Path,[Text.Encoding]::UTF8.GetBytes('corrupt'));return }
  if($script:Mode -eq 'resume' -and !(Test-Path -LiteralPath $Path)) { [IO.File]::WriteAllBytes($Path,[Text.Encoding]::UTF8.GetBytes('ver'));throw 'interrupted' }
  if(Test-Path -LiteralPath $Path) { $script:Resumed=((Get-Item -LiteralPath $Path).Length -gt 0) }
  Copy-Item -LiteralPath $expectedFile -Destination $Path -Force
}
try {
  $destination=Join-Path $testRoot 'artifact'
  $refused=$false
  try { Get-VerifiedFile 'https://test.invalid/artifact' $destination $expected } catch { $refused=$true }
  if(!$refused -or (Test-Path -LiteralPath $destination)) { throw 'Corrupt download was accepted' }
  $script:Mode='resume';Get-VerifiedFile 'https://test.invalid/artifact' $destination $expected
  if(!$script:Resumed -or (Get-Hash $destination) -ne $expected) { throw 'Resume did not produce verified file' }
  $before=$script:Transfers;Get-VerifiedFile 'https://test.invalid/artifact' $destination $expected
  if($script:Transfers -ne $before) { throw 'Verified cache was downloaded again' }
  Write-Host 'PowerShell syntax, corrupt-file rejection, resume and cache tests passed.'
} finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }
