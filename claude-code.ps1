[CmdletBinding(PositionalBinding=$false)]
param([string]$Root='', [string]$Version='',
  [ValidateSet('auto','official','china')][string]$Network='official',
  [switch]$Check,[switch]$Update,[switch]$Launch,[switch]$DryRun,[switch]$Help,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$RunArgs=@())
$ErrorActionPreference='Stop'
$Target='claude-code'
$LibRevision='60692bd80622a0d3d80ee501eacb8db139641a3e'
if ($Help) {
  Write-Output "Install $Target. Options: -Check -Update -Launch -DryRun -Root PATH -Version VERSION -Network official. Uses upstream locations and update policies. LMM_LIB_DIR selects local helpers."
  exit 0
}
function Get-LmmLibrary([string]$Name) {
  if ($env:LMM_LIB_DIR) {
    $text=[IO.File]::ReadAllText((Join-Path $env:LMM_LIB_DIR $Name),[Text.Encoding]::UTF8)
  } else {
    $uri="https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/$LibRevision/templates/lib/$Name"
    $text=$null
    $protocol=[Net.ServicePointManager]::SecurityProtocol
    try {
      [Net.ServicePointManager]::SecurityProtocol=$protocol -bor [Net.SecurityProtocolType]::Tls12
      $options=@{Uri=$uri;UseBasicParsing=$true;TimeoutSec=60;ErrorAction='Stop'}
      $proxyValue=if($env:HTTPS_PROXY){$env:HTTPS_PROXY}else{$env:HTTP_PROXY}
      if ($proxyValue) {
        $proxy=[Uri]$proxyValue
        $options.Proxy=$proxy.GetLeftPart([UriPartial]::Authority)
        if ($proxy.UserInfo) {
          $parts=$proxy.UserInfo.Split(':',2)
          $password=if($parts.Length -eq 2){[Uri]::UnescapeDataString($parts[1])}else{''}
          $secure=ConvertTo-SecureString $password -AsPlainText -Force
          $options.ProxyCredential=New-Object System.Management.Automation.PSCredential([Uri]::UnescapeDataString($parts[0]),$secure)
        }
      }
      for ($attempt=1;$attempt -le 3;$attempt++) {
        try {
          $response=Invoke-WebRequest @options
          $text=[Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
          break
        } catch { if ($attempt -eq 3) { throw "Cannot fetch library $Name at $LibRevision. Check the network or set LMM_LIB_DIR." } }
      }
    } finally { [Net.ServicePointManager]::SecurityProtocol=$protocol }
  }
  if ([string]::IsNullOrWhiteSpace($text)) { throw "Empty library: $Name" }
  return [scriptblock]::Create($text)
}

try {
  . (Get-LmmLibrary 'external.ps1')
  Invoke-ExternalSetup -Target $Target -Root $Root -Version $Version -Network $Network -Check:$Check -Update:$Update -Launch:$Launch -DryRun:$DryRun -RunArgs $RunArgs
  exit 0
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }
