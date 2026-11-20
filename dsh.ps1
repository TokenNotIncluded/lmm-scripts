param(
  [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_-]*$')][string]$Profile = 'web',
  [ValidateSet('install','rollback','uninstall')][string]$Action = 'install',
  [switch]$UseExistingProfile
)
$ErrorActionPreference = 'Stop'
if ($args.Count) { throw 'Usage: .\dsh.ps1 [-Profile name] [-Action install|rollback|uninstall] [-UseExistingProfile]' }

function Assert-DshPath([string]$Path,[bool]$Directory) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { throw "Required DSH path is missing: $Path" }
  if ($item.PSIsContainer -ne $Directory) { throw "Unexpected DSH path type: $Path" }
  for ($part = $item; $part; $part = Get-Item -LiteralPath (Split-Path -Parent $part.FullName) -Force -ErrorAction SilentlyContinue) {
    if ($part.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked DSH path is not supported: $($part.FullName)" }
    if (-not (Split-Path -Parent $part.FullName)) { break }
  }
  return $item.FullName
}
function Get-DshDataPath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  if ($full -notmatch '^[A-Za-z]:\\') {
    throw 'Managed DSH requires a local drive path; UNC and device paths are not supported.'
  }
  $missing = New-Object 'System.Collections.Generic.List[string]'
  $nearest = $null
  for ($cursor = $full; $cursor; $cursor = Split-Path -Parent $cursor) {
    $item = $null
    try { $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop }
    catch [Management.Automation.ItemNotFoundException] {
      if (-not $nearest) {
        $part = Split-Path -Leaf $cursor
        if ($part -match '~[0-9]' -or $part.TrimEnd(' ','.') -cne $part) {
          throw 'An unresolved short-name or trimmed-name path is not supported by managed DSH.'
        }
        $missing.Insert(0,$part)
      }
    }
    if ($item) {
      if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Managed DSH data paths and their existing ancestors must be plain directories, not links.'
      }
      if (-not $nearest) { $nearest = $item.FullName }
    }
    if (-not (Split-Path -Parent $cursor)) { break }
  }
  if (-not $nearest) { throw 'Cannot inspect the existing ancestor of the DSH data path.' }
  if (-not ('LmmDshDirectoryIdentityV2' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class LmmDshDirectoryIdentityV2 {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share,
        IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path,
        uint capacity, uint flags);
    public static string Resolve(string directory) {
        // OPEN_EXISTING, metadata-only access, and BACKUP_SEMANTICS for a directory.
        using (SafeFileHandle file = CreateFileW(directory, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
            if (file.IsInvalid) throw new IOException("Cannot open the existing DSH directory for identity.");
            StringBuilder path = new StringBuilder(1024);
            uint length = GetFinalPathNameByHandleW(file, path, (uint)path.Capacity, 1);
            if (length >= path.Capacity && length <= 32768) {
                path = new StringBuilder((int)length + 1);
                length = GetFinalPathNameByHandleW(file, path, (uint)path.Capacity, 1);
            }
            if (length == 0 || length >= path.Capacity)
                throw new IOException("Cannot resolve the DSH directory to a local volume identity.");
            return path.ToString();
        }
    }
}
'@
  }
  # A volume GUID avoids treating drive-letter or existing 8.3 aliases as distinct roots.
  $resolved = [LmmDshDirectoryIdentityV2]::Resolve($nearest).TrimEnd('\')
  if ($resolved -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]+\}(\\|$)') {
    throw 'The DSH directory has no supported local volume identity.'
  }
  foreach ($part in $missing) { $resolved += '\' + $part }
  return $resolved
}
function Assert-DshDataSeparation([string]$DataRoot,[string]$RuntimeRoot) {
  $data = (Get-DshDataPath $DataRoot).TrimEnd('\') + '\'
  $runtime = (Get-DshDataPath $RuntimeRoot).TrimEnd('\') + '\'
  if ($data.StartsWith($runtime,[StringComparison]::OrdinalIgnoreCase) -or
      $runtime.StartsWith($data,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'DSH_HOME and the managed runtime root must not overlap.'
  }
}
function New-DshDirectory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-DshDirectory $parent) }
    [void](Assert-DshPath $parent $true)
    [void][IO.Directory]::CreateDirectory($Path)
  }
  return Assert-DshPath $Path $true
}
function Write-DshAtomic([string]$Path,[string]$Text) {
  [void](Assert-DshPath (Split-Path -Parent $Path) $true)
  if (Test-Path -LiteralPath $Path) { [void](Assert-DshPath $Path $false) }
  $temp = $Path + '.new-' + [guid]::NewGuid().ToString('N')
  try {
    $stream = [IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
      $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
      $stream.Write($bytes,0,$bytes.Length)
      $stream.Flush()
    } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
    else { [IO.File]::Move($temp,$Path) }
  } finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
  }
}
function Get-DshShim([string]$Id) {
  if ($Id -notmatch '^[0-9a-z.-]+-[0-9a-f]{16}$') { throw 'Invalid managed DSH installation ID.' }
  $eol = [string][char]13 + [char]10
  return (@(
    '@echo off',
    'rem lmm-dsh-managed-v1',
    'setlocal DisableDelayedExpansion',
    'if not defined DSH_HOME set "DSH_HOME=%~dp0..\..\.dsh"',
    ('"%~dp0..\share\lmm-dsh\installs\' + $Id + '\Scripts\dsh.exe" %*'),
    'exit /b %errorlevel%'
  ) -join $eol) + $eol
}
function Read-DshShim([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  [void](Assert-DshPath $Path $false)
  $text = [IO.File]::ReadAllText($Path)
  $match = [regex]::Match($text,'\\installs\\([0-9a-z.-]+-[0-9a-f]{16})\\Scripts\\dsh\.exe')
  if (-not $match.Success -or $text -cne (Get-DshShim $match.Groups[1].Value)) {
    throw "Refusing to replace an unmanaged DSH command: $Path"
  }
  return $match.Groups[1].Value
}
function Read-DshReceipt([string]$Id) {
  [void](Get-DshShim $Id)
  $directory = Join-Path $installs $Id
  [void](Assert-DshPath $directory $true)
  $path = Join-Path $directory '.lmm-install.json'
  [void](Assert-DshPath $path $false)
  $receipt = [IO.File]::ReadAllText($path) | ConvertFrom-Json
  if ($receipt.schema -ne 1 -or $receipt.id -cne $Id -or
      $receipt.wheel_sha256 -notmatch '^[0-9a-f]{64}$' -or
      $receipt.launcher_sha256 -notmatch '^[0-9a-f]{64}$' -or
      $receipt.version -notmatch '^[0-9a-z.-]+$' -or
      $Id -cne ($receipt.version + '-' + $receipt.wheel_sha256.Substring(0,16))) {
    throw 'Invalid managed DSH receipt.'
  }
  return $receipt
}
function Assert-DshRuntime([string]$Id) {
  $receipt = Read-DshReceipt $Id
  # Only this reviewed runtime is supported by this installer. Future versions must
  # add their complete payload contract before they can become rollback targets.
  if ($receipt.version -cne $wheelVersion -or $receipt.wheel_sha256 -cne $wheelHash) {
    throw 'This installer does not recognize the recorded DSH runtime version.'
  }
  $directory = Join-Path $installs $Id
  $launcher = Join-Path $directory 'Scripts\dsh.exe'
  [void](Assert-DshPath $launcher $false)
  [void](Assert-DshPath $receipt.base_python $false)
  if ((Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash -ine $receipt.launcher_sha256) {
    throw 'Managed DSH launcher checksum mismatch.'
  }
  foreach ($member in $payload) {
    $path = Join-Path $directory ('Lib\site-packages\deepseek_harness_runtime\' + $member.path)
    [void](Assert-DshPath $path $false)
    if ((Get-Item -LiteralPath $path).Length -ne $member.bytes -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $member.sha256) {
      throw 'Managed DSH runtime payload checksum mismatch.'
    }
  }
  return $launcher
}
function Find-DshPython {
  $candidates = @()
  foreach ($name in @('python.exe','python3.exe')) {
    $candidates += @(Get-Command $name -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
  }
  $py = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue
  if ($py) {
    # Listing installed interpreters does not request an installation.
    foreach ($line in @(& $py.Source -0p 2>$null)) {
      if ($line -match '([A-Za-z]:\\.*\\python(?:[0-9.]*)?\.exe)\s*$') { $candidates += $Matches[1] }
    }
  }
  foreach ($candidate in @($candidates | Select-Object -Unique)) {
    if ($candidate -match '\\Microsoft\\WindowsApps\\') { continue }
    try { [void](Assert-DshPath $candidate $false) } catch { continue }
    $result = @(& $candidate -I -c 'import json,platform,sys; print(json.dumps({"version":list(sys.version_info[:2]),"bits":platform.architecture()[0],"path":sys.executable}))' 2>$null)
    if ($LASTEXITCODE) { continue }
    try { $info = ($result -join '') | ConvertFrom-Json } catch { continue }
    if ($info.version[0] -eq 3 -and $info.version[1] -ge 10 -and $info.bits -eq '64bit') {
      return Assert-DshPath $info.path $false
    }
  }
  throw 'Install an existing 64-bit Python 3.10 or later, put it on PATH, and rerun. This installer does not install Python.'
}
function New-DshRuntime([string]$Id) {
  $directory = Join-Path $installs $Id
  if (Test-Path -LiteralPath $directory) { return Assert-DshRuntime $Id }
  $python = Find-DshPython
  $created = $false
  $complete = $false
  try {
    # Venvs contain absolute paths. Create at the final path; never rename a venv.
    [void][IO.Directory]::CreateDirectory($directory)
    $created = $true
    $archive = Join-Path $directory $wheelName
    Invoke-WebRequest -UseBasicParsing $wheelUrl -OutFile $archive
    if ((Get-Item -LiteralPath $archive).Length -ne 86959936 -or
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $wheelHash) {
      throw 'Official DSH wheel checksum mismatch.'
    }
    & $python -I -m venv $directory | Out-Host
    if ($LASTEXITCODE) { throw "DSH venv creation failed: $LASTEXITCODE" }
    $requirements = Join-Path $directory '.requirements.txt'
    $uri = (New-Object Uri($archive)).AbsoluteUri
    [IO.File]::WriteAllText($requirements,($uri + ' --hash=sha256:' + $wheelHash + [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
    $venvPython = Join-Path $directory 'Scripts\python.exe'
    & $venvPython -I -m pip --isolated install --disable-pip-version-check --no-input --no-index --no-deps --no-cache-dir --only-binary=:all: --require-hashes -r $requirements | Out-Host
    if ($LASTEXITCODE) { throw "DSH wheel installation failed: $LASTEXITCODE" }
    $probe = 'import importlib.metadata,json; import deepseek_harness_runtime as r; print(json.dumps({"version":importlib.metadata.version("deepseek-harness-runtime-bin"),"root":str(r.bundled_package_dir()),"runtime":str(r.bundled_runtime_path()),"argv":r.resolve_bundled_launch_args("exe")}))'
    $raw = @(& $venvPython -I -c $probe)
    if ($LASTEXITCODE) { throw 'Cannot inspect installed DSH runtime.' }
    $installed = ($raw -join '') | ConvertFrom-Json
    $packageRoot = Join-Path $directory 'Lib\site-packages\deepseek_harness_runtime'
    $runtime = Join-Path $packageRoot 'runtime\deepseek-harness-sdk-runtime-win-x64.exe'
    if ($installed.version -cne $wheelVersion -or
        [IO.Path]::GetFullPath($installed.root) -ine [IO.Path]::GetFullPath($packageRoot) -or
        [IO.Path]::GetFullPath($installed.runtime) -ine [IO.Path]::GetFullPath($runtime) -or
        @($installed.argv).Count -ne 1 -or $installed.argv[0] -ine $runtime) {
      throw 'Installed DSH wheel identity does not match its contract.'
    }
    $launcher = Join-Path $directory 'Scripts\dsh.exe'
    [void](Assert-DshPath $launcher $false)
    $receipt = [ordered]@{
      schema = 1; id = $Id; version = $wheelVersion; wheel_sha256 = $wheelHash
      base_python = $python
      launcher_sha256 = (Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Write-DshAtomic (Join-Path $directory '.lmm-install.json') ($receipt | ConvertTo-Json)
    [void](Assert-DshRuntime $Id)
    Remove-Item -LiteralPath $archive,$requirements -Force
    $complete = $true
    return $launcher
  } finally {
    if ($created -and -not $complete) { Remove-DshDirectory $directory }
  }
}
function Assert-DshTree([string]$Directory) {
  [void](Assert-DshPath $Directory $true)
  # Do not follow junctions while removing our own installation.
  $pending = New-Object 'System.Collections.Generic.Stack[string]'
  $pending.Push($Directory)
  while ($pending.Count) {
    foreach ($entry in Get-ChildItem -LiteralPath ($pending.Pop()) -Force) {
      if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to delete a linked DSH installation.' }
      if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
    }
  }
}
function Remove-DshDirectory([string]$Directory) {
  Assert-DshTree $Directory
  Remove-Item -LiteralPath $Directory -Recurse -Force
}
function Remove-DshManagedHost {
  # Complete all receipt, metadata and descendant-link checks before deleting a shim.
  $owned = @(Get-ChildItem -LiteralPath $installs -Force)
  foreach ($entry in $owned) {
    if (-not $entry.PSIsContainer) { throw 'Unexpected file in managed DSH installations.' }
    [void](Read-DshReceipt $entry.Name)
    Assert-DshTree $entry.FullName
  }
  if (Test-Path -LiteralPath $profileFile) { [void](Assert-DshPath $profileFile $false) }
  if ($current) { Remove-Item -LiteralPath $shim -Force }
  if ($previous) { Remove-Item -LiteralPath $backup -Force }
  foreach ($entry in $owned) { Remove-DshDirectory $entry.FullName }
  if (Test-Path -LiteralPath $profileFile) { Remove-Item -LiteralPath $profileFile -Force }
  Write-Host 'Managed DSH runtime removed. DSH_HOME, profiles, provider packages, pnpm, Python and the shared .local/bin PATH entry were retained.'
}
function Set-DshUserPath {
  $old = [Environment]::GetEnvironmentVariable('Path','User')
  $entries = @($old -split ';' | Where-Object {
    $_ -and [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ine $bin
  })
  $next = (@($bin) + $entries) -join ';'
  [Environment]::SetEnvironmentVariable('Path',$next,'User')
  $env:PATH = $bin + ';' + $env:PATH
  return [pscustomobject]@{ before=$old; after=$next }
}
function Assert-DshCommandOwnership {
  foreach ($name in @('dsh.cmd','dsh.exe','dsh.ps1')) {
    foreach ($command in @(Get-Command $name -CommandType Application,ExternalScript -All -ErrorAction SilentlyContinue)) {
      if ([IO.Path]::GetFullPath($command.Source) -ine $shim) {
        throw "A different DSH command is on PATH: $($command.Source). Remove or move that installation from PATH yourself; its files and profiles have not been changed."
      }
    }
  }
}
function Get-DshProfileKey([string]$Path) {
  $hash = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).TrimEnd('\').ToUpperInvariant())))).Replace('-','').ToLowerInvariant()
  } finally { $hash.Dispose() }
}

$architecture = $env:PROCESSOR_ARCHITEW6432
if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
$wheel = $env:OS -eq 'Windows_NT' -and $architecture -eq 'AMD64'
if (-not $wheel -and ($Action -ne 'install' -or $UseExistingProfile)) {
  throw 'Managed wheel actions are available only on Windows x64. Other architectures retain the original npm installer.'
}
if (-not $wheel) {
  npm.cmd install -g @deepseek-ai/dsh@latest pnpm@latest
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
}
$dshRoot = $env:DSH_HOME
if ([string]::IsNullOrWhiteSpace($dshRoot)) { $dshRoot = Join-Path $HOME '.dsh' }
elseif ($dshRoot -match '^~([\\/]|$)') { $dshRoot = Join-Path $HOME $dshRoot.Substring(1).TrimStart('/','\') }
$dshRoot = [IO.Path]::GetFullPath($dshRoot)
$lock = $null
$launcher = 'dsh.cmd'
$activated = $false
$newRuntime = $false
$oldDshHome = $env:DSH_HOME
$oldProcessPath = $env:PATH
$pathChange = $null
try {
  if ($wheel) {
    $wheelVersion = '0.2.2rc2'
    $wheelHash = 'a791af95a97be205a73354c6819e95b5fe2ff40a57ef8a78d53c188ee33e9aea'
    $wheelName = 'deepseek_harness_runtime_bin-0.2.2rc2-py3-none-win_amd64.whl'
    $wheelUrl = 'https://files.pythonhosted.org/packages/4e/87/cc1080f32f3835637d93d265ff94d2b24a1ec6b96780894a7e7eeb0a0b5a/deepseek_harness_runtime_bin-0.2.2rc2-py3-none-win_amd64.whl'
    $payload = @(
      @{path='runtime\deepseek-harness-sdk-runtime-win-x64.exe'; bytes=147907584; sha256='a3a56fad32059c85e520d892821e50ce5fe4ebcc88eac2c48839f4207efc8e39'},
      @{path='runtime\deepseek-harness-sdk-runtime-win-x64-rg.exe'; bytes=5429760; sha256='f9dde63498b3193f098355dbec97af99dc4f6b8fa0df5ed04114a03012c042cb'},
      @{path='runtime\win-x64\downloads.json'; bytes=6630; sha256='c683efdf7ebe13946d58c9139f900f39a9c384f0465371fd33dddb01894ece23'}
    )
    $managedPath = Join-Path $HOME '.local\share\lmm-dsh'
    # Validate before creating the runtime root, profile cache, lock or metadata.
    Assert-DshDataSeparation $dshRoot $managedPath
    $managed = New-DshDirectory $managedPath
    $installs = New-DshDirectory (Join-Path $managed 'installs')
    $bin = New-DshDirectory (Join-Path $HOME '.local\bin')
    $shim = Join-Path $bin 'dsh.cmd'
    $backup = Join-Path $managed 'previous.cmd'
    $profileFile = Join-Path $managed 'profile-roots.json'
    $lockPath = Join-Path $managed '.lock'
    if (Test-Path -LiteralPath $lockPath) { [void](Assert-DshPath $lockPath $false) }
    try { $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw 'Another managed DSH operation is active, or its lock cannot be opened.' }
    $current = Read-DshShim $shim
    $previous = Read-DshShim $backup
    if ($current) { [void](Read-DshReceipt $current) }
    if ($previous) { [void](Read-DshReceipt $previous) }
    if ($Action -eq 'rollback') {
      if (-not $current -or -not $previous -or $current -eq $previous) { throw 'No distinct managed DSH rollback target is available.' }
      [void](Assert-DshRuntime $previous)
      $before = [IO.File]::ReadAllText($shim)
      Write-DshAtomic $shim ([IO.File]::ReadAllText($backup))
      try { Write-DshAtomic $backup $before } catch { Write-DshAtomic $shim $before; throw }
      Write-Host 'Managed DSH command rolled back. Profiles and provider packages were not changed.'
      exit 0
    }
    if ($Action -eq 'uninstall') {
      Remove-DshManagedHost
      exit 0
    }
    Assert-DshCommandOwnership
    $profileKeys = @()
    if (Test-Path -LiteralPath $profileFile) {
      [void](Assert-DshPath $profileFile $false)
      $profileKeys = @([IO.File]::ReadAllText($profileFile) | ConvertFrom-Json)
      if (@($profileKeys | Where-Object { $_ -notmatch '^[0-9a-f]{64}$' }).Count) { throw 'Invalid managed DSH profile metadata.' }
    }
    $profileKey = Get-DshProfileKey $dshRoot
    if ((Test-Path -LiteralPath $dshRoot) -and @(Get-ChildItem -LiteralPath $dshRoot -Force).Count -and
        $profileKeys -notcontains $profileKey -and -not $UseExistingProfile) {
      throw 'This DSH_HOME already has data from an unrecognized installation. Back it up and choose a new DSH_HOME, or explicitly pass -UseExistingProfile. No profile migration is performed.'
    }
    $env:DSH_HOME = $dshRoot
    $id = $wheelVersion + '-' + $wheelHash.Substring(0,16)
    $newRuntime = -not (Test-Path -LiteralPath (Join-Path $installs $id))
    $launcher = New-DshRuntime $id
    npm.cmd install -g pnpm@latest
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    $version = @(& $launcher --version)
    if ($LASTEXITCODE -or ($version -join '').Trim() -cne '0.2.2-rc.2') { throw 'Installed DSH host version check failed.' }
  }

  # Recheck after runtime creation, before the first profile write: a previously
  # missing path may now have a real Windows directory identity.
  if ($wheel) { Assert-DshDataSeparation $dshRoot $managedPath }
  $cache = Join-Path $dshRoot 'lmm-provider-packages'
  New-Item -ItemType Directory -Path $cache -Force | Out-Null
  $info = Get-Item -LiteralPath $cache -Force
  if (-not $info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe DSH cache' }
  $cache = $info.FullName
  $expected = '21bc853b321906550cf529cecc83719e6d14fd70041cc7cb92e4aecd6316d3f1'
  $plugin = Join-Path $cache ($expected + '.tgz')
  $work = Join-Path $cache ('.download-' + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $work | Out-Null
  try {
    $download = Join-Path $work 'plugin.tgz'
    Invoke-WebRequest -UseBasicParsing 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/v0.1.0-alpha.9/dsh-lmm-provider.tgz' -OutFile $download
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expected) { throw 'DSH checksum mismatch.' }
    if (-not (Test-Path -LiteralPath $plugin)) { [IO.File]::Move($download, $plugin) }
    $info = Get-Item -LiteralPath $plugin -Force
    if ($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $plugin -Algorithm SHA256).Hash -ne $expected) { throw 'DSH checksum mismatch.' }
    & $launcher plugin --profile $Profile add $plugin --ignore-scripts
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
  } finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  }

  if ($wheel) {
    $before = if ($current) { [IO.File]::ReadAllText($shim) } else { $null }
    $oldBackup = if ($previous) { [IO.File]::ReadAllText($backup) } else { $null }
    $oldProfiles = if (Test-Path -LiteralPath $profileFile) { [IO.File]::ReadAllText($profileFile) } else { $null }
    try {
      if ($current -and $current -ne $id) { Write-DshAtomic $backup $before }
      Write-DshAtomic $shim (Get-DshShim $id)
      Write-DshAtomic $profileFile (ConvertTo-Json -InputObject @($profileKeys + $profileKey | Select-Object -Unique))
      $pathChange = Set-DshUserPath
      if ((Get-Command dsh.cmd -CommandType Application).Source -ine $shim) { throw 'The managed dsh.cmd is not the selected command.' }
      $activated = $true
    } catch {
      if ($before) { Write-DshAtomic $shim $before }
      elseif (Test-Path -LiteralPath $shim) { Remove-Item -LiteralPath $shim -Force }
      if ($oldBackup) { Write-DshAtomic $backup $oldBackup }
      elseif (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
      if ($oldProfiles) { Write-DshAtomic $profileFile $oldProfiles }
      elseif (Test-Path -LiteralPath $profileFile) { Remove-Item -LiteralPath $profileFile -Force }
      if ($pathChange -and [Environment]::GetEnvironmentVariable('Path','User') -ceq $pathChange.after) {
        [Environment]::SetEnvironmentVariable('Path',$pathChange.before,'User')
      }
      throw
    }
    Write-Host "Managed DSH installed at $shim. Start a new terminal; existing parent processes must prepend $bin to PATH."
  }
} finally {
  $env:DSH_HOME = $oldDshHome
  if (-not $activated) { $env:PATH = $oldProcessPath }
  try {
    if ($wheel -and $newRuntime -and -not $activated -and (Test-Path -LiteralPath (Join-Path $installs $id))) {
      Remove-DshDirectory (Join-Path $installs $id)
    }
  } finally { if ($lock) { $lock.Dispose() } }
}
