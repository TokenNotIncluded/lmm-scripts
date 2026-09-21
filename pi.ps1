$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\pi.ps1' }
$installer = Invoke-RestMethod https://pi.dev/install.ps1
& ([scriptblock]::Create($installer + "`n" + @'
$pi = Join-Path (Get-PiBinDir) 'pi.cmd'
$version = & $pi --version
if ($LASTEXITCODE) { exit $LASTEXITCODE }
if ($version -ne '0.85.1') { Write-Warning "Pi $version installed; LMM alpha requires 0.85.1, plugin skipped."; exit 0 }
& $pi install npm:@tokennotincluded/pi-lmm-provider@0.1.0-alpha.1
exit $LASTEXITCODE
'@))
