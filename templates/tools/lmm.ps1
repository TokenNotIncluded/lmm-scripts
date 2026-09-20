function Install-Lmm {
  $script:Phase='LMM CLI'; $destination=Join-Path $Root "apps\lmm\$LmmVersion-$Platform"
  if (-not $Update -and (Test-Path -LiteralPath (Join-Path $destination 'lmm.exe')) -and (Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { $script:Client=Join-Path $destination 'lmm.exe'; return }
  $work=Join-Path $script:Stage 'lmm'
  if ($FromSource) {
    $cargo=Get-Command cargo.exe -ErrorAction SilentlyContinue
    if (-not $cargo) { throw 'Source install needs Rust 1.88+ and Visual Studio C++ Build Tools. Install those, then retry -FromSource.' }
    $cargoRoot=Join-Path $script:Stage 'cargo'
    Invoke-Native $cargo.Source @('install','lmm-cli','--version',$LmmVersion,'--locked','--root',$cargoRoot)
    New-Item -ItemType Directory -Path $work | Out-Null
    Copy-Item -LiteralPath (Join-Path $cargoRoot 'bin\lmm.exe') -Destination $work
  } else {
    $hash=$LmmHashes[$Platform]
    if (-not $hash) { throw "No prebuilt LMM CLI for $Platform yet. Use -FromSource with Rust 1.88+ and build tools." }
    $name="lmm-v$LmmVersion-$Platform.zip"; $archive=Join-Path $script:Cache $name
    Get-VerifiedFile "$LmmReleaseBase/$name" $archive $hash
    Expand-Archive -LiteralPath $archive -DestinationPath $work
  }
  Invoke-Native (Join-Path $work 'lmm.exe') @('--version')
  Set-Content -LiteralPath (Join-Path $work '.lmm-managed') -Value $LmmVersion
  New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
  if (Test-Path -LiteralPath $destination) {
    if (!(Test-Path -LiteralPath (Join-Path $destination '.lmm-managed'))) { throw "Refusing unowned directory: $destination" }
    $destination += '-reinstall-' + [Guid]::NewGuid().ToString('N')
  }
  Move-Item -LiteralPath $work -Destination $destination; $script:Client=Join-Path $destination 'lmm.exe'
}
function Install-Tool { Install-Lmm }
