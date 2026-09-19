# LMM scripts

Self-contained Pi and DSH installers for the public LMM scripts page. The
published `.sh` and `.ps1` files are generated from `templates/`; they do not
fetch another unversioned installer and do not need this repository beside them.

- `pi.sh` / `pi.ps1`: ensure a compatible Node/npm and Pi installation, then
  install the published LMM Pi provider `0.1.0-alpha.1` from npm. Git is not required.
- `dsh.sh` / `dsh.ps1`: ensure Node/npm and DSH are usable, then start DSH Web.
  These scripts do **not** claim to install the separate, currently unpublished
  DSH LMM provider package.

## Supported environments

- Linux and macOS, x64 or arm64, with Bash and normal file/archive utilities.
- Windows x64 or arm64, Windows PowerShell 5.1+ or PowerShell 7, including the
  standard `Get-FileHash` and `Expand-Archive` commands.
- Node 22.19+ in the 22.x line, or Node 24+. Missing/incompatible Node/npm can be
  bootstrapped as a private Node 24.21.0 installation. Official archives are
  checked against SHA-256 values pinned in the reviewed script.
- Linux official Node binaries require a compatible glibc system. On Alpine,
  install distribution-compatible Node/npm first. Unsupported CPUs/OS versions
  stop with a useful error instead of attempting the wrong binary.

No `sudo`, administrator access, global npm installation, shell-profile edits,
or PowerShell execution-policy changes are performed. Windows uses a managed
side-by-side client. POSIX reuses an existing working client, otherwise it uses
a managed client. The tested managed versions are Pi 0.85.1 and DSH 0.1.5-rc.1.

## Run

Download the complete script before running it. Do not execute a failed or
partially downloaded file:

```sh
curl --fail --location --show-error --retry 3 --connect-timeout 20 \
  --max-time 120 https://api.lmm.best/scripts/pi.sh -o pi.sh && bash pi.sh
```

```powershell
$ErrorActionPreference = 'Stop'
Invoke-WebRequest https://api.lmm.best/scripts/pi.ps1 -OutFile pi.ps1
.\pi.ps1
```

Use `dsh.sh` / `dsh.ps1` for DSH. POSIX scripts also defer execution until the
whole function and final invocation block have arrived, so a truncated pipe does
not begin a partial install. Downloading first still provides a clearer failure.

Options:

| Bash | PowerShell | Behavior |
| --- | --- | --- |
| `--check` | `-Check` | Inspect requirements without downloading/installing |
| `--install-only` | `-InstallOnly` | Install DSH without starting the Web server |
| `--no-bootstrap` | `-NoBootstrap` | Refuse automatic dependency/client installation |
| `--help` | `Get-Help .\pi.ps1` | Usage |

After installation, use the printed launcher path. For Pi, run `/login`, choose
LMM, then `/model`. Installing a package is not evidence of working OAuth,
model calls, streaming, or billing; those require a real account and acceptance.

## Slow and unreliable networks

Downloads show received bytes, rate and progress. POSIX uses curl's transfer
meter; Windows computes progress and KiB/s while streaming to disk. Downloads
resume from `.part` files, fall back to a fresh transfer when the server rejects
ranges, and verify the complete archive before extraction. A corrupted download
is never installed. A verified cached archive works offline.

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `LMM_RETRIES` | `3` | Maximum download attempts / npm fetch retries (max 10) |
| `LMM_CONNECT_TIMEOUT` | `20` | Connection timeout in seconds |
| `LMM_STALL_TIMEOUT` | `120` | Stalled-read window; curl threshold is 128 bytes/s |
| `LMM_DOWNLOAD_TIMEOUT` | `1800` | Total download time per attempt |
| `LMM_COMMAND_TIMEOUT` | `1800` | Bound an npm/client installation command |
| `LMM_INSTALL_ROOT` | user data directory | Private runtimes, clients and launchers |
| `LMM_CACHE_ROOT` | user cache directory | Verified/partial Node archives |
| `LMM_NODE_BASE_URL` | `https://nodejs.org/dist` | Explicit HTTPS mirror; pinned hashes still apply |
| `LMM_NPM_REGISTRY` | npm configuration | Explicit HTTPS registry, without embedded credentials |

For a very slow link, raise the total time limit rather than disabling TLS or
checksum checks. The retry budget is bounded; exhausted retries return failure
and retain safe partial data for the next run. npm uses exponential backoff and
its integrity-checked cache. Long-running installation commands print elapsed
heartbeats instead of appearing frozen.

`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, npm proxy/CA configuration and Windows
system proxy settings are respected. Windows' built-in HTTP downloader needs an
HTTP(S) proxy; use an HTTP adapter for a SOCKS proxy. Proxy credentials are not
printed by the installer. No mirror, proxy, or certificate bypass is silently
selected. POSIX requires curl, or wget plus `timeout`; if neither is available,
the script names the missing prerequisite and stops before changing the runtime.

## Repeating or recovering an installation

Client installations are built in a private staging directory and checked before
promotion. Failure does not replace a working installation. Each prefix has an
installation lock; concurrent installers cannot overwrite each other. A POSIX
lock left by a forcibly killed process must be inspected before removal; the
script never assumes a PID or lock is safe to delete.

Existing incomplete version directories are not silently overwritten. Inspect
and remove only the reported incomplete directory, then rerun. Partial downloads
and npm's cache can be reused. No credentials, API keys or private machine state
belong in this repository.

## Development and evidence

```sh
python3 generate.py
shellcheck pi.sh dsh.sh
python3 -m unittest discover -s tests -v
```

On Windows: `./tests/test_installers.ps1`. CI runs Ubuntu, macOS and Windows,
covering parser compatibility, missing dependencies, interrupted transfers,
resume fallback, offline cache, bad checksums, HTTPS enforcement, paths with
spaces, bounded failures, concurrent installers and truncated shell input.
These fixtures are not a substitute for a real user's full client login/session.

Node pins originate from the [official checksums](https://nodejs.org/dist/v24.21.0/SHASUMS256.txt).
Client distribution instructions come from [Pi](https://pi.dev/news/2026/5/7/pi-has-a-new-home)
and [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).
