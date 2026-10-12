# Magpie

Install or update [yetone/magpie](https://github.com/yetone/magpie).
The desktop menu entry is **24**; the Termux entry is **7**. Existing entries keep their numbers.

```sh
bash magpie.sh
bash magpie.sh update
MAGPIE_CLI=1 bash magpie.sh              # Terminal build on Linux
MAGPIE_BIN_DIR="$HOME/bin" bash magpie.sh
```

```powershell
.\magpie.ps1
.\magpie.ps1 update
.\magpie.ps1 -Cli
.\magpie.ps1 -BinDir "$HOME\bin"
```

Both files work independently. Use `help` for local usage without a download.

## Platforms

| Platform | Installation |
| --- | --- |
| macOS Intel / Apple silicon | Official installer: signed app in `/Applications` or `~/Applications`, with a command link. |
| Linux x64 / ARM64 | Official installer: desktop build when WebKitGTK 4.1 is available, otherwise terminal build. `MAGPIE_CLI=1` requests the terminal build. |
| Termux | Official installer: Android-native terminal build in `$PREFIX/bin`. The inspected release provides ARM64; other architectures stop if no matching asset exists. No Linux binary or proot fallback. |
| Windows x64 / ARM64 | Exact matching executable from the latest stable GitHub release, installed as `magpie.exe` in `~/.local/bin`. `-Cli` or a nonempty `MAGPIE_CLI` selects the terminal build. |

On Unix, upstream selects the package, checks its hash and reports missing platform dependencies. No Node.js, Go, Homebrew or system package manager is required by this wrapper. Linux GUI and Windows GUI dependencies still follow upstream requirements. This does not promise compatibility with every Linux distribution or old OS release.

`MAGPIE_BIN_DIR` changes the command directory on both entry points. Windows also accepts `-BinDir`. The wrapper does not change persistent PATH settings. Run the printed full path or add that directory to PATH yourself.

The Unix entry finishes downloading `https://usemagpie.ai/install.sh` before it executes the response and forwards arguments unchanged. Upstream options such as `--proxy` and `--mirror` remain upstream options, not an LMM proxy framework. Environment proxy settings must also allow the initial installer download. The script requires Bash and curl; the upstream installer handles its other dependencies.

Windows uses the exact asset name, release tag, repository URL and GitHub's SHA-256 digest. Missing, ambiguous or invalid metadata stops installation. A failed download or hash check does not replace an existing executable. A successful update stages the new binary on the same volume and uses an atomic file replacement. Close Magpie before an update if Windows reports that the executable is in use; the installer does not kill running applications.

Installation does not launch Magpie, sign in, save API keys or overwrite provider settings. Configure providers in Magpie after installation. Magpie's own account discovery and privacy settings apply when you run it; see its [README](https://github.com/yetone/magpie#quick-start).

## Menu downloads

Both menus prefer adjacent local scripts. Without them, all tools use one immutable `lmm-scripts` commit, including the latest merged Codewhale fix at the time this change was made. `LMM_SCRIPTS_REV` remains an explicit override for testing another revision. The pin applies to the wrapper scripts; upstream software installers still select their current releases.

## Checks

```sh
python3 test-magpie.py
```

```powershell
.\test-magpie.ps1
```

The tests use temporary directories and fake downloads. They cover argument and environment forwarding, interrupted downloads, exit status, menu numbering, local and downloaded menus, Windows architecture selection, SHA-256 validation and preservation of an old installation. They do not install or launch the real application. CI runs these checks on Linux, macOS and Windows, including Windows PowerShell 5.1. A passing fixture test is not a real-device GUI test.

Upstream inspected: the [official Unix installer](https://github.com/yetone/magpie/blob/main/site/public/install.sh) and [v0.1.1215 assets](https://github.com/yetone/magpie/releases/tag/v0.1.1215), published on 2026-10-12. Release selection is dynamic, not pinned to that software version.
