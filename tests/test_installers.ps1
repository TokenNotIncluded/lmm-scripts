$ErrorActionPreference='Stop'
$Root=Split-Path $PSScriptRoot
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
foreach($name in @('pi.ps1','dsh.ps1')){
    $tokens=$null;$errors=$null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $name),[ref]$tokens,[ref]$errors)|Out-Null
    Assert ($errors.Count -eq 0) ($errors | Out-String)
}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'templates/installer.ps1'),[ref]$tokens,[ref]$errors)
foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
    if($definition.Name -in @('Say','Matches','Download','QuoteArgument')){Invoke-Expression $definition.Extent.Text}
}
$App='test';$Retries=2;$ConnectTimeout=1;$StallTimeout=2;$DownloadTimeout=10
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('lmm-installer-tests-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temp | Out-Null
$Fixture=[Text.Encoding]::UTF8.GetBytes('verified fixture archive content')
$Sha=[Security.Cryptography.SHA256]::Create()
$Hash=([BitConverter]::ToString($Sha.ComputeHash($Fixture))).Replace('-','').ToLowerInvariant()
$script:Requests=0;$script:Offsets=@();$script:Interrupt=$false;$script:Corrupt=$false;$script:IgnoreRange=$false
Add-Type -TypeDefinition @'
using System; using System.IO;
public class InterruptedDownload : Stream {
 private byte[] data; private bool sent;
 public InterruptedDownload(byte[] data){this.data=data;}
 public override int Read(byte[] buffer,int offset,int count){if(sent)throw new IOException("interrupted fixture");sent=true;int n=Math.Min(8,data.Length);Array.Copy(data,0,buffer,offset,n);return n;}
 public override bool CanRead=>true; public override bool CanSeek=>false; public override bool CanWrite=>false;
 public override long Length=>data.Length; public override long Position {get=>0;set=>throw new NotSupportedException();}
 public override void Flush(){} public override long Seek(long a,SeekOrigin b)=>throw new NotSupportedException();
 public override void SetLength(long n)=>throw new NotSupportedException();public override void Write(byte[] b,int o,int c)=>throw new NotSupportedException();
}
'@
function New-DownloadRequest([Uri]$Uri){
    $script:Requests++
    $request=[pscustomobject]@{Timeout=0;ReadWriteTimeout=0;UserAgent='';Proxy=$null;Offset=0L;Attempt=$script:Requests}
    $request|Add-Member ScriptMethod AddRange {param($offset) $this.Offset=$offset}
    $request|Add-Member ScriptMethod GetResponse {
        $script:Offsets+= $this.Offset
        $offset=if($script:IgnoreRange){0}else{$this.Offset}
        $data=if($script:Corrupt){[Text.Encoding]::UTF8.GetBytes('corrupt')}elseif($offset){[byte[]]$Fixture[$offset..($Fixture.Length-1)]}else{$Fixture}
        $response=[pscustomobject]@{StatusCode=if($offset){206}else{200};ContentLength=$data.Length;Headers=@{'Content-Range'="bytes $offset-$($Fixture.Length-1)/$($Fixture.Length)"};Bytes=$data;Interrupt=($script:Interrupt -and $this.Attempt -eq 1)}
        $response|Add-Member ScriptMethod GetResponseStream {if($this.Interrupt){return [InterruptedDownload]::new($this.Bytes)};return [IO.MemoryStream]::new($this.Bytes)}
        $response|Add-Member ScriptMethod Close {}
        return $response
    }
    return $request
}
function Start-Sleep {param($Seconds)}
try {
    $File=Join-Path $Temp 'runtime.zip'
    $script:Interrupt=$true
    Download ([Uri]'https://example.invalid/runtime.zip') $File $Hash
    Assert (Matches $File $Hash) 'Interrupted transfer did not recover with checksum validation.'
    Assert ($script:Requests -eq 2) 'Expected a bounded retry.'
    Assert ($script:Offsets[1] -eq 8) 'Partial bytes were not resumed.'
    $script:Requests=0
    Download ([Uri]'https://example.invalid/runtime.zip') $File $Hash
    Assert ($script:Requests -eq 0) 'Verified offline cache should not use the network.'
    Remove-Item -LiteralPath $File
    [IO.File]::WriteAllText("$File.part",'stale prefix')
    $script:Interrupt=$false;$script:IgnoreRange=$true;$script:Requests=0
    Download ([Uri]'https://example.invalid/runtime.zip') $File $Hash
    Assert (Matches $File $Hash) 'Server without range support should restart safely.'
    Remove-Item -LiteralPath $File
    $script:Corrupt=$true;$script:Requests=0;$Rejected=$false
    try { Download ([Uri]'https://example.invalid/runtime.zip') $File $Hash } catch { $Rejected=$true }
    Assert $Rejected 'Checksum mismatch was accepted.'
    Assert ($script:Requests -eq 2) 'Retries were not bounded.'
    Assert (-not (Test-Path -LiteralPath $File)) 'Corrupt archive was promoted.'
    $Rejected=$false
    try { Download ([Uri]'http://example.invalid/runtime.zip') $File $Hash } catch { $Rejected=$true }
    Assert $Rejected 'Insecure transport was accepted.'
    Assert ((QuoteArgument 'C:\Folder With Spaces\') -eq '"C:\Folder With Spaces\\"') 'Native command quoting lost trailing slashes.'
    Write-Host 'PowerShell parsing, retry, resume, cache, checksum, HTTPS and path quoting tests passed.'
} finally {
    $Sha.Dispose()
    Remove-Item -LiteralPath $Temp -Recurse -Force
}
