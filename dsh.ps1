param([ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_-]*$')][string]$Profile = 'web')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\dsh.ps1 [-Profile name]' }
npm.cmd install -g @deepseek-ai/dsh@latest pnpm@latest
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/TokenNotIncluded/dsh-lmm-provider/releases/latest'
$asset = @($release.assets | Where-Object { $_.name -eq 'dsh-lmm-provider.tgz' })
if ($release.draft -or $release.prerelease -or $asset.Count -ne 1) { throw 'No published DSH LMM plugin release found' }
$url = [Uri]$asset[0].browser_download_url
if ($url.Scheme -ne 'https' -or $url.Host -ne 'github.com' -or -not $url.IsDefaultPort -or $url.UserInfo -or $url.Query -or $url.Fragment -or $url.AbsolutePath -notmatch '^/TokenNotIncluded/dsh-lmm-provider/releases/download/[^/]+/dsh-lmm-provider\.tgz$') { throw 'Unexpected plugin release URL' }
dsh.cmd plugin --profile $Profile add $url.AbsoluteUri --ignore-scripts
exit $LASTEXITCODE
