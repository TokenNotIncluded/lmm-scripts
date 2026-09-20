function Assert-PiShell {
  # Follow Pi's shellPath -> Git Bash -> PATH lookup, without editing settings.
  $agentDirectory=$env:PI_CODING_AGENT_DIR
  if (!$agentDirectory) { $agentDirectory=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.pi\agent' }
  $settingsPath=Join-Path $agentDirectory 'settings.json'
  if (Test-Path -LiteralPath $settingsPath) {
    try { $settings=Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Invalid Pi settings: $settingsPath. Repair the JSON before installing." }
    if ($null -eq $settings) { throw "Invalid Pi settings: $settingsPath" }
    $property=$settings.PSObject.Properties['shellPath']
    if ($property -and $property.Value) {
      $shell=[string]$property.Value
      if (Test-Path -LiteralPath $shell -PathType Leaf) { return }
      if (Get-Command $shell -CommandType Application -ErrorAction SilentlyContinue) { return }
      throw "Pi shellPath does not exist: $shell. Correct it in $settingsPath."
    }
  }
  if ($env:ProgramFiles -and (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') -PathType Leaf)) { return }
  if (Get-Command 'bash.exe' -CommandType Application -ErrorAction SilentlyContinue) { return }
  throw 'Pi requires Bash on Windows. Install Git for Windows, reopen PowerShell, or set shellPath in Pi settings. See https://pi.dev/docs/latest/windows'
}
function Install-Tool {
  Install-Node; Set-NpmNetwork
  Install-Client '@earendil-works/pi-coding-agent' $PiVersion 'pi'
  $script:Phase='Pi LMM provider'
  Invoke-WithRegistryRetry $script:Client @('install',"npm:@tokennotincluded/pi-lmm-provider@$PiProviderVersion")
}
