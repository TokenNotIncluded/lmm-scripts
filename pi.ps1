$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\pi.ps1' }
$installer = Invoke-RestMethod https://pi.dev/install.ps1
& ([scriptblock]::Create($installer + "`n" + @'
$pi = Join-Path (Get-PiBinDir) 'pi.cmd'
& $pi --version
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$env:LMM_PI_BIN = $pi
$plugin = '@tokennotincluded/pi-lmm-provider@0.1.0-alpha.7'
npm.cmd exec --yes --package="$plugin" '--' lmm-pi-provider "npm:$plugin"
exit $LASTEXITCODE
'@))
