function Test-Node {
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $node -or -not $npm) { return $false }
  try { $versionText=(& $node.Source --version 2>$null | Out-String).Trim() } catch { return $false }
  if ($LASTEXITCODE -ne 0 -or $versionText -notmatch '^v([0-9]+)\.([0-9]+)\.[0-9]+') { return $false }
  $major=[int]$Matches[1];$minor=[int]$Matches[2]
  return (($major -eq 22 -and $minor -ge 19) -or $major -ge 24)
}
function Install-Node {
  $script:Phase = 'Node.js runtime'
  if (Test-Node) { $script:NodeBin = Split-Path (Get-Command node.exe).Source; return }
  $directory = Join-Path $Root "runtime\node-v$NodeVersion-$Platform"
  if (Test-Path -LiteralPath (Join-Path $directory 'node.exe')) { $env:PATH = "$directory;$env:PATH" }
  if (Test-Node) { $script:NodeBin = $directory; return }
  if ($NoInstallNode -or $NoBootstrap) { throw 'Need Node 22.19+ (22.x) or Node 24+, including npm.' }
  $hash = $NodeHashes[$Platform]
  if (-not $hash) { throw "No verified Node archive for $Platform" }
  $name = "node-v$NodeVersion-$Platform.zip"; $archive = Join-Path $script:Cache $name
  Get-VerifiedFile "https://nodejs.org/dist/v$NodeVersion/$name" $archive $hash
  $unpack = Join-Path $script:Stage 'runtime'; Expand-Archive -LiteralPath $archive -DestinationPath $unpack
  $extracted = Join-Path $unpack "node-v$NodeVersion-$Platform"
  Invoke-Native (Join-Path $extracted 'node.exe') @('--version')
  if (Test-Path -LiteralPath $directory) { throw "Managed runtime is present but unusable; inspect $directory before replacing." }
  Move-Item -LiteralPath $extracted -Destination $directory
  $script:NodeBin = $directory; $env:PATH = "$directory;$env:PATH"
}
function Set-NpmNetwork {
  if (-not $env:npm_config_cache) { $cache=(& npm.cmd config get cache 2>$null | Out-String).Trim(); if ($cache) { $env:npm_config_cache=$cache } else { $env:npm_config_cache=Join-Path $script:Cache 'npm' } }
  $env:npm_config_fetch_retries=[string]$Retries; $env:npm_config_fetch_timeout=[string]($StallTimeout*1000); $env:npm_config_fetch_retry_mintimeout='2000'; $env:npm_config_fetch_retry_maxtimeout='30000'; $env:npm_config_strict_ssl='true'; $env:npm_config_prefer_offline='true'
  if ($env:LMM_NPM_REGISTRY) { $env:npm_config_registry=$env:LMM_NPM_REGISTRY }
  $current = (& npm.cmd config get registry 2>$null | Out-String).Trim()
  if ($env:npm_config_registry -or ($current -and $current -ne 'https://registry.npmjs.org/')) { Write-Log 'Keeping your existing npm registry/proxy configuration.'; return }
  $script:NpmSelected = $true
  if ($Network -eq 'china') { $env:npm_config_registry='https://registry.npmmirror.com/' }
  elseif ($Network -eq 'official') { $env:npm_config_registry='https://registry.npmjs.org/' }
  else { $env:npm_config_registry = @(Get-RankedUrls @('https://registry.npmjs.org/','https://registry.npmmirror.com/'))[0] }
  Write-Log 'Registry selection affects this process only, not your global npm configuration.'
}
function Invoke-WithRegistryRetry([string]$Command,[string[]]$Arguments) {
  try { Invoke-Native $Command $Arguments } catch {
    if ($Network -ne 'auto' -or -not $script:NpmSelected) { throw }
    if ($env:npm_config_registry -eq 'https://registry.npmjs.org/') { $env:npm_config_registry='https://registry.npmmirror.com/' } else { $env:npm_config_registry='https://registry.npmjs.org/' }
    Write-Log 'Retrying with the alternate registry and the same cache.'
    Invoke-Native $Command $Arguments
  }
}
function Install-Client([string]$Package,[string]$Version,[string]$Entry) {
  $script:Phase="$Target client"; $destination=Join-Path $Root "apps\$Target\$Version"
  if (-not $Update -and (Test-Path -LiteralPath (Join-Path $destination "$Entry.cmd")) -and (Test-Path -LiteralPath (Join-Path $destination '.lmm-managed')) -and (Get-Content -LiteralPath (Join-Path $destination '.lmm-managed') -Raw).Trim() -eq "$Version|$ScriptVersion") { $script:Client=Join-Path $destination "$Entry.cmd"; return }
  if ($NoBootstrap) { throw 'Managed client is missing. Rerun without -NoBootstrap.' }
  $work=Join-Path $script:Stage 'client'; New-Item -ItemType Directory -Path $work | Out-Null
  $installArgs=@('install','--global','--prefix',$work,'--no-audit','--no-fund',"$Package@$Version")
  if ($Target -eq 'pi') {
    # https://pi.dev/docs/latest/quickstart: Pi ships a prebuilt CLI.
    $installArgs+=@('--ignore-scripts')
  } else {
    $allow='@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs'
    $npmHelp=(& npm.cmd install --help 2>$null | Out-String)
    if ($npmHelp.Contains('--allow-scripts')) { $installArgs+=@("--allow-scripts=$allow") }
    if ((& npm.cmd config get ignore-scripts 2>$null | Out-String).Trim() -eq 'true') { throw 'DSH needs native build scripts. Review your package-specific build policy; ignore-scripts=true will not be overridden.' }
  }
  Invoke-WithRegistryRetry (Get-Command npm.cmd).Source $installArgs
  Invoke-Native (Join-Path $work "$Entry.cmd") @('--version')
  Set-Content -LiteralPath (Join-Path $work '.lmm-managed') -Value "$Version|$ScriptVersion"
  New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
  if (Test-Path -LiteralPath $destination) {
    if (!(Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { throw "Refusing unowned directory: $destination" }
    $destination += '-reinstall-' + [Guid]::NewGuid().ToString('N')
  }
  Move-Item -LiteralPath $work -Destination $destination; $script:Client=Join-Path $destination "$Entry.cmd"
}
