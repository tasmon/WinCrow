# WinCrow

**Scavenge the bloat. Leave only bones.**

WinCrow is a single-file PowerShell tool with a dark-or-light GUI that strips Windows 10 and Windows 11 down to what you actually use. It removes bloated apps, lets you choose what starts with Windows, and flips 43 privacy, performance and interface switches. Every change can be undone from the same window.

![License: MIT](https://img.shields.io/badge/license-MIT-red)
![Platform: Windows 10 | 11](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-black)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-black)

<!-- Add screenshots to docs/ and uncomment:
![WinCrow dark theme](docs/screenshot-dark.png)
![WinCrow light theme](docs/screenshot-light.png)
-->

## Features

- **Debloat** - lists the Store apps on your PC, pre-ticks the junk (Candy Crush, TikTok, Bing apps, Solitaire, Clipchamp, trial software and more) and removes what you pick. Removal is for all users and also stops the apps returning on new accounts.
- **Startup apps** - shows everything that starts with Windows (registry Run keys and Startup folders). Untick to stop, tick to bring it back. Nothing is deleted.
- **Tweaks** - 43 reversible switches in five groups: Privacy, Ads and bloat, Performance, Interface, System. Includes "Disable background apps".
- **Dark and light themes** - one click in the sidebar; your choice is remembered.
- **Safe by design** - protected system apps are never shown, an optional restore point is created before removal, and every action is logged.
- **Installs like a real program** - first launch copies WinCrow to `C:\Program Files\WinCrow` and adds a Start menu shortcut.

## Install

### Option 1: the installer (recommended)

1. Download this repository (**Code > Download ZIP**, or grab a release) and extract the whole folder.
2. Double-click **`WinCrow Installer.cmd`** and accept the administrator prompt.
3. Choose **1) Install or update WinCrow**.

WinCrow opens and is now in your Start menu as **WinCrow**.

### Option 2: run the script directly

Open PowerShell in the extracted folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\WinCrow.ps1
```

On first launch WinCrow installs itself the same way as the installer does.

## Using WinCrow

| Page | What to do |
| --- | --- |
| **Debloat** | Tick the apps to remove (recommended ones are pre-ticked), keep *Create a restore point first* on, press **Remove selected**. |
| **Startup apps** | Untick anything you do not want at sign-in, press **Apply changes**. Takes effect at the next sign-in. |
| **Tweaks** | Tick a tweak to apply it, untick to restore the Windows default, press **Apply changes**. File Explorer restarts automatically when a tweak needs it. |
| **About** | Version, developer, log folder and **Uninstall WinCrow**. |

The sidebar button at the bottom switches between the dark and light theme.

## The tweaks

**Privacy (13)** - Disable background apps, Reduce telemetry, Turn off advertising ID, Disable activity history, Disable Windows Error Reporting, Opt out of the Customer Experience Program, Stop app-launch tracking, Turn off tailored experiences, Disable feedback prompts, Hide language list from websites, Turn off online speech recognition, Disable location services, Disable Recall (Windows 11).

**Ads and bloat (6)** - Remove tips, suggestions and silent app installs, Block consumer features, No web results in Start search, Disable Widgets / News and Interests, Disable Copilot, Disable Cortana (Windows 10).

**Performance (9)** - Disable Game Bar / Game DVR, Stop Edge startup boost and background mode, Disable Delivery Optimization peer-to-peer, Disable SysMain (Superfetch), Faster shutdown, Faster menu animations, Remove desktop startup delay, Disable Fast Startup, Turn off transparency effects.

**Interface (11)** - Show file extensions, Show hidden files and folders, Open File Explorer to This PC, Hide Recent and Frequent in Quick access, Use dark mode for Windows and apps, Classic right-click menu (Windows 11), Left-align the taskbar (Windows 11), Hide the Chat button (Windows 11), Hide the Task View button, Hide the taskbar search box, Disable the Sticky Keys popup.

**System (4)** - No auto-restart while you are signed in, Keep drivers out of Windows Update, Disable Remote Assistance, Disable OneDrive file sync.

Tweaks that only apply to one Windows version are hidden on the other.

## Safety and undo

- **Tweaks and startup apps** are fully reversible: untick and apply.
- **Removed apps** can be reinstalled from the Microsoft Store.
- WinCrow can create a **System Restore point** before removing apps. If System Protection is off, or a point was made in the last 24 hours, Windows may skip it; WinCrow logs that and carries on.
- Windows, the Store, codecs, the Edge runtime and graphics-driver apps are protected and never listed.
- Read the tick list before pressing a button. *Optional* apps (Phone Link, Mail and Calendar, Xbox, Sticky Notes and similar) are un-ticked on purpose.
- Some tweaks are policy settings. A major Windows feature update can reset them; open WinCrow and re-apply.
- Tweaks that write to your user settings apply to the account running WinCrow. If you elevate with a different admin account, run WinCrow from your own account instead.

## Uninstall

Run **`WinCrow Installer.cmd`** and choose **2**, or open WinCrow > **About** > **Uninstall WinCrow**, or run `.\WinCrow.ps1 -Uninstall`. This removes the program folder and the Start menu shortcut. It does not change your Windows settings. Untick your tweaks first if you want them reverted.

## Requirements

- Windows 10 (1809 or newer) or Windows 11
- Windows PowerShell 5.1, which ships with Windows
- Administrator rights

## Troubleshooting

**Windows says the script is blocked, or SmartScreen warns.** The script is unsigned. Use the installer, which unblocks it, or run `Unblock-File .\WinCrow.ps1` once. Read the script first if you like; it is a single readable file.

**Antivirus flags it.** Tools that edit policies and remove apps can look suspicious to heuristics. The full source is in `WinCrow.ps1`.

**An app fails to remove.** The log panel and `C:\Program Files\WinCrow\Logs` show why. Close the app and press **Rescan**, then try again.

**A tweak looks un-ticked after a restart.** Windows or an update reset it. Re-apply it.

**Logs** are in `C:\Program Files\WinCrow\Logs`. Your theme choice is stored in `settings.json` in the same folder.

## Project layout

```
WinCrow/
  WinCrow.ps1             the whole app (GUI, installer logic, debloat list, tweaks)
  WinCrow Installer.cmd   one-click installer / uninstaller
  README.md
  LICENSE
```

## Contributing

Pull requests are welcome.

- **Add an app to the debloat list:** add a line to `$RuleText` in `WinCrow.ps1` in the form `package-name-pattern|Friendly name|R` (`R` = recommended, `O` = optional). Wildcards (`*`) are allowed.
- **Add a tweak:** add an `Add-Tw` call in the tweak section. Use `Rg` for each registry value and give a restore value (or `$null` to delete the value on restore). Mark version-specific tweaks with `-Only10` or `-Only11`, and add `-Restart` if File Explorer must restart.
- Keep the file **ASCII only** so Windows PowerShell 5.1 reads it correctly, and test on both a Windows 10 and a Windows 11 machine or VM.

## Disclaimer

WinCrow changes system settings and removes software. It is provided as is, without warranty. Create a backup or restore point, review what is ticked, and use it at your own risk.

## License

MIT - see [LICENSE](LICENSE).

## Developer

**Tasmon Islam** - [tasmon@outlook.com](mailto:tasmon@outlook.com)
