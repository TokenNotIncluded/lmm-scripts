param([ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_-]*$')][string]$Profile = 'web')
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\dsh.ps1 [-Profile name]' }
npm.cmd install -g @deepseek-ai/dsh@latest pnpm@latest
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$response = Invoke-WebRequest -UseBasicParsing -Method Head -Uri 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/latest'
$finalUri = $response.BaseResponse.ResponseUri
if (-not $finalUri) { $finalUri = $response.BaseResponse.RequestMessage.RequestUri }
$url = [Uri]$finalUri
if (-not $url -or $url.Scheme -ne 'https' -or $url.Host -ne 'github.com' -or -not $url.IsDefaultPort -or $url.UserInfo -or $url.Query -or $url.Fragment -or $url.AbsolutePath -notmatch '^/TokenNotIncluded/dsh-lmm-provider/releases/tag/([a-zA-Z0-9][a-zA-Z0-9._-]*)$') { throw 'Unexpected plugin release URL' }
$pluginUrl = 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/' + $Matches[1] + '/dsh-lmm-provider.tgz'
dsh.cmd plugin --profile $Profile add $pluginUrl --ignore-scripts
exit $LASTEXITCODE
