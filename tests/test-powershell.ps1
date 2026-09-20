$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot
foreach($file in Get-ChildItem -LiteralPath $project -Filter '*.ps1') {
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if($errors.Count) { throw ($errors | Out-String) }
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'lmm.ps1'),[ref]$tokens,[ref]$errors)
foreach($definition in $ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) { . ([scriptblock]::Create($definition.Extent.Text)) }
foreach($library in Get-ChildItem (Join-Path $project 'templates/lib') -Filter '*.ps1') { . $library.FullName }
$Target='test';$Network='official';$Update=$false;$script:Phase='test'
$Retries=2;$ConnectTimeout=1;$StallTimeout=2;$DownloadTimeout=10;$CommandTimeout=1;$MinSpeed=1
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('lmm-ps-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$fixture=[Text.Encoding]::UTF8.GetBytes('verified fixture download content')
$expectedFile=Join-Path $testRoot 'expected';[IO.File]::WriteAllBytes($expectedFile,$fixture)
$expected=(Get-FileHash -LiteralPath $expectedFile -Algorithm SHA256).Hash.ToLowerInvariant()
function Get-DownloadUrls { return @('https://test.invalid/artifact') }
function Get-Command { param([string]$Name) if($Name -eq 'curl.exe'){return $null};return Microsoft.PowerShell.Core\Get-Command $Name }
Add-Type -TypeDefinition @'
using System; using System.IO;
public class InterruptedFixture : Stream {
 private byte[] data; private bool sent;
 public InterruptedFixture(byte[] bytes){data=bytes;}
 public override int Read(byte[] buffer,int offset,int count){if(sent)throw new IOException("interrupted");sent=true;int n=Math.Min(8,data.Length);Array.Copy(data,0,buffer,offset,n);return n;}
 public override bool CanRead {get{return true;}} public override bool CanSeek {get{return false;}} public override bool CanWrite {get{return false;}}
 public override long Length {get{return data.Length;}} public override long Position {get{return 0;}set{throw new NotSupportedException();}}
 public override void Flush(){} public override long Seek(long a,SeekOrigin b){throw new NotSupportedException();}
 public override void SetLength(long n){throw new NotSupportedException();}public override void Write(byte[] b,int o,int c){throw new NotSupportedException();}
}
'@
$script:Mode='resume';$script:Requests=0;$script:Offsets=@()
function New-DownloadRequest([Uri]$Uri) {
  $script:Requests++
  $r=[pscustomobject]@{Timeout=0;ReadWriteTimeout=0;AllowAutoRedirect=$true;Proxy=$null;Offset=0L;Attempt=$script:Requests;Uri=$Uri}
  $r | Add-Member ScriptMethod AddRange {param($value) $this.Offset=$value}
  $r | Add-Member ScriptMethod GetResponse {
    $script:Offsets+= $this.Offset
    $offset=if($script:Mode -eq 'ignore-range'){0}else{$this.Offset}
    $bytes=if($script:Mode -eq 'corrupt'){[Text.Encoding]::UTF8.GetBytes('corrupt')}elseif($offset){[byte[]]$fixture[$offset..($fixture.Length-1)]}else{$fixture}
    $response=[pscustomobject]@{ResponseUri=$this.Uri;StatusCode=if($offset){206}else{200};ContentLength=$bytes.Length;Headers=@{'Content-Range'="bytes $offset-$($fixture.Length-1)/$($fixture.Length)"};Bytes=$bytes;Interrupt=($script:Mode -eq 'resume' -and $this.Attempt -eq 1)}
    $response | Add-Member ScriptMethod GetResponseStream {if($this.Interrupt){return [InterruptedFixture]::new($this.Bytes)};return [IO.MemoryStream]::new($this.Bytes)}
    $response | Add-Member ScriptMethod Close {}
    return $response
  }
  return $r
}
try {
  $destination=Join-Path $testRoot 'artifact'
  Get-VerifiedFile 'https://test.invalid/artifact' $destination $expected
  if($script:Offsets[1] -ne 8 -or (Get-Hash $destination) -ne $expected) { throw 'Interrupted transfer did not resume correctly' }
  $before=$script:Requests;Get-VerifiedFile 'https://test.invalid/artifact' $destination $expected
  if($script:Requests -ne $before) { throw 'Verified cache was downloaded again' }
  Remove-Item -LiteralPath $destination
  [IO.File]::WriteAllText("$destination.part",'stale prefix');$script:Mode='ignore-range'
  Get-VerifiedFile 'https://test.invalid/artifact' $destination $expected
  if((Get-Hash $destination) -ne $expected) { throw 'Server without Range support corrupted the file' }
  Remove-Item -LiteralPath $destination;$script:Mode='corrupt';$refused=$false
  try { Get-VerifiedFile 'https://test.invalid/artifact' $destination $expected } catch { $refused=$true }
  if(!$refused -or (Test-Path -LiteralPath $destination)) { throw 'Corrupt download was accepted' }
  $refused=$false;try { Get-VerifiedFile 'http://test.invalid/artifact' $destination $expected } catch { $refused=$true }
  if(!$refused) { throw 'HTTP was accepted' }
  if((QuoteArgument 'C:\Folder With Spaces\') -ne '"C:\Folder With Spaces\\"') { throw 'Native argument quoting lost a trailing slash' }
  $refused=$false;$timer=[Diagnostics.Stopwatch]::StartNew()
  try { Invoke-Bounded (Get-Process -Id $PID).Path @('-NoProfile','-Command','Start-Sleep -Seconds 10') } catch { $refused=$true }
  if(!$refused -or $timer.Elapsed.TotalSeconds -gt 8) { throw 'Native process timeout did not stop the child' }
  Write-Host 'PowerShell syntax, real-stream resume, Range fallback, cache, checksum, HTTPS, quoting and process timeout checks passed.'
} finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }
