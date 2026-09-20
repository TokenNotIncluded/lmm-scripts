function Write-Launcher {
  $destination=Join-Path $Root "bin\$Target.cmd"
  if ((Test-Path -LiteralPath $destination) -and !(Select-String -LiteralPath $destination -SimpleMatch 'Managed by LMM installers' -Quiet)) { throw "Refusing existing launcher: $destination" }
  if (!$script:Client.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Launcher target must remain inside the managed root.' }
  $clientRelative=$script:Client.Substring($Root.Length).TrimStart('\')
  # Keep the .cmd file ASCII: %~dp0 supports Unicode/space-containing user paths
  # without changing the user's console code page. Tail-call batch shims.
  $lines=@('@echo off','rem Managed by LMM installers','setlocal DisableDelayedExpansion')
  if ($script:NodeBin -and $script:NodeBin.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) {
    $nodeRelative=$script:NodeBin.Substring($Root.Length).TrimStart('\')
    $lines+=@("set `"PATH=%~dp0..\$nodeRelative;%PATH%`"")
  }
  if ($script:PnpmBin -and $script:PnpmBin.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase)) {
    $pmRelative=$script:PnpmBin.Substring($Root.Length).TrimStart('\')
    $lines+=@("set `"PATH=%~dp0..\$pmRelative;%PATH%`"")
  }
  $lines+=@("`"%~dp0..\$clientRelative`" %*")
  $temporary=Join-Path $script:Stage 'launcher.cmd'
  [IO.File]::WriteAllLines($temporary,$lines,[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $destination -Force
  if ($AddPath -and -not $NoPath) {
    $bin=Join-Path $Root 'bin'; $old=[string][Environment]::GetEnvironmentVariable('Path','User')
    if (@($old -split ';' | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') }).Count -eq 0) {
      try { [Environment]::SetEnvironmentVariable('Path',($old.TrimEnd(';')+';'+$bin).TrimStart(';'),'User') }
      catch { Write-Log 'Could not update user PATH. Use the full launcher path printed below.' }
    }
    $env:PATH="$bin;$env:PATH"
  }
}
