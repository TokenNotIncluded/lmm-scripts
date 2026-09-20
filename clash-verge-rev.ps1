$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\clash-verge-rev.ps1' }
winget install --exact --id ClashVergeRev.ClashVergeRev
exit $LASTEXITCODE
