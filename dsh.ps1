param([ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_-]*$')][string]$Profile = 'web')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\dsh.ps1 [-Profile name]' }
npm.cmd install -g @deepseek-ai/dsh@0.1.5-rc.2 pnpm@11.7.0
if ($LASTEXITCODE) { exit $LASTEXITCODE }
dsh.cmd plugin --profile $Profile add https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/v0.1.0-alpha.2/tokennotincluded-dsh-lmm-provider-0.1.0-alpha.2.tgz --ignore-scripts
exit $LASTEXITCODE
