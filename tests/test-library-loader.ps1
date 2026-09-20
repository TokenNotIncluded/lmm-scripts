$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $project 'templates/load.ps1.in'))))
$LibRevision=('a'*40)
$root=Join-Path ([IO.Path]::GetTempPath()) ('lmm-loader-'+[Guid]::NewGuid().ToString('N'))
$beforeDir=$env:LMM_LIB_DIR; $beforeProxy=$env:HTTPS_PROXY; $beforeHttp=$env:HTTP_PROXY
$beforeProtocol=[Net.ServicePointManager]::SecurityProtocol
$script:Calls=0; $script:Mode='ok'; $script:SeenUri=''
function Invoke-WebRequest {
  [CmdletBinding()]
  param([string]$Uri,[switch]$UseBasicParsing,[int]$TimeoutSec,[string]$Proxy,[pscredential]$ProxyCredential)
  $script:Calls++; $script:SeenUri=$Uri
  if($script:Mode -eq 'fail' -or ($script:Mode -eq 'retry' -and $script:Calls -eq 1)){throw 'interrupted'}
  $code='$LmmLoaded=42; function Get-LmmTestValue { $LmmLoaded }'
  if($script:Mode -eq 'empty'){$code=' '}
  if($script:Mode -eq 'invalid'){$code='function {'}
  return [pscustomobject]@{RawContentStream=[IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($code))}
}
function Assert-Throws([scriptblock]$Code) {
  $caught=$false
  try{& $Code}catch{$caught=$true}
  if(!$caught){throw 'Expected a library loading error.'}
}
try {
  $env:LMM_LIB_DIR='';$env:HTTPS_PROXY='';$env:HTTP_PROXY=''
  . (Get-LmmLibrary 'common.ps1')
  if((Get-LmmTestValue) -ne 42){throw 'Remote functions did not survive dot-sourcing.'}
  if($script:SeenUri -ne "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/$LibRevision/templates/lib/common.ps1"){throw 'Wrong pinned library URL.'}
  $script:Mode='retry';$script:Calls=0
  . (Get-LmmLibrary 'common.ps1')
  if($script:Calls -ne 2){throw 'Transient fetch failure was not retried.'}
  $script:Mode='fail';$script:Calls=0
  Assert-Throws { . (Get-LmmLibrary 'common.ps1') }
  if($script:Calls -ne 3){throw 'Retries were not bounded.'}
  foreach($mode in @('empty','invalid')){
    $script:Mode=$mode
    Assert-Throws { . (Get-LmmLibrary 'common.ps1') }
  }
  New-Item -ItemType Directory -Path $root | Out-Null
  $local=Join-Path $root ('local '+[char]0x6D4B+[char]0x8BD5+' libraries')
  New-Item -ItemType Directory -Path $local | Out-Null
  $code='$LmmUnicode="'+[char]0x6D4B+[char]0x8BD5+'"; function Get-LmmLocalValue { $LmmUnicode }'
  [IO.File]::WriteAllText((Join-Path $local 'local.ps1'),$code,[Text.UTF8Encoding]::new($false))
  $env:LMM_LIB_DIR=$local;$script:Calls=0
  . (Get-LmmLibrary 'local.ps1')
  if((Get-LmmLocalValue) -ne ([string][char]0x6D4B+[char]0x8BD5)){throw 'UTF-8 local library changed text.'}
  Assert-Throws { . (Get-LmmLibrary 'missing.ps1') }
  if($script:Calls -ne 0){throw 'Local override silently fetched a missing library.'}
  if([Net.ServicePointManager]::SecurityProtocol -ne $beforeProtocol){throw 'Protocol setting leaked.'}
  Write-Host 'Library import scope, fixed URL, retries, errors and UTF-8 local imports passed.'
} finally {
  $env:LMM_LIB_DIR=$beforeDir;$env:HTTPS_PROXY=$beforeProxy;$env:HTTP_PROXY=$beforeHttp
  [Net.ServicePointManager]::SecurityProtocol=$beforeProtocol
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
