# Troubleshooting

## I just want the easiest install

Use the root double-click launcher:

```text
Install.bat
```

The `.bat` files are intentionally thin launchers. They are easier for Windows
users to double-click, while the actual install, process checks, shortcuts,
settings server, and uninstall safety checks stay in PowerShell where they are
more reliable.

## The ring does not appear

1. Open Codex Desktop, or let the helper auto-start it.
2. Open `/pet`.
3. Run:

   ```powershell
   .\bin\powershell\Status.ps1
   .\bin\powershell\Diagnose.ps1
   ```

4. Confirm `PetOverlayOpen` is `True`.

If `/pet` is closed, the app hides the ring.

## Codex Desktop did not auto-start

Run diagnostics:

```powershell
.\bin\powershell\Diagnose.ps1
```

Confirm `CodexDesktopFound` is `True` in status output. The helper searches a
running `Codex.exe`, the `OpenAI.Codex` AppX package, the Start Menu AppID, and
matching `WindowsApps` folders. If your PC uses a nonstandard install, provide
one of these at install or start time:

```powershell
.\bin\powershell\Install.ps1 -CodexAppPath "C:\Program Files\WindowsApps\OpenAI.Codex_...\app\Codex.exe"
.\bin\powershell\Install.ps1 -CodexAppId "OpenAI.Codex_2p2nqsd0c76g0!App"
```

Use `-NoStartCodex` only when you want to start Codex Desktop manually.

## The ring appears but usage is blank

Run:

```powershell
.\bin\powershell\Diagnose.ps1 -TestLiveUsage
```

If live usage fails, check:

- Codex Desktop is signed in.
- `%USERPROFILE%\.codex\auth.json` exists.
- Your network can reach `https://chatgpt.com`.

You can still run without live usage:

```powershell
.\bin\powershell\Start.ps1 -NoLiveUsage
```

## The ring is in front of the pet message

Restart the app:

```powershell
.\bin\powershell\Stop.ps1
.\bin\powershell\Start.ps1
```

The app periodically places the ring behind the Codex avatar overlay. If Codex
changes its window behavior, this may need an update.

## The ring follows the wrong place

Close and reopen `/pet`, then run:

```powershell
.\bin\powershell\Diagnose.ps1
```

The app follows the coordinates saved by Codex Desktop in
`.codex-global-state.json`.

## Startup registration did not work

Run the installer again:

```text
Install.bat
```

Or from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\powershell\Install.ps1
```

Then check:

```powershell
.\bin\powershell\Status.ps1
```

The Startup shortcut should exist at:

```text
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Codex Pet Limit Rings.lnk
```

## CMD or Bash wrapper fails

Use the wrapper for your terminal:

```bat
bin\cmd\install.cmd
bin\cmd\status.cmd
```

```sh
sh ./bin/bash/install.sh
sh ./bin/bash/status.sh
```

The Bash wrappers are intended for Windows shells such as Git Bash, MSYS,
Cygwin, or WSL with `powershell.exe` available. Native Linux or macOS shells are
not supported because the overlay uses Windows WPF and Win32 APIs.

If `bash` resolves to the legacy Windows `C:\Windows\System32\bash.exe` but no
WSL distribution is installed, install a WSL distribution or use CMD/PowerShell
instead.

## Full uninstall refuses to remove files

`Uninstall.ps1 -RemoveFiles` only removes a directory that contains the install
marker written by the installer. This prevents a mistyped custom `-InstallDir`
from recursively deleting unrelated files.

If you installed an older version before this marker existed, run the installer
once from the updated repository:

```text
Install.bat
```

Then run:

```powershell
.\bin\powershell\Uninstall.ps1 -RemoveFiles
```

Only remove a directory manually after confirming the path is really the
Codex Pet Limit Rings install directory.

## Settings page says forbidden

Open settings through the launcher:

```text
Settings.bat
```

or:

```powershell
.\bin\powershell\Settings.ps1
```

The local settings server now requires a per-session token. Opening
`settings\index.html` directly or reusing an old URL without the token will not
be allowed to read or save settings.

## Logs

Logs are written to:

```text
%LOCALAPPDATA%\CodexPetLimitRingsWin\logs\rings.log
```

Right-click the tray icon and choose `Open Logs`.
