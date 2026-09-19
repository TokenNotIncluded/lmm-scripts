# LMM scripts

Cross-platform setup scripts for the LMM tools.

Scripts are intended for interactive use. They install into the current user's
Node environment and do not use `sudo` or administrator privileges by default.
Review a script before running it.

## Linux / macOS

```sh
bash install-pi.sh
bash install-dsh.sh
bash install-ai-tools.sh
```

## Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-pi.ps1
.\install-dsh.ps1
.\install-ai-tools.ps1
```

Set `LMM_PI_PLUGIN` or `LMM_DSH_PLUGIN` to a package name to install an
optional plugin after the provider itself.
