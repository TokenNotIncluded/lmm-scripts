$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\pi.ps1' }
npm.cmd install -g --ignore-scripts @earendil-works/pi-coding-agent@0.85.1
if ($LASTEXITCODE) { exit $LASTEXITCODE }
pi.cmd install npm:@tokennotincluded/pi-lmm-provider@0.1.0-alpha.1
exit $LASTEXITCODE
