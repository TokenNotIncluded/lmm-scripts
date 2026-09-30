$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\pi.ps1' }
$installer = Invoke-RestMethod https://pi.dev/install.ps1
& ([scriptblock]::Create($installer + "`n" + @'
$pi = Join-Path (Get-PiBinDir) 'pi.cmd'
& $pi --version
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$env:LMM_PI_BIN = $pi
npm.cmd exec --yes --package=@tokennotincluded/pi-lmm-provider@alpha -- lmm-pi-provider git:github.com/TokenNotIncluded/pi-lmm-provider@83e4c3ec22e9d9909904141f43c7424c59b7a474
exit $LASTEXITCODE
'@))
