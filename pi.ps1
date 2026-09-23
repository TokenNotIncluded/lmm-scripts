$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\pi.ps1' }
$installer = Invoke-RestMethod https://pi.dev/install.ps1
& ([scriptblock]::Create($installer + "`n" + @'
$pi = Join-Path (Get-PiBinDir) 'pi.cmd'
$version = & $pi --version
if ($LASTEXITCODE) { exit $LASTEXITCODE }
if ($version -notmatch '^0\.(86\.[1-9]\d*|87\.\d+)$') { Write-Warning "Pi $version installed; LMM alpha supports 0.86.1 through 0.87.x, plugin skipped."; exit 0 }
$env:LMM_PI_BIN = $pi
npm.cmd exec --yes --package=@tokennotincluded/pi-lmm-provider@0.1.0-alpha.2 -- lmm-pi-provider npm:@tokennotincluded/pi-lmm-provider@0.1.0-alpha.2
exit $LASTEXITCODE
'@))
