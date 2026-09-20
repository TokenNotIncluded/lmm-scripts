function Setting([string]$Name, [int]$Default, [int]$Maximum) {
    $raw = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($raw)) { return $Default }
    $number = 0
    if ($raw -notmatch '^[1-9][0-9]*$' -or -not [int]::TryParse($raw, [ref]$number) -or $number -gt $Maximum) { throw "$Name must be between 1 and $Maximum." }
    return $number
}
function QuoteArgument([string]$Value) {
    if($Value -notmatch '[\s"]' -and $Value.Length){return $Value}
    return '"' + [regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1') + '"'
}
function Stop-InstallChild($Process) {
    if($Process.HasExited){return}
    $killer=$null
    if($env:SystemRoot){$killer=Join-Path $env:SystemRoot 'System32\taskkill.exe'}
    if($killer -and (Test-Path -LiteralPath $killer)){ & $killer /PID $Process.Id /T /F 2>$null | Out-Null }
    if(-not $Process.HasExited){try{$Process.Kill($true)}catch{$Process.Kill()}}
    [void]$Process.WaitForExit(10000)
}
function Invoke-Bounded([string]$Executable,[string[]]$Arguments) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Executable; $info.UseShellExecute=$false
    if ((Get-Location).Provider.Name -eq 'FileSystem') { $info.WorkingDirectory=(Get-Location).ProviderPath }
    $info.Arguments=($Arguments | ForEach-Object { QuoteArgument $_ }) -join ' '
    $process=New-Object Diagnostics.Process; $process.StartInfo=$info
    $started=$false
    try {
      $started=$process.Start()
      if(-not $started){throw 'Could not start the installation process.'}
      $watch=[Diagnostics.Stopwatch]::StartNew(); $last=0
      while(-not $process.WaitForExit(1000)) {
        if($watch.Elapsed.TotalSeconds -gt $CommandTimeout){
          Stop-InstallChild $process
          throw 'Operation timed out. Increase LMM_COMMAND_TIMEOUT for slow networks and rerun.'
        }
        if($watch.Elapsed.TotalSeconds-$last -ge 15){Write-Log ('Still working: {0:N0}s elapsed.' -f $watch.Elapsed.TotalSeconds);$last=$watch.Elapsed.TotalSeconds}
      }
      $global:LASTEXITCODE=$process.ExitCode
      if($process.ExitCode -ne 0){throw "Installation command failed with exit code $($process.ExitCode)."}
    } finally {
      if($started -and -not $process.HasExited){Stop-InstallChild $process}
      $process.Dispose()
    }
}
function Invoke-Native([string]$Command, [string[]]$Arguments) {
  if ([IO.Path]::GetExtension($Command) -ieq '.cmd') {
    if ((Test-Path -LiteralPath $Command) -and (Select-String -LiteralPath $Command -SimpleMatch 'Managed by LMM installers' -Quiet)) {
      $launcherLines=@(Get-Content -LiteralPath $Command)
      foreach ($pathLine in $launcherLines) {
        if ($pathLine -match '^set "PATH=%~dp0\.\.\\(.+);%PATH%"$') {
          $runtime=[IO.Path]::GetFullPath((Join-Path (Split-Path (Split-Path $Command)) $Matches[1]))
          if (!$runtime.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Managed runtime escaped its root.' }
          if (!(Test-Path -LiteralPath $runtime -PathType Container)) { throw 'Managed runtime is missing. Rerun the installer.' }
          $env:PATH="$runtime;$env:PATH"
        }
      }
      $line=$launcherLines[-1]
      if ($line -match '^"%~dp0\.\.\\(.+)" %\*$') {
        $resolved=[IO.Path]::GetFullPath((Join-Path (Split-Path (Split-Path $Command)) $Matches[1]))
        if (!$resolved.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Managed launcher target escaped its root.' }
        $Command=$resolved
      }
    }
    if ([IO.Path]::GetExtension($Command) -ieq '.cmd') {
    $parent=Split-Path $Command
    $binName=[IO.Path]::GetFileNameWithoutExtension($Command).ToLowerInvariant()
    switch ($binName) {
      'npm' { $packageName='npm' }
      'pi' { $packageName='@earendil-works/pi-coding-agent' }
      'pnpm' { $packageName='pnpm' }
      'dsh' { $packageName='@deepseek-ai/dsh' }
      default { throw 'Unsupported command shim; use the managed installer or a native executable.' }
    }
    $packageRoot=[IO.Path]::GetFullPath((Join-Path $parent ('node_modules/' + $packageName)))
    $manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $binProperty=$manifest.PSObject.Properties['bin']
    if (!$binProperty) { throw 'Package manifest has no bin entry.' }
    $bins=$binProperty.Value
    $relative=$null
    if ($bins -is [string]) { $relative=$bins }
    elseif ($null -ne $bins -and $bins.PSObject.Properties[$binName]) { $relative=$bins.PSObject.Properties[$binName].Value }
    if ($relative -isnot [string] -or !$relative -or [IO.Path]::IsPathRooted($relative)) { throw 'Invalid package bin entry.' }
    $entry=[IO.Path]::GetFullPath((Join-Path $packageRoot $relative))
    if (!$entry.StartsWith($packageRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Package bin entry escaped its package.' }
    if (!(Test-Path -LiteralPath $entry)) { throw 'Client entry is missing. Rerun with -Update.' }
    $Command=(Get-Command node.exe).Source
    $Arguments=@($entry)+$Arguments
    }
  }
  Invoke-Bounded $Command $Arguments
}
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
