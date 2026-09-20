function Install-Pnpm {
  $script:Phase='DSH package manager';$destination=Join-Path $Root "tools\pnpm\$PnpmVersion"
  if ((Test-Path -LiteralPath (Join-Path $destination 'pnpm.cmd')) -and (Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { $script:PnpmBin=$destination }
  elseif ($NoBootstrap) {
    $pm=Get-Command pnpm.cmd -ErrorAction SilentlyContinue
    if (!$pm) { throw 'pnpm is missing; rerun without -NoBootstrap.' }
    Invoke-Native $pm.Source @('--version');$script:PnpmBin=Split-Path $pm.Source
  } else {
    $work=Join-Path $script:Stage 'pnpm';New-Item -ItemType Directory -Path $work | Out-Null
    Invoke-WithRegistryRetry (Get-Command npm.cmd).Source @('install','--global','--prefix',$work,'--ignore-scripts','--no-audit','--no-fund',"pnpm@$PnpmVersion")
    Invoke-Native (Join-Path $work 'pnpm.cmd') @('--version')
    Set-Content -LiteralPath (Join-Path $work '.lmm-managed') -Value $PnpmVersion
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    if (Test-Path -LiteralPath $destination) {
      if (!(Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { throw 'Unowned pnpm installation directory.' }
      $destination+='-reinstall-'+[Guid]::NewGuid().ToString('N')
    }
    Move-Item -LiteralPath $work -Destination $destination;$script:PnpmBin=$destination
  }
  $env:PATH="$script:PnpmBin;$env:PATH"
}
function Install-Tool {
  Install-Node; Set-NpmNetwork
        Install-Pnpm
        Install-Client '@deepseek-ai/dsh' $DshVersion 'dsh'
        $script:Phase='DSH LMM provider'; $archive=Join-Path $script:Cache ($DshProviderUrl.Split('/')[-1])
        Get-VerifiedFile $DshProviderUrl $archive $DshProviderSha256
        # DSH 0.1.5 uses a shell to invoke pnpm on Windows. Passing absolute
        # paths containing spaces loses argument boundaries in that layer.
        # Keep the verified immutable package inside the profile and pass a
        # path-free file: spec; configure the store through environment instead.
        $profileHome=$env:DSH_HOME
        $userDirectory=[Environment]::GetFolderPath('UserProfile')
        if (!$profileHome) { $profileHome=Join-Path $userDirectory '.dsh' }
        elseif ($profileHome -eq '~') { $profileHome=$userDirectory }
        elseif ($profileHome.StartsWith('~/') -or $profileHome.StartsWith('~\')) { $profileHome=Join-Path $userDirectory $profileHome.Substring(2) }
        if (![IO.Path]::IsPathRooted($profileHome)) { $profileHome=Join-Path (Get-Location).ProviderPath $profileHome }
        $profileDirectory=Join-Path ([IO.Path]::GetFullPath($profileHome)) "profiles\$Profile"
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        $packageName='.lmm-provider-'+$DshProviderSha256.Substring(0,16)+'.tgz'
        $profilePackage=Join-Path $profileDirectory $packageName
        if (Test-Path -LiteralPath $profilePackage) {
          if ((Get-Hash $profilePackage) -ne $DshProviderSha256) { throw 'Conflicting installer package in the DSH profile; inspect it before retrying.' }
        } else {
          $pending=Join-Path $profileDirectory ('.lmm-package-'+[Guid]::NewGuid().ToString('N')+'.tmp')
          try { Copy-Item -LiteralPath $archive -Destination $pending; Move-Item -LiteralPath $pending -Destination $profilePackage -Force }
          finally { if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force } }
        }
        $env:npm_config_store_dir=Join-Path $script:Cache 'pnpm'
        Invoke-WithRegistryRetry $script:Client @('plugin','--profile',$Profile,'add',"file:$packageName",'--ignore-scripts')
}
