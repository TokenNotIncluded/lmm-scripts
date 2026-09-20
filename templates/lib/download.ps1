function Set-RequestProxy($request) {
            $proxyValue = if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { $env:HTTP_PROXY }
            if ($proxyValue) {
                $proxyUri = [Uri]$proxyValue
                if ($proxyUri.Scheme -notin @('http','https')) { throw 'Use an HTTP(S) proxy with Windows PowerShell; SOCKS needs a local HTTP proxy adapter.' }
                $proxy = New-Object Net.WebProxy($proxyUri.GetLeftPart([UriPartial]::Authority))
                if ($proxyUri.UserInfo) {
                    $parts=$proxyUri.UserInfo.Split(':',2)
                    $password=if ($parts.Length -eq 2) { [Uri]::UnescapeDataString($parts[1]) } else { '' }
                    $proxy.Credentials=New-Object Net.NetworkCredential([Uri]::UnescapeDataString($parts[0]),$password)
                }
                if ($env:NO_PROXY) {
                    $proxy.BypassList=@($env:NO_PROXY.Split(',') | ForEach-Object { $hostName=$_.Trim().TrimStart('.'); if($hostName -eq '*') { '.*' } elseif($hostName) { '^https?://([^/]+\.)?' + [regex]::Escape($hostName) + '(:[0-9]+)?(/|$)' } })
                }
                $request.Proxy=$proxy
            }
}
function New-DownloadRequest([Uri]$Uri) { return [Net.HttpWebRequest]::Create($Uri) }
function Get-RankedUrls([string[]]$Urls) {
  $scores = @(); $index = 0
  foreach ($url in $Urls) {
    $timer = [Diagnostics.Stopwatch]::StartNew(); $score = 999999
    try {
      $request = New-DownloadRequest ([Uri]$url)
      $request.Method = 'HEAD'; $request.Timeout = 4000; $request.AllowAutoRedirect = $true
      Set-RequestProxy $request
      $response = $request.GetResponse(); $response.Close(); $score = $timer.ElapsedMilliseconds
    } catch { } finally { $timer.Stop() }
    $scores += [pscustomobject]@{ Url=$url; Score=$score; Order=$index }; $index++
  }
  return @($scores | Sort-Object Score,Order | ForEach-Object { $_.Url })
}
function Get-DownloadUrls([string]$Official) {
  $mirrors = @()
  if ($Official.StartsWith('https://nodejs.org/dist/')) { $mirrors = @($Official.Replace('https://nodejs.org/dist/','https://npmmirror.com/mirrors/node/')) }
  elseif ($Official.StartsWith('https://github.com/')) { $mirrors = @("https://ghfast.top/$Official", "https://ghproxy.net/$Official") }
  if ($Network -eq 'official') { return @($Official) }
  if ($Network -eq 'china') { return @($mirrors) + @($Official) }
  return @(Get-RankedUrls (@($Official) + @($mirrors)))
}
function Receive-Stream([string]$Url, [string]$Path) {
  # Used on older Windows without curl.exe. ReadWriteTimeout bounds stalled reads.
  $offset = 0L
  if (Test-Path -LiteralPath $Path) { $offset = (Get-Item -LiteralPath $Path).Length }
  $request = New-DownloadRequest ([Uri]$Url)
  $request.Timeout = $ConnectTimeout*1000; $request.ReadWriteTimeout = $StallTimeout*1000; $request.AllowAutoRedirect = $true
  Set-RequestProxy $request
  if ($offset -gt 0) { $request.AddRange($offset) }
  $response = $null; $inputStream = $null; $outputStream = $null
  try {
    $response = $request.GetResponse()
    if ($response.ResponseUri.Scheme -ne 'https') { throw 'Insecure redirect refused.' }
    $mode = [IO.FileMode]::Create
    if ($offset -gt 0 -and [int]$response.StatusCode -eq 206) {
      if ($response.Headers['Content-Range'] -notlike "bytes $offset-*") { throw 'Invalid resume response.' }
      $mode = [IO.FileMode]::Append
    }
    $inputStream = $response.GetResponseStream()
    $outputStream = [IO.File]::Open($Path,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $buffer = New-Object byte[] 65536; $windowBytes = 0L; $total = 0L
    $window = [Diagnostics.Stopwatch]::StartNew(); $overall = [Diagnostics.Stopwatch]::StartNew()
    while (($read = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
      $outputStream.Write($buffer,0,$read); $windowBytes += $read; $total += $read
      if ($overall.Elapsed.TotalSeconds -gt $DownloadTimeout) { throw 'Download timeout.' }
      if ($window.Elapsed.TotalSeconds -ge $StallTimeout -and ($response.ContentLength -lt 0 -or $total -lt $response.ContentLength)) {
        if ($windowBytes / $window.Elapsed.TotalSeconds -lt $MinSpeed) { throw 'Download too slow; changing source.' }
        $window.Restart(); $windowBytes = 0
      }
    }
  } finally {
    if ($outputStream) { $outputStream.Dispose() }; if ($inputStream) { $inputStream.Dispose() }; if ($response) { $response.Close() }
  }
}
function Get-VerifiedFile([string]$Url, [string]$Destination, [string]$Expected) {
  $parsed=[Uri]$Url
  if ($parsed.Scheme -ne 'https' -or $parsed.UserInfo) { throw 'Download URLs must use HTTPS without credentials.' }
  foreach($file in @($Destination,"$Destination.part","$Destination.part.url")) { if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing symlink cache entries.' } }
  if (-not $Update -and (Test-Path -LiteralPath $Destination) -and (Get-Hash $Destination) -eq $Expected) { Write-Log "Cached: $([IO.Path]::GetFileName($Destination))"; return }
  $partial = "$Destination.part"; $sourceFile = "$partial.url"
  if ((Test-Path -LiteralPath $partial) -and (Get-Hash $partial) -eq $Expected) { Move-Item -LiteralPath $partial -Destination $Destination -Force; return }
  if ($env:LMM_NODE_BASE_URL -and $Url.StartsWith('https://nodejs.org/dist/')) { $Url=$Url.Replace('https://nodejs.org/dist',$env:LMM_NODE_BASE_URL.TrimEnd('/')) }
  $sourceNumber = 0
  foreach ($source in @(Get-DownloadUrls $Url)) {
    $sourceNumber++
    if ((Test-Path -LiteralPath $partial) -and (!(Test-Path -LiteralPath $sourceFile) -or (Get-Content -LiteralPath $sourceFile -Raw).Trim() -ne $source)) { Remove-Item -LiteralPath $partial -Force }
    Set-Content -LiteralPath $sourceFile -Value $source -Encoding ASCII
    foreach ($attempt in 1..$Retries) {
      Write-Log "Downloading $([IO.Path]::GetFileName($Destination)) (source $sourceNumber, attempt $attempt)"
      try {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
          Invoke-Native $curl.Source @('-q','--proto','=https','--proto-redir','=https','-fL','--connect-timeout',([string]$ConnectTimeout),'--max-time',([string]$DownloadTimeout),'--speed-time',([string]$StallTimeout),'--speed-limit',([string]$MinSpeed),'--continue-at','-','--output',$partial,$source)
        } else { Receive-Stream $source $partial }
        if ((Get-Hash $partial) -ne $Expected) { Remove-Item -LiteralPath $partial -Force; Write-Log 'Checksum mismatch; download will not be executed.'; break }
        Move-Item -LiteralPath $partial -Destination $Destination -Force
        Remove-Item -LiteralPath $sourceFile -Force -ErrorAction SilentlyContinue
        return
      } catch {
        Write-Log 'Transfer failed or stalled. Retrying, then trying another source.'
        if ($attempt -eq 1 -and (Test-Path -LiteralPath $partial)) {
          # Keep a partial for retry; a rejected Range gets a clean retry next source.
          if ($curl -and $LASTEXITCODE -in @(22,33,36)) { Remove-Item -LiteralPath $partial -Force }
        }
      }
    }
  }
  throw 'All download sources failed. Retry -Network official or -Network china; inspect your proxy/CA settings.'
}
