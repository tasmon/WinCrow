<#
.SYNOPSIS
    WinCrow - scavenge the bloat. Leave only bones.

.DESCRIPTION
    * Removes bloated Store apps (pick from a list)
    * Enables / disables startup apps (pick from a list)
    * 40+ privacy, performance and interface tweaks, each one reversible
    * Cleaner (temp files, browser and app caches), registry cleaner with backups,
      leftover finder, and an update check against github.com/tasmon/WinCrow
    * Dark and light themes
    * First launch installs itself to "C:\Program Files\WinCrow" and adds a
      Start menu shortcut. After that, launch it from the Start menu.

    Easiest: run "WinCrow Installer.cmd".
    Or:      powershell -ExecutionPolicy Bypass -File .\WinCrow.ps1
    Remove:  Windows Settings -> Apps -> Installed apps -> WinCrow -> Uninstall   (or)   .\WinCrow.ps1 -Uninstall

    Developer: Tasmon Islam <tasmon@outlook.com>
    NOTE: this file is plain ASCII on purpose so Windows PowerShell 5.1 reads it correctly.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$FirstRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$AppName      = 'WinCrow'
$AppVersion   = '1.2.5'
$RepoOwner    = 'tasmon'
$RepoName     = 'WinCrow'
$RepoUrl      = "https://github.com/$RepoOwner/$RepoName"
$DevName      = 'Tasmon Islam'
$DevEmail     = 'tasmon@outlook.com'
$InstallDir   = Join-Path $env:ProgramFiles $AppName
$LogDir       = Join-Path $InstallDir 'Logs'
$IconPath     = Join-Path $InstallDir 'WinCrow.ico'
$SettingsPath = Join-Path $InstallDir 'settings.json'
# registry backups and quarantined folders live outside the program folder so updates and uninstalls never delete them
$DataDir       = Join-Path $env:ProgramData $AppName
$QuarantineDir = Join-Path $DataDir 'Quarantine'
$RegBackupRoot = Join-Path $DataDir 'RegBackups'
$ShortcutPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\WinCrow.lnk'
$PsExe        = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# Any error that stops WinCrow before or after the window opens is written to Logs\crash.log and shown,
# because the app runs with a hidden console and would otherwise just disappear.
trap {
    $m = ('{0}  v{1}  {2}{3}{4}' -f (Get-Date), $AppVersion, ($_ | Out-String), $_.ScriptStackTrace, [Environment]::NewLine)
    foreach ($d in @($LogDir, $env:TEMP)) { try { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }; Add-Content -LiteralPath (Join-Path $d 'WinCrow-crash.log') -Value $m; break } catch { } }
    try { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show(('WinCrow could not start:' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine + $_.InvocationInfo.PositionMessage + [Environment]::NewLine + [Environment]::NewLine + 'Details: ' + $LogDir + '\WinCrow-crash.log'), 'WinCrow', 'OK', 'Error') } catch { }
    exit 1
}

# ------------------------------------------------------------------ elevation
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Must run as admin in Windows PowerShell 5.1 (the Appx module needs it)
$native64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
$wrongBitness = ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and (Test-Path -LiteralPath $native64))
if (-not (Test-Admin) -or $PSVersionTable.PSEdition -eq 'Core' -or $wrongBitness) {
    if (-not $PSCommandPath) { Write-Warning 'Save WinCrow as a .ps1 file and run it from there.'; return }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    if ($Uninstall) { $argList += '-Uninstall' }
    if ($FirstRun)  { $argList += '-FirstRun' }
    $launchExe = $PsExe
    if ($wrongBitness) { $launchExe = $native64 }
    try { Start-Process -FilePath $launchExe -Verb RunAs -ArgumentList $argList } catch { }
    return
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
try {
    Add-Type -Name Dpi -Namespace WinCrow -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    [void][WinCrow.Dpi]::SetProcessDPIAware()
} catch { }
try {
    Add-Type -Name Dwm -Namespace WinCrow -MemberDefinition '[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int val, int size);'
} catch { }
[Windows.Forms.Application]::EnableVisualStyles()

# Display scale: 1.0 at 100%, 1.25 at 125% and so on. Sizes written for 96 DPI are scaled by WinForms,
# but text is measured here so nothing is ever cut off at any scale.
$script:DpiScale = 1.0
try { $gdi = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $script:DpiScale = [double]$gdi.DpiX / 96.0; $gdi.Dispose() } catch { }
if ($script:DpiScale -lt 1.0) { $script:DpiScale = 1.0 }

function Get-TextPx([string]$Text, [Drawing.Font]$Font) {
    $fl = [Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine
    return [Windows.Forms.TextRenderer]::MeasureText($Text, $Font, (New-Object Drawing.Size(0, 0)), $fl)
}

# One type scale for the whole window. Sizes are in points, so Windows scales every one of them
# by the same factor at any display scale (100%, 125%, 150%...) and the text stays consistent.
$FontSpec = @{
    Display = @('Segoe UI Black', 20)
    Title   = @('Segoe UI Semibold', 15)
    Nav     = @('Segoe UI Semibold', 10.5)
    Strong  = @('Segoe UI Semibold', 10)
    Body    = @('Segoe UI', 10)
    Mono    = @('Consolas', 9.5)
}
function Fnt([string]$Kind) {
    $f = $FontSpec[$Kind]
    return (New-Object Drawing.Font($f[0], [single]$f[1]))
}

# ------------------------------------------------------------------ helpers
function Hex([string]$x) { [Drawing.ColorTranslator]::FromHtml($x) }

function Show-Msg([string]$Text, [string]$Icon = 'Information') {
    [void][Windows.Forms.MessageBox]::Show($Text, 'WinCrow', 'OK', $Icon)
}

function Pt([double]$x, [double]$y) { New-Object Drawing.PointF([single]$x, [single]$y) }

# The crow mark: a black crow perched on a branch, with a red eye, on a blood-red disc (100x100 box)
function New-CrowBitmap([int]$Size) {
    $bmp = New-Object Drawing.Bitmap $Size, $Size
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([Drawing.Color]::Transparent)
    $g.ScaleTransform($Size / 100.0, $Size / 100.0)

    # blood-red disc with a dark ring
    $rect = New-Object Drawing.RectangleF 0, 0, 100, 100
    $disc = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (Hex '#E11D2E'), (Hex '#4A060C'), 55.0
    $g.FillEllipse($disc, 1, 1, 97, 97)
    $ringPen = New-Object Drawing.Pen (Hex '#0A0A0C'), 2.2
    $g.DrawEllipse($ringPen, 4, 4, 91, 91)

    # branch
    $branch = New-Object Drawing.Pen (Hex '#0A0A0C'), 3.2
    $branch.StartCap = 'Round'; $branch.EndCap = 'Round'
    $g.DrawLine($branch, 18, 78, 84, 74)

    # crow silhouette facing right: hooked beak, rounded head, folded wing, long tail
    $black = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (Hex '#2A2C33'), (Hex '#030304'), 70.0
    $body = @((Pt 93 39), (Pt 80 30), (Pt 75 24), (Pt 68 20), (Pt 60 22), (Pt 55 29), (Pt 48 34), (Pt 38 40), (Pt 28 52),
              (Pt 18 70), (Pt 12 84), (Pt 22 80), (Pt 26 86), (Pt 33 78), (Pt 40 76), (Pt 52 76), (Pt 62 68), (Pt 68 58),
              (Pt 70 48), (Pt 77 44), (Pt 88 43))
    $g.FillPolygon($black, [Drawing.PointF[]]$body)

    # wing feathers
    $feather = New-Object Drawing.Pen (Hex '#5A5D6A'), 1.3
    $feather.StartCap = 'Round'; $feather.EndCap = 'Round'
    $g.DrawLine($feather, 40, 46, 24, 70); $g.DrawLine($feather, 48, 50, 32, 74); $g.DrawLine($feather, 56, 54, 42, 76)

    # legs
    $leg = New-Object Drawing.Pen (Hex '#0A0A0C'), 3
    $leg.StartCap = 'Round'; $leg.EndCap = 'Round'
    $g.DrawLine($leg, 50, 75, 50, 77); $g.DrawLine($leg, 60, 70, 62, 75)

    # glowing red eye
    $glow = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(90, 255, 40, 40))
    $g.FillEllipse($glow, 63, 23, 9, 9)
    $eye = New-Object Drawing.SolidBrush (Hex '#FF2D2D')
    $g.FillEllipse($eye, 65, 25, 5, 5)

    foreach ($o in @($disc, $ringPen, $branch, $black, $feather, $leg, $glow, $eye)) { $o.Dispose() }
    $g.Dispose()
    return $bmp
}

# Writes a real .ico (PNG-compressed, 256x256) so the Start menu shortcut looks crisp
function Save-CrowIcon([string]$Path) {
    $bmp = New-CrowBitmap 256
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $png = $ms.ToArray()
    $fs = [IO.File]::Create($Path)
    $bw = New-Object IO.BinaryWriter $fs
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$png.Length); $bw.Write([uint32]22)
    $bw.Write($png)
    $bw.Close(); $fs.Close(); $bmp.Dispose(); $ms.Dispose()
}

function New-WinCrowShortcut {
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($ShortcutPath)
    $lnk.TargetPath       = $PsExe
    $lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\WinCrow.ps1`""
    $lnk.WorkingDirectory = $InstallDir
    $lnk.IconLocation     = $IconPath
    $lnk.Description      = 'WinCrow - Windows debloat and tweak toolkit'
    $lnk.WindowStyle      = 7
    $lnk.Save()
    # tick "Run as administrator" on the shortcut so Windows asks for UAC once, up front
    try {
        $b = [IO.File]::ReadAllBytes($ShortcutPath)
        $b[0x15] = $b[0x15] -bor 0x20
        [IO.File]::WriteAllBytes($ShortcutPath, $b)
    } catch { }
}

# Registers WinCrow in Windows "Installed apps" (Settings / Control Panel) so it can be removed from there
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinCrow'
function Register-WinCrow {
    try {
        New-Item -Path $UninstallKey -Force | Out-Null
        $un = "`"$PsExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\WinCrow.ps1`" -Uninstall"
        $kb = 0
        try { $kb = [int]((Get-ChildItem -LiteralPath $InstallDir -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1KB) } catch { }
        $str = @{
            DisplayName = 'WinCrow'; DisplayVersion = $AppVersion; Publisher = $DevName
            InstallLocation = $InstallDir; DisplayIcon = $IconPath; UninstallString = $un
            URLInfoAbout = $RepoUrl; HelpLink = $RepoUrl; InstallDate = (Get-Date).ToString('yyyyMMdd')
        }
        foreach ($n in $str.Keys) { New-ItemProperty -Path $UninstallKey -Name $n -Value $str[$n] -PropertyType String -Force | Out-Null }
        New-ItemProperty -Path $UninstallKey -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $UninstallKey -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $UninstallKey -Name EstimatedSize -Value $kb -PropertyType DWord -Force | Out-Null
    } catch { }
}

function Install-WinCrow {
    New-Item -ItemType Directory -Path $InstallDir, $LogDir -Force | Out-Null
    $dest = Join-Path $InstallDir 'WinCrow.ps1'
    if ($PSCommandPath -and ($PSCommandPath -ine $dest)) { Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force }
    Save-CrowIcon $IconPath
    New-WinCrowShortcut
    Register-WinCrow
}

function Invoke-Uninstall {
    Remove-Item -LiteralPath $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ShortcutPath -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $InstallDir) {
        # the running script lives in that folder, so delete it a moment after we exit
        Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -WindowStyle Hidden `
            -ArgumentList "/c ping 127.0.0.1 -n 4 >nul & rmdir /s /q `"$InstallDir`""
    }
}

# ------------------------------------------------------------------ uninstall / first-run install
if ($Uninstall) {
    Invoke-Uninstall
    Show-Msg 'WinCrow was removed from this PC. Your Windows settings were not changed.'
    return
}

$runningFrom = ''
if ($PSCommandPath) { $runningFrom = [IO.Path]::GetDirectoryName($PSCommandPath) }

if ($runningFrom -ine $InstallDir) {
    if (-not $PSCommandPath) { Show-Msg 'Please save WinCrow as WinCrow.ps1 and run that file.' 'Warning'; return }
    try {
        Install-WinCrow
        Start-Process -FilePath $PsExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$InstallDir\WinCrow.ps1`"", '-FirstRun')
        return
    } catch {
        Show-Msg ("Could not install WinCrow:`n`n" + $_.Exception.Message + "`n`nRunning from the current location instead.") 'Warning'
    }
} else {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $ShortcutPath) -or -not (Test-Path -LiteralPath $IconPath)) {
        try { Save-CrowIcon $IconPath; New-WinCrowShortcut } catch { }
    }
    Register-WinCrow
}
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# ------------------------------------------------------------------ system info
$Build     = [Environment]::OSVersion.Version.Build
$IsWin11   = ($Build -ge 22000)
try { $OsCaption = (Get-CimInstance Win32_OperatingSystem).Caption } catch { $OsCaption = 'Windows' }

# ------------------------------------------------------------------ themes
$Themes = @{
    Dark = @{
        Bg = (Hex '#08090B'); Panel = (Hex '#0F1115'); Panel2 = (Hex '#181A20'); Hover = (Hex '#22252D'); Line = (Hex '#2B2E37')
        Text = (Hex '#EDEDF0'); Dim = (Hex '#8D909A'); Accent = (Hex '#E11D2E'); Accent2 = (Hex '#FF5B2E')
        Danger = (Hex '#6E0F1A'); DangerHover = (Hex '#9A1424'); LogBg = (Hex '#050506'); LogFg = (Hex '#FF7A59')
    }
    Light = @{
        Bg = (Hex '#F3F3F6'); Panel = (Hex '#FFFFFF'); Panel2 = (Hex '#E8E8EE'); Hover = (Hex '#DADAE3'); Line = (Hex '#CFD0D8')
        Text = (Hex '#14151A'); Dim = (Hex '#5E616B'); Accent = (Hex '#C8101E'); Accent2 = (Hex '#E8452A')
        Danger = (Hex '#1B1C22'); DangerHover = (Hex '#3A3C46'); LogBg = (Hex '#EDEDF2'); LogFg = (Hex '#8A1019')
    }
}

$script:Settings = @{ Theme = 'Dark'; AutoUpdate = $true }
function Load-Settings {
    try {
        $s = Get-Content -LiteralPath $SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($s.Theme -in 'Dark', 'Light') { $script:Settings.Theme = [string]$s.Theme }
        if ($null -ne $s.AutoUpdate) { $script:Settings.AutoUpdate = [bool]$s.AutoUpdate }
    } catch { }
}
function Save-Settings {
    try { ($script:Settings | ConvertTo-Json) | Set-Content -LiteralPath $SettingsPath -Encoding ASCII } catch { }
}
Load-Settings

$script:Theme = $script:Settings.Theme
$C = $Themes[$script:Theme]
$script:Roles = @{}        # control -> role, so a theme switch can recolor everything

# ------------------------------------------------------------------ logging
$script:LogBox = $null
$script:Busy   = $false
function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $line = '{0:HH:mm:ss}  {1,-5} {2}' -f (Get-Date), $Level, $Message
    if ($script:LogBox) { $script:LogBox.AppendText($line + "`r`n") }
    try { Add-Content -LiteralPath (Join-Path $LogDir ('wincrow-{0:yyyyMMdd}.log' -f (Get-Date))) -Value $line -ErrorAction Stop } catch { }
    [Windows.Forms.Application]::DoEvents()
}

# ====================================================================== DEBLOAT DATA
# pattern | friendly name | tier   (R = recommended to remove, O = optional)
$RuleText = @'
Microsoft.549981C3F5F10|Cortana (legacy app)|R
Microsoft.Bing*|Bing apps (News, Weather, Finance, Sports)|R
Microsoft.3DBuilder|3D Builder|R
Microsoft.Microsoft3DViewer|3D Viewer|R
Microsoft.Print3D|Print 3D|R
Microsoft.MixedReality.Portal|Mixed Reality Portal|R
Microsoft.GetHelp|Get Help|R
Microsoft.Getstarted|Tips / Get Started|R
Microsoft.MicrosoftOfficeHub|Microsoft 365 (Office) hub|R
Microsoft.MicrosoftSolitaireCollection|Solitaire Collection|R
Microsoft.People|People|R
Microsoft.SkypeApp|Skype|R
Microsoft.Wallet|Microsoft Pay / Wallet|R
Microsoft.WindowsFeedbackHub|Feedback Hub|R
Microsoft.WindowsMaps|Maps|R
Microsoft.ZuneVideo|Movies and TV|R
Microsoft.Messaging|Messaging|R
Microsoft.OneConnect|Mobile Plans|R
Microsoft.NetworkSpeedTest|Network Speed Test|R
Microsoft.Office.Sway|Sway|R
Microsoft.Windows.DevHome|Dev Home|R
Microsoft.PowerAutomateDesktop|Power Automate|R
Microsoft.Copilot|Copilot|R
MicrosoftTeams|Microsoft Teams (personal)|R
MSTeams|Microsoft Teams (personal)|R
Clipchamp.Clipchamp|Clipchamp|R
king.com.*|King games (Candy Crush and co.)|R
*CandyCrush*|Candy Crush|R
*FarmVille*|FarmVille|R
*BubbleWitch*|Bubble Witch|R
*MarchofEmpires*|March of Empires|R
*Roblox*|Roblox|R
*Disney*|Disney+|R
*SpotifyMusic*|Spotify|R
*Netflix*|Netflix|R
*TikTok*|TikTok|R
*Facebook*|Facebook|R
*Instagram*|Instagram|R
*Twitter*|Twitter / X|R
*LinkedIn*|LinkedIn|R
*AmazonVideo*|Prime Video|R
*Hulu*|Hulu|R
*PicsArt*|PicsArt|R
*Pinterest*|Pinterest|R
*Duolingo*|Duolingo|R
*AdobeCreativeCloudExpress*|Adobe Express|R
*McAfee*|McAfee trial|R
*Norton*|Norton trial|R
*WinZip*|WinZip trial|R
*HiddenCity*|Hidden City|R
*EclipseManager*|Eclipse Manager|R
*ActiproSoftware*|Actipro|R
Microsoft.YourPhone|Phone Link|O
Microsoft.WindowsCommunicationsApps|Mail and Calendar|O
Microsoft.OutlookForWindows|Outlook (new)|O
Microsoft.Todos|Microsoft To Do|O
Microsoft.Office.OneNote|OneNote|O
Microsoft.ZuneMusic|Groove Music / Media Player|O
Microsoft.Xbox*|Xbox components|O
Microsoft.GamingApp|Xbox app|O
MicrosoftCorporationII.MicrosoftFamily|Microsoft Family|O
MicrosoftCorporationII.QuickAssist|Quick Assist|O
Microsoft.RemoteDesktop|Remote Desktop (Store)|O
Microsoft.MicrosoftStickyNotes|Sticky Notes|O
Microsoft.WindowsAlarms|Alarms and Clock|O
'@
$Rules = foreach ($l in ($RuleText -split "`r?`n")) {
    if ($l.Trim()) { $p = $l.Split('|'); [pscustomobject]@{ P = $p[0]; L = $p[1]; T = $p[2] } }
}

# Things Windows or the Store itself needs - never shown, never removed
$ProtectRegex = '^(Microsoft\.(WindowsStore|StorePurchaseApp|DesktopAppInstaller|VCLibs|NET\.|UI\.Xaml|WindowsAppRuntime|SecHealthUI|WindowsTerminal|HEVCVideoExtension|HEIFImageExtension|WebpImageExtension|VP9VideoExtensions|WebMediaExtensions|AV1VideoExtension|MicrosoftEdge|LockApp|AAD\.|AccountsControl|AsyncTextService|BioEnrollment|CredDialogHost|ECApp|Win32WebViewHost|Windows\.(?!DevHome))|Windows\.|NVIDIACorp|RealtekSemiconductor|AdvancedMicroDevices|AppUp\.Intel)'

# Readable name for an app that has no rule: drops the publisher id and splits CamelCase
function Get-FriendlyName([string]$Pkg) {
    $parts = @($Pkg -split '\.')
    if ($parts.Count -gt 1 -and ($parts[0] -match '^\d' -or $parts[0] -match '^Microsoft(CorporationII)?$')) { $parts = $parts[1..($parts.Count - 1)] }
    if ($parts.Count -eq 2 -and $parts[0] -eq $parts[1]) { $parts = @($parts[0]) }
    $t = ($parts -join ' ')
    $t = $t -creplace '(?<=[a-z0-9])(?=[A-Z])', ' '
    $t = $t -creplace '(?<=[A-Z])(?=[A-Z][a-z])', ' '
    return $t.Trim()
}

function Get-InstalledApps {
    $pk = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
        -not $_.IsFramework -and -not $_.NonRemovable -and $_.SignatureKind -ne 'System' -and $_.Name -notmatch $ProtectRegex
    }
    $out = foreach ($g in ($pk | Group-Object Name)) {
        $nm = $g.Name
        $rule = $null
        foreach ($r in $Rules) { if ($nm -like $r.P) { $rule = $r; break } }
        [pscustomobject]@{
            Name  = $nm
            Label = $(if ($rule) { $rule.L } else { Get-FriendlyName $nm })
            Tier  = $(if ($rule) { $rule.T } else { 'X' })
            Full  = @($g.Group | ForEach-Object { $_.PackageFullName })
        }
    }
    $out | Sort-Object @{ Expression = { switch ($_.Tier) { 'R' { 0 } 'O' { 1 } default { 2 } } } }, Label
}

# ====================================================================== STARTUP DATA
$ApprovedBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

function Get-StartupState([string]$Key, [string]$Name) {
    try {
        $v = (Get-ItemProperty -Path $Key -Name $Name -ErrorAction Stop).$Name
        return (($v[0] -band 1) -eq 0)
    } catch { return $true }
}

function Set-StartupState([string]$Key, [string]$Name, [bool]$Enable) {
    if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
    $b = New-Object byte[] 12
    if ($Enable) { $b[0] = 2 } else { $b[0] = 3; [BitConverter]::GetBytes((Get-Date).ToFileTime()).CopyTo($b, 4) }
    New-ItemProperty -Path $Key -Name $Name -PropertyType Binary -Value $b -Force | Out-Null
}

function Get-StartupEntries {
    $list = New-Object System.Collections.ArrayList
    $regs = @(
        @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';                 A = "HKCU:\$ApprovedBase\Run";   S = 'Current user' },
        @{ P = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';                 A = "HKLM:\$ApprovedBase\Run";   S = 'All users' },
        @{ P = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';     A = "HKLM:\$ApprovedBase\Run32"; S = 'All users (32-bit)' }
    )
    foreach ($r in $regs) {
        if (-not (Test-Path $r.P)) { continue }
        $k = Get-Item -Path $r.P
        foreach ($n in $k.GetValueNames()) {
            if (-not $n) { continue }
            [void]$list.Add([pscustomobject]@{ Name = $n; Command = [string]$k.GetValue($n); Source = $r.S; Approved = $r.A; Enabled = (Get-StartupState $r.A $n) })
        }
    }
    $folders = @(
        @{ P = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup');      A = "HKCU:\$ApprovedBase\StartupFolder"; S = 'Startup folder (user)' },
        @{ P = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup');  A = "HKLM:\$ApprovedBase\StartupFolder"; S = 'Startup folder (all users)' }
    )
    $ws = New-Object -ComObject WScript.Shell
    foreach ($f in $folders) {
        if (-not (Test-Path -LiteralPath $f.P)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $f.P -File -Force | Where-Object { $_.Name -ne 'desktop.ini' })) {
            $cmd = $file.FullName
            if ($file.Extension -eq '.lnk') { try { $cmd = $ws.CreateShortcut($file.FullName).TargetPath } catch { } }
            [void]$list.Add([pscustomobject]@{ Name = $file.Name; Command = $cmd; Source = $f.S; Approved = $f.A; Enabled = (Get-StartupState $f.A $file.Name) })
        }
    }
    return @($list | Sort-Object Name)
}

# ====================================================================== TWEAK DATA
# Rg  = one registry value: path, name, value-when-tweaked, type, value-to-restore ($null = delete the value)
function Rg($p, $n, $v, $t = 'DWord', $rev = $null) { @{ K = 'Reg'; P = $p; N = $n; V = $v; T = $t; R = $rev } }

$Tweaks = New-Object System.Collections.ArrayList
function Add-Tw([string]$Cat, [string]$Name, [string]$Desc, [object[]]$Entries, [switch]$Only11, [switch]$Only10, [switch]$Restart) {
    [void]$script:Tweaks.Add(@{ Cat = $Cat; Name = $Name; Desc = $Desc; Entries = $Entries
                               Only11 = [bool]$Only11; Only10 = [bool]$Only10; RestartExplorer = [bool]$Restart })
}

$TweakCats = @('Privacy', 'Ads and bloat', 'Performance', 'Interface', 'System')
$ExpAdv  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$ExpRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$Persona = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$WU      = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

# ---- Privacy
Add-Tw 'Privacy' 'Disable background apps' 'Apps stop running in the background when you are not using them' @(
    (Rg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 'DWord' 0),
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2))
Add-Tw 'Privacy' 'Reduce telemetry' 'Minimum diagnostic data and stops the Connected User Experiences (DiagTrack) service' @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0),
    @{ K = 'Svc'; N = 'DiagTrack'; R = 'Automatic' })
Add-Tw 'Privacy' 'Turn off advertising ID' 'Apps can no longer use a personal advertising ID' @(
    (Rg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'DWord' 1))
Add-Tw 'Privacy' 'Disable activity history' 'Stops Windows collecting and uploading your activity timeline' @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0),
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0),
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0))
Add-Tw 'Privacy' 'Disable Windows Error Reporting' 'Stops crash reports being sent to Microsoft' @(
    (Rg 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 'DWord' 0))
Add-Tw 'Privacy' 'Opt out of the Customer Experience Program' 'Turns off the Customer Experience Improvement Program (CEIP)' @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0))
Add-Tw 'Privacy' 'Stop app-launch tracking' 'Windows no longer tracks which apps you open to rank Start suggestions' @(
    (Rg $ExpAdv 'Start_TrackProgs' 0 'DWord' 1))
Add-Tw 'Privacy' 'Turn off tailored experiences' 'No personalised tips and ads based on your diagnostic data' @(
    (Rg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'DWord' 1),
    (Rg 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1))
Add-Tw 'Privacy' 'Disable feedback prompts' 'Windows stops asking you to rate your experience' @(
    (Rg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0))
Add-Tw 'Privacy' 'Hide language list from websites' 'Websites cannot read your language list to personalise content' @(
    (Rg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 'DWord' 0))
Add-Tw 'Privacy' 'Turn off online speech recognition' 'Voice clips are not sent to Microsoft for recognition' @(
    (Rg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0))
Add-Tw 'Privacy' 'Disable location services' 'Policy that blocks Windows and apps from using your location' @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1))
Add-Tw 'Privacy' 'Disable Recall (Windows 11 AI snapshots)' 'Stops Windows saving AI snapshots of your screen activity' -Only11 @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1))

# ---- Ads and bloat
$cdmPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$cdm = @('SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
         'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SubscribedContent-310093Enabled',
         'SystemPaneSuggestionsEnabled', 'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled',
         'OemPreInstalledAppsEnabled', 'SoftLandingEnabled', 'RotatingLockScreenOverlayEnabled') |
       ForEach-Object { Rg $cdmPath $_ 0 'DWord' 1 }
Add-Tw 'Ads and bloat' 'Remove tips, suggestions and silent app installs' 'Stops Start menu / lock screen ads and apps that install themselves' $cdm
Add-Tw 'Ads and bloat' 'Block consumer features' 'Policy that stops Windows pushing sponsored apps to the Start menu' @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1))
Add-Tw 'Ads and bloat' 'No web results in Start search' 'Start search only looks at your PC (no Bing, no search highlights)' @(
    (Rg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0 'DWord' 1),
    (Rg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1),
    (Rg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0 'DWord' 1))
Add-Tw 'Ads and bloat' 'Disable Widgets / News and Interests' 'Removes the taskbar widgets / news feed (Windows 11 and Windows 10)' @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0),
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0))
Add-Tw 'Ads and bloat' 'Disable Copilot' 'Turns off the Windows Copilot sidebar / taskbar button' @(
    (Rg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1),
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1))
Add-Tw 'Ads and bloat' 'Disable Cortana (Windows 10)' 'Policy that turns Cortana off' -Only10 @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0))

# ---- Performance
Add-Tw 'Performance' 'Disable Game Bar / Game DVR capture' 'Stops background game recording and the Game Bar popups' @(
    (Rg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 'DWord' 1),
    (Rg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 'DWord' 1))
Add-Tw 'Performance' 'Stop Edge startup boost and background mode' 'Edge no longer preloads at sign-in or keeps running after you close it' @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0),
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0))
Add-Tw 'Performance' 'Disable Delivery Optimization peer-to-peer' 'Windows Update will not share update downloads with other PCs' @(
    (Rg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' 0 'DWord' 1))
Add-Tw 'Performance' 'Disable SysMain (Superfetch)' 'Stops the prefetch service. Best on SSDs, leave off on old hard drives' @(
    @{ K = 'Svc'; N = 'SysMain'; R = 'Automatic' })
Add-Tw 'Performance' 'Faster shutdown' 'Apps and services are force-closed after 2 seconds instead of 20 / 5' @(
    (Rg 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '2000' 'String' '20000'),
    (Rg 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '1000' 'String' '5000'),
    (Rg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '2000' 'String' '5000'))
Add-Tw 'Performance' 'Faster menu animations' 'Menus open almost instantly (delay 50 ms instead of 400 ms)' @(
    (Rg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '50' 'String' '400'))
Add-Tw 'Performance' 'Remove desktop startup delay' 'Startup apps launch right away instead of waiting a few seconds' @(
    (Rg "$ExpRoot\Serialize" 'StartupDelayInMSec' 0))
Add-Tw 'Performance' 'Disable Fast Startup' 'Full shutdowns again. Fixes odd boot, dual-boot and update issues' @(
    (Rg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 'DWord' 1))
Add-Tw 'Performance' 'Turn off transparency effects' 'Less GPU work, snappier windows on older hardware' @(
    (Rg $Persona 'EnableTransparency' 0 'DWord' 1))

# ---- Interface
Add-Tw 'Interface' 'Show file extensions' 'Always show .exe, .pdf, .docx ... in File Explorer' -Restart @(
    (Rg $ExpAdv 'HideFileExt' 0 'DWord' 1))
Add-Tw 'Interface' 'Show hidden files and folders' 'File Explorer lists hidden items' -Restart @(
    (Rg $ExpAdv 'Hidden' 1 'DWord' 2))
Add-Tw 'Interface' 'Open File Explorer to This PC' 'Explorer starts at This PC instead of Home / Quick access' -Restart @(
    (Rg $ExpAdv 'LaunchTo' 1 'DWord' 2))
Add-Tw 'Interface' 'Hide Recent and Frequent in Quick access' 'Explorer stops listing recently used files and folders' -Restart @(
    (Rg $ExpRoot 'ShowRecent' 0 'DWord' 1),
    (Rg $ExpRoot 'ShowFrequent' 0 'DWord' 1))
Add-Tw 'Interface' 'Use dark mode for Windows and apps' 'Switches the Windows system and app theme to dark' @(
    (Rg $Persona 'AppsUseLightTheme' 0 'DWord' 1),
    (Rg $Persona 'SystemUsesLightTheme' 0 'DWord' 1))
Add-Tw 'Interface' 'Classic right-click menu (Windows 11)' 'Brings back the full context menu without "Show more options"' -Only11 -Restart @(
    @{ K = 'Key'; P = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' })
Add-Tw 'Interface' 'Left-align the taskbar (Windows 11)' 'Start button and icons sit on the left like Windows 10' -Only11 -Restart @(
    (Rg $ExpAdv 'TaskbarAl' 0 'DWord' 1))
Add-Tw 'Interface' 'Hide the Chat button (Windows 11)' 'Removes the Teams chat icon from the taskbar' -Only11 -Restart @(
    (Rg $ExpAdv 'TaskbarMn' 0 'DWord' 1))
Add-Tw 'Interface' 'Hide the Task View button' 'Removes the Task View icon from the taskbar' -Restart @(
    (Rg $ExpAdv 'ShowTaskViewButton' 0 'DWord' 1))
Add-Tw 'Interface' 'Hide the taskbar search box' 'Removes the search box / icon from the taskbar (Start search still works)' -Restart @(
    (Rg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0 'DWord' $(if ($IsWin11) { 1 } else { 2 })))
Add-Tw 'Interface' 'Disable the Sticky Keys popup' 'Pressing Shift five times no longer opens the Sticky Keys prompt' @(
    (Rg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String' '510'))

# ---- System
Add-Tw 'System' 'No auto-restart while you are signed in' 'Windows Update will not reboot the PC while someone is logged on' @(
    (Rg "$WU\AU" 'NoAutoRebootWithLoggedOnUsers' 1))
Add-Tw 'System' 'Keep drivers out of Windows Update' 'Quality updates will not replace your graphics / chipset drivers' @(
    (Rg $WU 'ExcludeWUDriversInQualityUpdate' 1))
Add-Tw 'System' 'Disable Remote Assistance' 'Blocks remote assistance invitations' @(
    (Rg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0 'DWord' 1))
Add-Tw 'System' 'Disable OneDrive file sync' 'Policy that stops OneDrive syncing files (the app itself stays installed)' @(
    (Rg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1))

function Test-Entry($e) {
    switch ($e.K) {
        'Reg' { try { $cur = (Get-ItemProperty -Path $e.P -Name $e.N -ErrorAction Stop).($e.N); return ($cur -eq $e.V) } catch { return $false } }
        'Key' { return (Test-Path -Path $e.P) }
        'Svc' { $s = Get-Service -Name $e.N -ErrorAction SilentlyContinue; return [bool]($s -and $s.StartType -eq 'Disabled') }
    }
}

function Set-Entry($e, [bool]$On) {
    switch ($e.K) {
        'Reg' {
            if ($On) {
                if (-not (Test-Path $e.P)) { New-Item -Path $e.P -Force | Out-Null }
                New-ItemProperty -Path $e.P -Name $e.N -Value $e.V -PropertyType $e.T -Force | Out-Null
            } elseif ($null -eq $e.R) {
                Remove-ItemProperty -Path $e.P -Name $e.N -ErrorAction SilentlyContinue
            } else {
                if (-not (Test-Path $e.P)) { New-Item -Path $e.P -Force | Out-Null }
                New-ItemProperty -Path $e.P -Name $e.N -Value $e.R -PropertyType $e.T -Force | Out-Null
            }
        }
        'Key' {
            if ($On) { New-Item -Path $e.P -Force | Out-Null; Set-ItemProperty -Path $e.P -Name '(default)' -Value '' }
            else { Remove-Item -Path (Split-Path $e.P -Parent) -Recurse -Force -ErrorAction SilentlyContinue }
        }
        'Svc' {
            if ($On) { Stop-Service -Name $e.N -Force -ErrorAction SilentlyContinue; Set-Service -Name $e.N -StartupType Disabled }
            else { Set-Service -Name $e.N -StartupType $e.R; Start-Service -Name $e.N -ErrorAction SilentlyContinue }
        }
    }
}

function Test-Tweak($t) {
    foreach ($e in $t.Entries) { if (-not (Test-Entry $e)) { return $false } }
    return $true
}

# ====================================================================== SHARED HELPERS
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    if ($Bytes -gt 0)   { return ('{0:N0} B' -f $Bytes) }
    return '0 KB'
}

function Wait-ProcUi($Proc) {
    while (-not $Proc.HasExited) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 150 }
    $Proc.WaitForExit()    # caches the exit code (Start-Process -PassThru can otherwise return a null ExitCode)
}

function New-RestorePoint([string]$Desc) {
    try { Checkpoint-Computer -Description $Desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Log 'Restore point created.' }
    catch { Write-Log ('Restore point skipped: ' + $_.Exception.Message) 'WARN' }
}

function Get-NormName([string]$s) { return ($s.ToLower() -replace '[^a-z0-9]', '') }

# ---- registry plumbing (uses the .NET registry API so odd value names are safe)
$UninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
$RunKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)

function Split-RegPath([string]$p) {
    if ($p -match '^(HKLM|HKCU|HKCR|HKU):\\?(.*)$') {
        $hive = $Matches[1]; $sub = $Matches[2]
        $root = $null
        switch ($hive) {
            'HKLM' { $root = [Microsoft.Win32.Registry]::LocalMachine }
            'HKCU' { $root = [Microsoft.Win32.Registry]::CurrentUser }
            'HKCR' { $root = [Microsoft.Win32.Registry]::ClassesRoot }
            'HKU'  { $root = [Microsoft.Win32.Registry]::Users }
        }
        return @{ Root = $root; Sub = $sub }
    }
    return $null
}

function Open-Reg([string]$p, [bool]$Writable = $false) {
    $s = Split-RegPath $p
    if (-not $s) { return $null }
    try { return $s.Root.OpenSubKey($s.Sub, $Writable) } catch { return $null }
}

# True only when the file is missing on a fixed drive that is present. Unplugged drives, network
# paths, wildcards and unresolved variables are never reported as missing.
$script:FixedRoots = $null
function Test-Missing([string]$Path) {
    if (-not $Path) { return $false }
    $p = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if ($p -notmatch '^[A-Za-z]:\\') { return $false }
    if ($p -match '[*?<>|%]') { return $false }
    if (-not $script:FixedRoots) {
        $script:FixedRoots = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.Name.ToUpper() })
    }
    if ($script:FixedRoots -notcontains $p.Substring(0, 3).ToUpper()) { return $false }
    return (-not (Test-Path -LiteralPath $p))
}

# Pulls the program path out of a command line such as: "C:\x\a.exe" /silent   or   C:\x\a.exe -x
function Get-CmdFile([string]$Cmd) {
    if (-not $Cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Cmd.Trim())
    if ($c.StartsWith('"')) {
        $e = $c.IndexOf('"', 1)
        if ($e -gt 1) { $c = $c.Substring(1, $e - 1) } else { return $null }
        if ($c -match '^[A-Za-z]:\\') { return $c }
        return $null
    }
    if ($c -match '^([A-Za-z]:\\.*?\.(exe|dll|msi|bat|cmd|com|ico|cpl|scr|sys))(\s|,|$)') { return $Matches[1] }
    return $null
}

# ====================================================================== CLEANER DATA
$CleanCats = @('Windows', 'Browsers', 'Applications', 'Privacy traces', 'Advanced')
$Cleaners = New-Object System.Collections.ArrayList
function Add-Cl([string]$Cat, [string]$Name, [string]$Desc, [string[]]$Paths, [bool]$On = $true, [string]$Kind = 'Files', [string[]]$Svc = @()) {
    [void]$script:Cleaners.Add(@{ Cat = $Cat; Name = $Name; Desc = $Desc; Paths = $Paths; On = $On; Kind = $Kind; Svc = $Svc; Bytes = $null })
}

$LA = $env:LOCALAPPDATA; $RA = $env:APPDATA; $WIN = $env:SystemRoot; $PD = $env:ProgramData
$ExplorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'

# ---- Windows
Add-Cl 'Windows' 'User temporary files' 'Leftover files in your Temp folder' @("$env:TEMP\*")
Add-Cl 'Windows' 'Windows temporary files' 'Leftover files in C:\Windows\Temp' @("$WIN\Temp\*")
Add-Cl 'Windows' 'Recycle Bin' 'Permanently empties the Recycle Bin on all drives' @() -On $false -Kind 'Recycle'
Add-Cl 'Windows' 'Thumbnail cache' 'Explorer picture previews (rebuilt when needed)' @("$LA\Microsoft\Windows\Explorer\thumbcache_*.db")
Add-Cl 'Windows' 'Internet cache (legacy)' 'INetCache used by Internet Explorer mode and older apps' @("$LA\Microsoft\Windows\INetCache\*")
Add-Cl 'Windows' 'Windows Update download cache' 'Already-installed update packages (SoftwareDistribution\Download)' @("$WIN\SoftwareDistribution\Download\*") -Svc @('wuauserv', 'bits')
Add-Cl 'Windows' 'Delivery Optimization cache' 'Cached update files shared with other PCs' @("$WIN\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*") -Svc @('dosvc')
Add-Cl 'Windows' 'Windows error reports' 'Crash and error reports waiting to be sent or archived' @("$PD\Microsoft\Windows\WER\ReportArchive\*", "$PD\Microsoft\Windows\WER\ReportQueue\*", "$PD\Microsoft\Windows\WER\Temp\*", "$LA\Microsoft\Windows\WER\ReportArchive\*", "$LA\Microsoft\Windows\WER\ReportQueue\*")
Add-Cl 'Windows' 'Memory dump files' 'Minidumps, MEMORY.DMP and kernel reports from past crashes' @("$WIN\Minidump\*", "$WIN\MEMORY.DMP", "$WIN\LiveKernelReports\*.dmp")
Add-Cl 'Windows' 'Windows log files' 'CBS, DISM and Windows Update log files' @("$WIN\Logs\CBS\*.log", "$WIN\Logs\DISM\*.log", "$WIN\Logs\WindowsUpdate\*")
Add-Cl 'Windows' 'App crash dumps' 'Crash dumps written by apps in your profile' @("$LA\CrashDumps\*")
Add-Cl 'Windows' 'DNS cache' 'Flushes the cached name lookups (ipconfig /flushdns)' @() -Kind 'Dns'

# ---- Browsers (cache only: your passwords, history, cookies and bookmarks are never touched)
Add-Cl 'Browsers' 'Google Chrome cache' 'Cached web files, code cache and GPU cache' @("$LA\Google\Chrome\User Data\*\Cache\*", "$LA\Google\Chrome\User Data\*\Code Cache\*", "$LA\Google\Chrome\User Data\*\GPUCache\*", "$LA\Google\Chrome\User Data\ShaderCache\*")
Add-Cl 'Browsers' 'Microsoft Edge cache' 'Cached web files, code cache and GPU cache' @("$LA\Microsoft\Edge\User Data\*\Cache\*", "$LA\Microsoft\Edge\User Data\*\Code Cache\*", "$LA\Microsoft\Edge\User Data\*\GPUCache\*", "$LA\Microsoft\Edge\User Data\ShaderCache\*")
Add-Cl 'Browsers' 'Mozilla Firefox cache' 'Cached web files and startup cache for every profile' @("$LA\Mozilla\Firefox\Profiles\*\cache2\*", "$LA\Mozilla\Firefox\Profiles\*\startupCache\*")
Add-Cl 'Browsers' 'Brave cache' 'Cached web files, code cache and GPU cache' @("$LA\BraveSoftware\Brave-Browser\User Data\*\Cache\*", "$LA\BraveSoftware\Brave-Browser\User Data\*\Code Cache\*", "$LA\BraveSoftware\Brave-Browser\User Data\*\GPUCache\*")
Add-Cl 'Browsers' 'Opera cache' 'Cached web files, code cache and GPU cache' @("$LA\Opera Software\Opera Stable\Cache\*", "$LA\Opera Software\Opera Stable\Code Cache\*", "$LA\Opera Software\Opera Stable\GPUCache\*", "$RA\Opera Software\Opera Stable\Cache\*")
Add-Cl 'Browsers' 'Vivaldi cache' 'Cached web files, code cache and GPU cache' @("$LA\Vivaldi\User Data\*\Cache\*", "$LA\Vivaldi\User Data\*\Code Cache\*", "$LA\Vivaldi\User Data\*\GPUCache\*")

# ---- Applications
Add-Cl 'Applications' 'Discord cache' 'Cached images and code' @("$RA\discord\Cache\*", "$RA\discord\Code Cache\*", "$RA\discord\GPUCache\*")
Add-Cl 'Applications' 'Spotify cache' 'Cached songs and covers (Storage folder)' @("$LA\Spotify\Storage\*")
Add-Cl 'Applications' 'Slack cache' 'Cached images and code' @("$RA\Slack\Cache\*", "$RA\Slack\Code Cache\*", "$RA\Slack\GPUCache\*")
Add-Cl 'Applications' 'Microsoft Teams (classic) cache' 'Cached images, logs and temporary data' @("$RA\Microsoft\Teams\Cache\*", "$RA\Microsoft\Teams\blob_storage\*", "$RA\Microsoft\Teams\GPUCache\*", "$RA\Microsoft\Teams\tmp\*")
Add-Cl 'Applications' 'Visual Studio Code cache' 'Cached data, code cache and GPU cache' @("$RA\Code\Cache\*", "$RA\Code\CachedData\*", "$RA\Code\GPUCache\*")
Add-Cl 'Applications' 'Steam web cache' 'Steam browser cache (not your games)' @("$LA\Steam\htmlcache\*")
Add-Cl 'Applications' 'GPU shader caches' 'NVIDIA, AMD and DirectX shader caches. Games rebuild them, so first launch can stutter' @("$LA\NVIDIA\DXCache\*", "$LA\NVIDIA\GLCache\*", "$LA\AMD\DxCache\*", "$LA\D3DSCache\*") -On $false
Add-Cl 'Applications' 'Developer caches' 'npm, pip and NuGet download caches. Packages download again when needed' @("$RA\npm-cache\*", "$LA\pip\Cache\*", "$LA\NuGet\v3-cache\*") -On $false

# ---- Privacy traces
Add-Cl 'Privacy traces' 'Recent files and jump lists' 'Recent items and taskbar jump lists' @("$RA\Microsoft\Windows\Recent\*.lnk", "$RA\Microsoft\Windows\Recent\AutomaticDestinations\*", "$RA\Microsoft\Windows\Recent\CustomDestinations\*") -On $false
Add-Cl 'Privacy traces' 'Run dialog history' 'The list of commands typed in Win+R' @("$ExplorerKey\RunMRU") -On $false -Kind 'RegClear'
Add-Cl 'Privacy traces' 'Explorer address bar history' 'Paths typed into File Explorer' @("$ExplorerKey\TypedPaths") -On $false -Kind 'RegClear'
Add-Cl 'Privacy traces' 'Explorer search history' 'Searches typed into File Explorer' @("$ExplorerKey\WordWheelQuery") -On $false -Kind 'RegClear'

# ---- Advanced
Add-Cl 'Advanced' 'Prefetch files' 'Windows launch-speed hints. Rebuilt, but apps start a little slower at first' @("$WIN\Prefetch\*.pf") -On $false
Add-Cl 'Advanced' 'Windows event logs' 'Clears every event log except Security. Loses troubleshooting history' @() -On $false -Kind 'EventLogs'
Add-Cl 'Advanced' 'Component store cleanup (WinSxS)' 'Removes superseded Windows components via DISM. Takes several minutes' @() -On $false -Kind 'Dism'

function Test-SafeClean([string]$p) {
    if ($p -notmatch '^[A-Za-z]:\\[^\\]+\\.+') { return $false }
    if ($p -match '^[A-Za-z]:\\Windows\\(System32|SysWOW64|WinSxS)(\\|$)') { return $false }
    return $true
}

function Get-DirBytes([string]$Path) {
    try {
        $m = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        if ($m.Sum) { return [double]$m.Sum }
    } catch { }
    return 0.0
}

function Get-RecycleBytes {
    try {
        $sh = New-Object -ComObject Shell.Application
        $sum = 0.0
        foreach ($i in $sh.Namespace(10).Items()) { $sum += [double]$i.Size }
        return $sum
    } catch { return 0.0 }
}

# Returns the size in bytes, or $null for items that have no meaningful size (DNS, event logs...)
function Get-CleanSize($it) {
    switch ($it.Kind) {
        'Recycle' { return (Get-RecycleBytes) }
        'Files' {
            $total = 0.0
            foreach ($p in $it.Paths) {
                if (-not (Test-SafeClean $p)) { continue }
                foreach ($f in (Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue)) {
                    if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    if ($f.PSIsContainer) { $total += (Get-DirBytes $f.FullName) } else { $total += [double]$f.Length }
                }
            }
            return $total
        }
        default { return $null }
    }
}

function Invoke-CleanItem($it) {
    switch ($it.Kind) {
        'Recycle' { try { Clear-RecycleBin -Force -ErrorAction Stop } catch { } }
        'Dns'     { try { & ipconfig.exe /flushdns | Out-Null } catch { } }
        'EventLogs' {
            foreach ($l in @(& wevtutil.exe el)) {
                if ($l -and $l -ne 'Security') { try { & wevtutil.exe cl $l 2>&1 | Out-Null } catch { } }
                [Windows.Forms.Application]::DoEvents()
            }
        }
        'Dism' {
            $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\dism.exe') -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup /NoRestart' -WindowStyle Hidden -PassThru
            Wait-ProcUi $p
        }
        'RegClear' {
            foreach ($rp in $it.Paths) {
                $k = Open-Reg $rp $true
                if ($k) {
                    foreach ($n in $k.GetValueNames()) { try { $k.DeleteValue($n, $false) } catch { } }
                    $k.Close()
                }
            }
        }
        default {
            $stopped = @()
            foreach ($s in $it.Svc) {
                $sv = Get-Service -Name $s -ErrorAction SilentlyContinue
                if ($sv -and $sv.Status -eq 'Running') { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue; $stopped += $s }
            }
            try {
                foreach ($p in $it.Paths) {
                    if (-not (Test-SafeClean $p)) { continue }
                    foreach ($f in (Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue)) {
                        if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                        Remove-Item -LiteralPath $f.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    [Windows.Forms.Application]::DoEvents()
                }
            } finally {
                foreach ($s in $stopped) { Start-Service -Name $s -ErrorAction SilentlyContinue }
            }
        }
    }
}

# ====================================================================== REGISTRY CLEANER
function Add-RegIssue($List, [string]$Cat, [string]$Item, [string]$Path, [string]$Kind, [string]$Name) {
    [void]$List.Add(@{ Cat = $Cat; Item = $Item; Path = $Path; Kind = $Kind; Name = $Name })
}

function Find-RegistryIssues {
    $script:FixedRoots = $null
    $out = New-Object System.Collections.ArrayList

    # 1. missing shared DLLs
    foreach ($base in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDLLs', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\SharedDLLs')) {
        $k = Open-Reg $base
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if ($n -and (Test-Missing $n)) { Add-RegIssue $out 'Missing shared DLL' $n $base 'Value' $n }
        }
        $k.Close()
        [Windows.Forms.Application]::DoEvents()
    }

    # 2. obsolete application paths
    foreach ($base in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths')) {
        $k = Open-Reg $base
        if (-not $k) { continue }
        foreach ($sn in $k.GetSubKeyNames()) {
            $sk = $k.OpenSubKey($sn)
            if (-not $sk) { continue }
            $def = [string]$sk.GetValue('')
            $sk.Close()
            $f = Get-CmdFile $def
            if ($f -and (Test-Missing $f)) { Add-RegIssue $out 'Obsolete application path' $sn ($base + '\' + $sn) 'Key' $null }
        }
        $k.Close()
        [Windows.Forms.Application]::DoEvents()
    }

    # 3. broken uninstall entries (uninstaller and install folder are both gone)
    foreach ($base in $UninstallRoots) {
        $k = Open-Reg $base
        if (-not $k) { continue }
        foreach ($sn in $k.GetSubKeyNames()) {
            $sk = $k.OpenSubKey($sn)
            if (-not $sk) { continue }
            $dn = [string]$sk.GetValue('DisplayName')
            $us = [string]$sk.GetValue('UninstallString')
            $il = [string]$sk.GetValue('InstallLocation')
            $sc = $sk.GetValue('SystemComponent')
            $wi = $sk.GetValue('WindowsInstaller')
            $parent = [string]$sk.GetValue('ParentKeyName')
            $sk.Close()
            if (-not $dn -or -not $us -or $parent -or $sc -eq 1 -or $wi -eq 1) { continue }
            $f = Get-CmdFile $us
            if (-not $f -or -not (Test-Missing $f)) { continue }
            if ($il -and -not (Test-Missing $il)) { continue }
            Add-RegIssue $out 'Broken uninstall entry' $dn ($base + '\' + $sn) 'Key' $null
        }
        $k.Close()
        [Windows.Forms.Application]::DoEvents()
    }

    # 4. startup entries that point to missing programs
    foreach ($base in $RunKeys) {
        $k = Open-Reg $base
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if (-not $n) { continue }
            $f = Get-CmdFile ([string]$k.GetValue($n))
            if ($f -and (Test-Missing $f)) { Add-RegIssue $out 'Startup entry with missing program' $n $base 'Value' $n }
        }
        $k.Close()
    }

    # 5. stale MUI cache entries
    $mui = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
    $k = Open-Reg $mui
    if ($k) {
        foreach ($n in $k.GetValueNames()) {
            if ($n -match '^(.*)\.(FriendlyAppName|ApplicationCompany)$') {
                $f = $Matches[1]
                if (Test-Missing $f) { Add-RegIssue $out 'Stale MUI cache entry' $f $mui 'Value' $n }
            }
        }
        $k.Close()
    }

    # 6. compatibility settings for programs that no longer exist
    foreach ($base in @('HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers', 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
                        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Persisted', 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store')) {
        $k = Open-Reg $base
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if ($n -and (Test-Missing $n)) { Add-RegIssue $out 'Obsolete compatibility entry' $n $base 'Value' $n }
        }
        $k.Close()
    }

    # 7. installer folder records for folders that are gone
    $inst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Folders'
    $k = Open-Reg $inst
    if ($k) {
        foreach ($n in $k.GetValueNames()) {
            if ($n -and (Test-Missing $n)) { Add-RegIssue $out 'Missing installer folder' $n $inst 'Value' $n }
        }
        $k.Close()
    }

    return ($out | Sort-Object { $_.Cat }, { $_.Item })
}

# Saves a .reg backup of each affected key first, then deletes. Nothing is deleted without a backup.
function Remove-RegIssues($Issues, [string]$BakDir) {
    New-Item -ItemType Directory -Path $BakDir -Force | Out-Null
    $saved = @{}
    $done = New-Object System.Collections.ArrayList
    $fail = 0; $n = 0
    foreach ($i in $Issues) {
        $n++
        $keyPath = [string]$i.Path
        if (-not $saved.ContainsKey($keyPath)) {
            $native = $keyPath -replace '^(HK[A-Z]{2}):\\?', '$1\'
            $file = Join-Path $BakDir ('{0:D4}.reg' -f $saved.Count)
            $okExport = $false
            try {
                $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\reg.exe') -ArgumentList ('export "{0}" "{1}" /y' -f $native, $file) -WindowStyle Hidden -PassThru
                Wait-ProcUi $p
                $okExport = ($p.ExitCode -eq 0 -and (Test-Path -LiteralPath $file))
            } catch { }
            $saved[$keyPath] = $okExport
            if ($okExport) { Add-Content -LiteralPath (Join-Path $BakDir 'index.txt') -Value ('{0}  {1}' -f (Split-Path $file -Leaf), $native) }
        }
        if (-not $saved[$keyPath]) { $fail++; Write-Log ("Backup failed, left untouched: " + $i.Item) 'ERROR'; continue }
        try {
            if ($i.Kind -eq 'Key') {
                $s = Split-RegPath $i.Path
                $s.Root.DeleteSubKeyTree($s.Sub, $false)
            } else {
                $k = Open-Reg $i.Path $true
                if ($k) { $k.DeleteValue($i.Name, $false); $k.Close() }
            }
            [void]$done.Add($i)
        } catch { $fail++; Write-Log ("Could not remove {0}: {1}" -f $i.Item, $_.Exception.Message) 'ERROR' }
        if (($n % 10) -eq 0) { [Windows.Forms.Application]::DoEvents() }
    }
    return @{ Done = $done; Fail = $fail }
}

# ====================================================================== LEFTOVERS
$ProtectedFolders = @('Common Files', 'Microsoft*', 'Windows*', 'WindowsApps', 'ModifiableWindowsApps', 'WindowsPowerShell', 'Internet Explorer',
    'Reference Assemblies', 'MSBuild', 'dotnet', 'Uninstall Information', 'Application Verifier', 'IIS', 'IIS Express', 'Packages', 'Package Cache',
    'Temp', 'Programs', 'Publishers', 'ConnectedDevices', 'VirtualStore', 'Comms', 'PlaceholderTileLogoFolder', 'USOShared', 'USOPrivate', 'regid.*',
    'SoftwareDistribution', 'ssh', 'Intel', 'NVIDIA*', 'AMD', 'Realtek*', 'Dolby*', 'Synaptics*', 'Qualcomm*', 'Waves*', 'WinCrow', 'Application Data',
    'Desktop', 'Documents', 'Start Menu', 'Templates', 'Low', 'History', 'INetCache', 'CrashDumps', 'D3DSCache', 'Adobe', 'Google', 'Mozilla', 'Apple*',
    'Oracle', 'Java', 'Git', 'Docker', 'Python*', 'nodejs', 'PowerShell')

function Test-Protected([string]$Name) {
    foreach ($p in $ProtectedFolders) { if ($Name -like $p) { return $true } }
    return $false
}

function Test-NameKnown([string]$Folder, $Names) {
    $n = Get-NormName $Folder
    if ($n.Length -lt 3) { return $true }
    foreach ($x in $Names) {
        if (-not $x) { continue }
        if ($x.Contains($n)) { return $true }
        if ($x.Length -ge 4 -and $n.Contains($x)) { return $true }
    }
    return $false
}

# Everything that proves a folder is still in use: installed programs, services, running processes, startup items, tasks
function Get-InUseEvidence {
    $names = New-Object System.Collections.ArrayList
    $paths = New-Object System.Collections.ArrayList
    foreach ($base in $UninstallRoots) {
        $k = Open-Reg $base
        if (-not $k) { continue }
        foreach ($sn in $k.GetSubKeyNames()) {
            $sk = $k.OpenSubKey($sn)
            if (-not $sk) { continue }
            foreach ($v in @('DisplayName', 'Publisher')) { $x = [string]$sk.GetValue($v); if ($x) { [void]$names.Add((Get-NormName $x)) } }
            foreach ($v in @('InstallLocation', 'UninstallString', 'DisplayIcon')) { $x = [string]$sk.GetValue($v); if ($x) { [void]$paths.Add($x.ToLower()) } }
            $sk.Close()
        }
        $k.Close()
        [Windows.Forms.Application]::DoEvents()
    }
    try { foreach ($s in (Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)) { if ($s.PathName) { [void]$paths.Add(([string]$s.PathName).ToLower()) } } } catch { }
    try { foreach ($p in (Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)) { if ($p.ExecutablePath) { [void]$paths.Add(([string]$p.ExecutablePath).ToLower()) } } } catch { }
    foreach ($rk in $RunKeys) {
        $k = Open-Reg $rk
        if ($k) { foreach ($n in $k.GetValueNames()) { $x = [string]$k.GetValue($n); if ($x) { [void]$paths.Add($x.ToLower()) } }; $k.Close() }
    }
    try {
        foreach ($t in (Get-ScheduledTask -ErrorAction Stop)) {
            foreach ($a in $t.Actions) { if ($a.Execute) { [void]$paths.Add(([string]$a.Execute).ToLower()) } }
        }
    } catch { }
    [Windows.Forms.Application]::DoEvents()
    return @{ Names = @($names); Paths = @($paths) }
}

function Find-Leftovers {
    $script:FixedRoots = $null
    $out = New-Object System.Collections.ArrayList
    $cut = (Get-Date).AddDays(-30)
    $ev = Get-InUseEvidence
    $evPaths = New-Object System.Collections.ArrayList
    [void]$evPaths.AddRange(@($ev.Paths))

    # shortcuts: broken ones are leftovers, working ones prove a folder is in use
    $ws = New-Object -ComObject WScript.Shell
    $scDirs = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
                [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) |
              Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach ($d in $scDirs) {
        foreach ($l in (Get-ChildItem -LiteralPath $d -Filter '*.lnk' -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $t = $null
            try { $t = [string]$ws.CreateShortcut($l.FullName).TargetPath } catch { continue }
            if (-not $t) { continue }
            if (Test-Missing $t) {
                [void]$out.Add(@{ Kind = 'Shortcut'; Cat = 'Broken shortcut'; Path = $l.FullName; Why = ('Points to a file that is gone: ' + $t); Size = 0.0 })
            } else { [void]$evPaths.Add($t.ToLower()) }
        }
        [Windows.Forms.Application]::DoEvents()
    }

    # folders: empty ones everywhere, orphaned program folders in Program Files
    $pf = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    $roots = @($pf) + @($env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach ($r in $roots) {
        $isPf = ($pf -contains $r)
        foreach ($d in (Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue)) {
            if (($d.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::System)) -ne 0) { continue }
            if (Test-Protected $d.Name) { continue }
            if ($d.LastWriteTime -gt $cut) { continue }
            $first = Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $first) {
                [void]$out.Add(@{ Kind = 'EmptyDir'; Cat = 'Empty folder'; Path = $d.FullName; Why = ('Contains no files. Last changed ' + $d.LastWriteTime.ToString('yyyy-MM-dd')); Size = 0.0 })
                continue
            }
            if (-not $isPf) { continue }
            if (Test-NameKnown $d.Name $ev.Names) { continue }
            $low = $d.FullName.ToLower()
            $used = $false
            foreach ($p in $evPaths) { if ($p.Contains($low)) { $used = $true; break } }
            if ($used) { continue }
            $sz = Get-DirBytes $d.FullName
            [void]$out.Add(@{ Kind = 'Orphan'; Cat = 'Program folder with no matching program'; Path = $d.FullName
                              Why = ('{0}. No installed program, service, startup item or shortcut uses it. Last changed {1}' -f (Format-Size $sz), $d.LastWriteTime.ToString('yyyy-MM-dd')); Size = $sz })
        }
        [Windows.Forms.Application]::DoEvents()
    }
    return ($out | Sort-Object { $_.Kind }, { $_.Path })
}

function Remove-Leftovers($Items) {
    $done = New-Object System.Collections.ArrayList
    $qRoot = $null
    foreach ($i in $Items) {
        try {
            switch ($i.Kind) {
                'Shortcut' { Remove-Item -LiteralPath $i.Path -Force -ErrorAction Stop }
                'EmptyDir' { Remove-Item -LiteralPath $i.Path -Recurse -Force -ErrorAction Stop }
                'Orphan' {
                    if (-not $qRoot) {
                        $qRoot = Join-Path $QuarantineDir (Get-Date -Format 'yyyyMMdd-HHmmss')
                        New-Item -ItemType Directory -Path $qRoot -Force | Out-Null
                    }
                    $leaf = Split-Path $i.Path -Leaf
                    $tag = (Split-Path (Split-Path $i.Path -Parent) -Leaf) -replace '[^A-Za-z0-9]', ''
                    $dest = Join-Path $qRoot ($tag + '_' + $leaf)
                    $x = 1
                    while (Test-Path -LiteralPath $dest) { $dest = (Join-Path $qRoot ($tag + '_' + $leaf)) + '-' + $x; $x++ }
                    Move-Item -LiteralPath $i.Path -Destination $dest -Force -ErrorAction Stop
                    Add-Content -LiteralPath (Join-Path $qRoot 'origin.txt') -Value ($dest + '  <-  ' + $i.Path)
                }
            }
            [void]$done.Add($i)
            Write-Log ('Removed: ' + $i.Path)
        } catch { Write-Log ('Could not remove {0}: {1}' -f $i.Path, $_.Exception.Message) 'ERROR' }
        [Windows.Forms.Application]::DoEvents()
    }
    return $done
}

# ====================================================================== UPDATES (version.txt on the main branch)
# WinCrow reads version.txt from the main branch of the GitHub project. Same number: nothing happens.
# Higher number: it offers to replace this script with WinCrow.ps1 from the main branch.
$RawBase    = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main"
$VersionUrl = "$RawBase/version.txt"
$ScriptUrl  = "$RawBase/WinCrow.ps1"
$UserAgent  = "WinCrow/$AppVersion"
$script:PendingUpdate = $null

# Runs in a background job at startup and inline when you press "Check for updates"
$UpdateFetch = {
    param($uri, $ua)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-WebRequest -Uri $uri -UseBasicParsing -Headers @{ 'User-Agent' = $ua; 'Cache-Control' = 'no-cache' } -TimeoutSec 8 -ErrorAction Stop
        [pscustomobject]@{ Ok = $true; Text = [string]$r.Content; Code = 200; Msg = '' }
    } catch {
        $c = 0
        try { $c = [int]$_.Exception.Response.StatusCode } catch { }
        [pscustomobject]@{ Ok = $false; Text = ''; Code = $c; Msg = $_.Exception.Message }
    }
}

function Read-Version($res) {
    if (-not $res) { return @{ State = 'Error'; Msg = 'No answer from GitHub.' } }
    if (-not $res.Ok) {
        if ($res.Code -eq 404) { return @{ State = 'NoVersion' } }
        return @{ State = 'Error'; Msg = [string]$res.Msg }
    }
    $first = (([string]$res.Text).Trim([char[]]@([char]0xFEFF, ' ', "`r", "`n", "`t")) -split "`n")[0].Trim()
    if ($first -match '^[vV]?([0-9]+(\.[0-9]+){1,3})$') {
        $ver = [version]$Matches[1]
        $state = 'Current'
        if ($ver -gt [version]$AppVersion) { $state = 'Newer' }
        return @{ State = $state; Tag = ('v' + $ver.ToString()); Version = $ver.ToString(); Page = $RepoUrl; Notes = ''; Download = $ScriptUrl }
    }
    return @{ State = 'Error'; Msg = 'version.txt on GitHub does not contain a version number such as 1.2.0.' }
}

# Downloads WinCrow.ps1 from the main branch, checks it, swaps the script file and restarts WinCrow
function Install-Update($rel) {
    $dest = $PSCommandPath
    if (-not $dest) { throw 'The path of this script is unknown, so it cannot be updated.' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $hdr = @{ 'User-Agent' = $UserAgent; 'Cache-Control' = 'no-cache' }
    $tmp = Join-Path $env:TEMP ('WinCrow-update-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
    Write-Log ('Downloading WinCrow ' + $rel.Version + '...')
    try {
        Invoke-WebRequest -Uri $rel.Download -OutFile $tmp -UseBasicParsing -Headers $hdr -TimeoutSec 60 -ErrorAction Stop
        $tok = $null; $errs = $null
        [void][Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$tok, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) { throw 'The downloaded file is not a valid PowerShell script, so nothing was changed.' }
        $body = Get-Content -LiteralPath $tmp -Raw
        if ($body -notmatch '\$AppName\s*=\s*''WinCrow''') { throw 'The downloaded file does not look like WinCrow, so nothing was changed.' }
        if ($body -match '\$AppVersion\s*=\s*''([0-9.]+)''') {
            if ([version]$Matches[1] -le [version]$AppVersion) {
                throw ('version.txt says ' + $rel.Version + ' but WinCrow.ps1 on GitHub is still version ' + $Matches[1] + '. Nothing was changed.')
            }
        } else { throw 'The downloaded file has no version number, so nothing was changed.' }
        Copy-Item -LiteralPath $dest -Destination ($dest + '.bak') -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath $tmp -Destination $dest -Force
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    Write-Log ('Updated to ' + $rel.Version + '. Restarting WinCrow...')
    Start-Process -FilePath $PsExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$dest`"")
    $form.Close()
}

# ====================================================================== UI BUILDING BLOCKS
function Set-Role($ctl, [string]$Role) { $script:Roles[$ctl] = $Role; return $ctl }

function Style-Btn($b, [string]$Kind) {
    switch ($Kind) {
        'primary' { $b.BackColor = $C.Accent; $b.ForeColor = (Hex '#FFFFFF'); $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $C.Accent2 }
        'danger'  { $b.BackColor = $C.Danger; $b.ForeColor = (Hex '#FFFFFF'); $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.MouseOverBackColor = $C.DangerHover }
        default   { $b.BackColor = $C.Panel2; $b.ForeColor = $C.Text; $b.FlatAppearance.BorderSize = 1; $b.FlatAppearance.BorderColor = $C.Line; $b.FlatAppearance.MouseOverBackColor = $C.Hover }
    }
}

function New-Btn([string]$Text, [string]$Kind = 'ghost', [int]$W = 150) {
    $b = New-Object Windows.Forms.Button
    $b.Font = Fnt 'Strong'
    # width is in 96-DPI units; it grows to fit the label at any display scale
    $need = [int][Math]::Ceiling((Get-TextPx $Text $b.Font).Width / $script:DpiScale) + 34
    if ($need -gt $W) { $W = $need }
    $b.Text = $Text; $b.Width = $W; $b.Height = 36; $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'
    $b.Margin = New-Object Windows.Forms.Padding(0, 0, 10, 6)
    Style-Btn $b $Kind
    [void](Set-Role $b "btn:$Kind")
    return $b
}

# The first column (names, paths) gets at least the width its text needs, up to 55% of the list.
# The other columns share what is left in their given proportions.
$script:Need0 = @{}
function Fit-Columns($lv) {
    $w = $lv.ClientSize.Width - 6
    if ($w -lt 50) { return }
    $ratio = $lv.Tag
    $sum = ($ratio | Measure-Object -Sum).Sum
    $n = $lv.Columns.Count
    $w0 = [int]($w * $ratio[0] / $sum)
    $need = $script:Need0[$lv]
    if ($need -and $need -gt $w0) { $w0 = [int][Math]::Min($need, $w * 0.55) }
    $lv.Columns[0].Width = $w0
    $rsum = $sum - $ratio[0]
    if ($n -lt 2 -or $rsum -le 0) { return }
    $rest = $w - $w0
    for ($i = 1; $i -lt $n; $i++) { $lv.Columns[$i].Width = [int]($rest * $ratio[$i] / $rsum) }
}

# Call after filling a list: measures the first column, adds a hover tip with the full row text where none is set, fits the columns
function Finish-List($lv) {
    $max = 0
    foreach ($it in $lv.Items) {
        $m = [Windows.Forms.TextRenderer]::MeasureText($it.Text, $lv.Font).Width
        if ($m -gt $max) { $max = $m }
        if (-not $it.ToolTipText) {
            $parts = @($it.SubItems | ForEach-Object { $_.Text })
            $it.ToolTipText = ($parts -join "`r`n")
        }
    }
    $script:Need0[$lv] = $max + [int](40 * $script:DpiScale)
    Fit-Columns $lv
}

function New-List([int[]]$Ratio) {
    $lv = New-Object Windows.Forms.ListView
    $lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true
    $lv.HeaderStyle = 'None'; $lv.BorderStyle = 'None'; $lv.MultiSelect = $false; $lv.ShowGroups = $true
    $lv.BackColor = $C.Panel; $lv.ForeColor = $C.Text
    $lv.Font = Fnt 'Body'
    $lv.Tag = $Ratio
    $lv.ShowItemToolTips = $true
    foreach ($r in $Ratio) { [void]$lv.Columns.Add('', 100) }
    $lv.Add_Resize({ param($s, $e) Fit-Columns $s })
    [void](Set-Role $lv 'list')
    return $lv
}

function New-Page([string]$Title, [string]$Sub, [int[]]$Ratio) {
    $page = New-Object Windows.Forms.Panel
    $page.Dock = 'Fill'; $page.BackColor = $C.Bg; $page.Visible = $false
    [void](Set-Role $page 'bg')

    $cap = New-Object Windows.Forms.Panel
    $cap.Dock = 'Top'; $cap.Height = 68; $cap.BackColor = $C.Bg
    [void](Set-Role $cap 'bg')
    $t = New-Object Windows.Forms.Label
    $t.Text = $Title; $t.AutoSize = $true; $t.ForeColor = $C.Text
    $t.Font = Fnt 'Title'; $t.Location = New-Object Drawing.Point(20, 8)
    [void](Set-Role $t 'title')
    $s = New-Object Windows.Forms.Label
    $s.Text = $Sub; $s.AutoSize = $false; $s.ForeColor = $C.Dim
    $s.Font = Fnt 'Body'; $s.Location = New-Object Drawing.Point(22, 40); $s.Size = New-Object Drawing.Size(400, 20)
    [void](Set-Role $s 'sub')
    $cap.Controls.AddRange(@($t, $s))
    $cap.Tag = @{ T = $t; S = $s }
    # the subtitle wraps to the available width and the caption grows with it, at any display scale
    $fitCap = {
        param($cp, $ev)
        if ($cp.ClientSize.Width -lt 50) { return }
        $lt = $cp.Tag.T; $ls = $cp.Tag.S
        $w = [Math]::Max(200, $cp.ClientSize.Width - $ls.Left - [int](20 * $script:DpiScale))
        $ls.Top = $lt.Bottom + [int](2 * $script:DpiScale)
        $m = [Windows.Forms.TextRenderer]::MeasureText($ls.Text, $ls.Font, (New-Object Drawing.Size(($w - [int](8 * $script:DpiScale)), 0)), [Windows.Forms.TextFormatFlags]::WordBreak)
        $ls.Size = New-Object Drawing.Size($w, ($m.Height + [int](4 * $script:DpiScale)))
        $h = $ls.Bottom + [int](8 * $script:DpiScale)
        if ($cp.Height -ne $h) { $cp.Height = $h }
    }
    $cap.Add_Resize($fitCap)
    $cap.Add_VisibleChanged($fitCap)

    $bar = New-Object Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Bottom'; $bar.BackColor = $C.Bg; $bar.WrapContents = $true
    $bar.AutoSize = $true; $bar.AutoSizeMode = 'GrowAndShrink'
    $bar.Padding = New-Object Windows.Forms.Padding(20, 12, 10, 8)
    [void](Set-Role $bar 'bg')

    $lv = $null
    if ($Ratio) { $lv = New-List $Ratio; $page.Controls.Add($lv) }
    $page.Controls.Add($bar)
    $page.Controls.Add($cap)
    return [pscustomobject]@{ Page = $page; List = $lv; Bar = $bar }
}

function Invoke-Busy([scriptblock]$Block) {
    if ($script:Busy) { return }
    $script:Busy = $true
    $form.UseWaitCursor = $true
    try { & $Block }
    catch { Write-Log $_.Exception.Message 'ERROR' }
    finally { $script:Busy = $false; $form.UseWaitCursor = $false; $script:Progress.Value = 0 }
}

# ====================================================================== FORM
$form = New-Object Windows.Forms.Form
$form.Text = 'WinCrow'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object Drawing.Size(1060, 740)
$form.MinimumSize = New-Object Drawing.Size(900, 580)
$form.BackColor = $C.Bg; $form.ForeColor = $C.Text
$form.Font = Fnt 'Body'
$form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
$form.AutoScaleMode = 'Dpi'
try { $form.Icon = [Drawing.Icon]::FromHandle((New-CrowBitmap 32).GetHicon()) } catch { }
$script:LogoBmp = New-CrowBitmap 160

# --- header
$header = New-Object Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = 78; $header.BackColor = $C.Panel
[void](Set-Role $header 'panel')
$header.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $k = $g.DpiX / 96.0
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
    $fl = [Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::NoPrefix
    $f1 = Fnt 'Display'
    $f2 = Fnt 'Body'
    $none = New-Object Drawing.Size(0, 0)
    $tag = 'Scavenge the bloat. Leave only bones.'
    $t1 = [Windows.Forms.TextRenderer]::MeasureText($g, 'Win', $f1, $none, $fl)
    $t3 = [Windows.Forms.TextRenderer]::MeasureText($g, $tag, $f2, $none, $fl)
    $stripe = [int][Math]::Ceiling(3 * $k)
    $pad = [int][Math]::Round(10 * $k)
    $logo = $s.Height - $stripe - 2 * $pad
    $x0 = [int][Math]::Round(16 * $k)
    $g.DrawImage($script:LogoBmp, $x0, $pad, $logo, $logo)
    $tx = $x0 + $logo + [int][Math]::Round(12 * $k)
    $tuck = [int][Math]::Round(4 * $k)
    $ty = [int](($s.Height - $stripe - ($t1.Height + $t3.Height - $tuck)) / 2)
    [Windows.Forms.TextRenderer]::DrawText($g, 'Win', $f1, (New-Object Drawing.Point($tx, $ty)), $C.Text, $fl)
    [Windows.Forms.TextRenderer]::DrawText($g, 'Crow', $f1, (New-Object Drawing.Point(($tx + $t1.Width), $ty)), $C.Accent, $fl)
    [Windows.Forms.TextRenderer]::DrawText($g, $tag, $f2, (New-Object Drawing.Point($tx, ($ty + $t1.Height - $tuck))), $C.Dim, $fl)
    $r = New-Object Drawing.Rectangle(0, ($s.Height - $stripe), $s.Width, $stripe)
    $gb = New-Object Drawing.Drawing2D.LinearGradientBrush $r, $C.Accent, $C.Accent2, 0.0
    $g.FillRectangle($gb, $r)
    $f1.Dispose(); $f2.Dispose(); $gb.Dispose()
})

# --- left navigation
$nav = New-Object Windows.Forms.Panel
$nav.Dock = 'Left'; $nav.Width = 190; $nav.BackColor = $C.Panel
[void](Set-Role $nav 'panel')
$NavBtns = @{}
$Pg = @{}
$script:CurPage = 'Debloat'

function Show-Page([string]$Key) {
    $script:CurPage = $Key
    foreach ($k in $Pg.Keys) { $Pg[$k].Page.Visible = ($k -eq $Key) }
    foreach ($k in $NavBtns.Keys) {
        if ($k -eq $Key) { $NavBtns[$k].BackColor = $C.Panel2; $NavBtns[$k].ForeColor = $C.Accent }
        else { $NavBtns[$k].BackColor = $C.Panel; $NavBtns[$k].ForeColor = $C.Text }
    }
}

$i = 0
foreach ($n in @(@{ K = 'Debloat'; T = '   Debloat' }, @{ K = 'Cleaner'; T = '   Cleaner' }, @{ K = 'Registry'; T = '   Registry' }, @{ K = 'Leftovers'; T = '   Leftovers' },
                 @{ K = 'Startup'; T = '   Startup apps' }, @{ K = 'Tweaks'; T = '   Tweaks' }, @{ K = 'About'; T = '   About' })) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $n.T; $b.Tag = $n.K; $b.TextAlign = 'MiddleLeft'; $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'
    $b.FlatAppearance.BorderSize = 0
    $b.Font = Fnt 'Nav'
    $b.Size = New-Object Drawing.Size(190, 44)
    $b.Location = New-Object Drawing.Point(0, (12 + $i * 46))
    $b.Add_Click({ param($s, $e) Show-Page $s.Tag })
    [void](Set-Role $b 'nav')
    $nav.Controls.Add($b)
    $NavBtns[$n.K] = $b
    $i++
}

$btnTheme = New-Btn 'Light theme' 'ghost' 160
$btnTheme.Margin = New-Object Windows.Forms.Padding(0)
$btnTheme.Location = New-Object Drawing.Point(15, 420)
$nav.Controls.Add($btnTheme)
$btnUpdate = New-Btn 'Update available' 'primary' 160
$btnUpdate.Margin = New-Object Windows.Forms.Padding(0)
$btnUpdate.Location = New-Object Drawing.Point(15, 376)
$btnUpdate.Visible = $false
$nav.Controls.Add($btnUpdate)
$nav.Add_Resize({
    $btnTheme.Location  = New-Object Drawing.Point($btnTheme.Left, ($nav.ClientSize.Height - $btnTheme.Height - [int](12 * $script:DpiScale)))
    $btnUpdate.Location = New-Object Drawing.Point($btnUpdate.Left, ($btnTheme.Top - $btnUpdate.Height - [int](8 * $script:DpiScale)))
})

# --- main area
$main = New-Object Windows.Forms.Panel
$main.Dock = 'Fill'; $main.BackColor = $C.Bg
[void](Set-Role $main 'bg')

$Pg.Debloat = New-Page 'Debloat' 'Tick the apps you want gone. Recommended ones are pre-ticked. Removal is for all users and also stops them returning on new accounts.' @(45, 55)
$Pg.Startup = New-Page 'Startup apps' 'Ticked = starts with Windows. Untick the ones you want to stop, then press Apply. Nothing is deleted - you can turn them back on here.' @(30, 18, 52)
$Pg.Tweaks  = New-Page 'Tweaks' 'Ticked = tweak is active. Tick to apply, untick to restore the Windows default.' @(38, 62)
$Pg.Cleaner   = New-Page 'Cleaner' 'Tick what to clean. Analyze shows the size of each item. Close browsers first. Cleaned files skip the Recycle Bin.' @(30, 54, 16)
$Pg.Registry  = New-Page 'Registry' 'Finds broken and obsolete entries. A .reg backup is saved before any change, so every fix can be undone.' @(30, 48, 22)
$Pg.Leftovers = New-Page 'Leftovers' 'Empty folders, broken shortcuts and program folders that look uninstalled. Program folders go to quarantine.' @(46, 16, 38)
$Pg.About   = New-Page 'About' '' $null
foreach ($k in 'Debloat', 'Cleaner', 'Registry', 'Leftovers', 'Startup', 'Tweaks', 'About') { $main.Controls.Add($Pg[$k].Page) }

$script:Progress = New-Object Windows.Forms.ProgressBar
$script:Progress.Dock = 'Bottom'; $script:Progress.Height = 6; $script:Progress.Style = 'Continuous'
$main.Controls.Add($script:Progress)

$script:LogBox = New-Object Windows.Forms.TextBox
$script:LogBox.Dock = 'Bottom'; $script:LogBox.Height = 120; $script:LogBox.Multiline = $true; $script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = 'Vertical'; $script:LogBox.BorderStyle = 'None'
$script:LogBox.BackColor = $C.LogBg; $script:LogBox.ForeColor = $C.LogFg
$script:LogBox.Font = Fnt 'Mono'
[void](Set-Role $script:LogBox 'log')
$main.Controls.Add($script:LogBox)

$form.Controls.Add($main)
$form.Controls.Add($nav)
$form.Controls.Add($header)

# ====================================================================== DEBLOAT PAGE
$chkRestore = New-Object Windows.Forms.CheckBox
$chkRestore.Text = 'Create a restore point first'; $chkRestore.Checked = $true; $chkRestore.AutoSize = $true
$chkRestore.ForeColor = $C.Text; $chkRestore.Margin = New-Object Windows.Forms.Padding(8, 8, 0, 0)
[void](Set-Role $chkRestore 'bg')

$btnRemove  = New-Btn 'Remove selected' 'primary' 150
$btnRecom   = New-Btn 'Recommended' 'ghost' 120
$btnNone    = New-Btn 'Select none' 'ghost' 100
$btnRescan  = New-Btn 'Rescan' 'ghost' 90
$Pg.Debloat.Bar.Controls.AddRange(@($btnRemove, $btnRecom, $btnNone, $btnRescan, $chkRestore))

function Load-Debloat {
    $lv = $Pg.Debloat.List
    Write-Log 'Scanning installed apps...'
    $lv.BeginUpdate()
    $lv.Items.Clear(); $lv.Groups.Clear()
    $groups = @{
        R = (New-Object Windows.Forms.ListViewGroup('R', 'Recommended to remove'))
        O = (New-Object Windows.Forms.ListViewGroup('O', 'Optional - you may use these'))
        X = (New-Object Windows.Forms.ListViewGroup('X', 'Other installed apps'))
    }
    foreach ($k in 'R', 'O', 'X') { [void]$lv.Groups.Add($groups[$k]) }
    foreach ($a in (Get-InstalledApps)) {
        $it = New-Object Windows.Forms.ListViewItem($a.Label)
        [void]$it.SubItems.Add($a.Name)
        $it.Tag = $a
        $it.Group = $groups[$a.Tier]
        $it.Checked = ($a.Tier -eq 'R')
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
    Finish-List $lv
    Write-Log ("Found {0} removable app(s)." -f $lv.Items.Count)
}

$btnRecom.Add_Click({ foreach ($it in $Pg.Debloat.List.Items) { $it.Checked = ($it.Tag.Tier -eq 'R') } })
$btnNone.Add_Click({ foreach ($it in $Pg.Debloat.List.Items) { $it.Checked = $false } })
$btnRescan.Add_Click({ Invoke-Busy { Load-Debloat } })

$btnRemove.Add_Click({
    $sel = @($Pg.Debloat.List.CheckedItems | ForEach-Object { $_.Tag })
    if ($sel.Count -eq 0) { Show-Msg 'Nothing is selected.'; return }
    $ans = [Windows.Forms.MessageBox]::Show("Remove $($sel.Count) app(s) for all users?`n`nThey can be reinstalled later from the Microsoft Store.", 'WinCrow', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Invoke-Busy {
        if ($chkRestore.Checked) {
            Write-Log 'Creating restore point...'
            try {
                Checkpoint-Computer -Description 'WinCrow - before debloat' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                Write-Log 'Restore point created.'
            } catch { Write-Log ('Restore point skipped: ' + $_.Exception.Message) 'WARN' }
        }
        $prov = @()
        try { $prov = @(Get-AppxProvisionedPackage -Online) } catch { Write-Log 'Could not read provisioned packages.' 'WARN' }
        $script:Progress.Maximum = $sel.Count
        $ok = 0; $fail = 0; $n = 0
        foreach ($a in $sel) {
            $n++
            Write-Log "Removing $($a.Label)..."
            try {
                foreach ($f in $a.Full) {
                    try { Remove-AppxPackage -Package $f -AllUsers -ErrorAction Stop }
                    catch { Remove-AppxPackage -Package $f -ErrorAction Stop }
                }
                foreach ($p in @($prov | Where-Object { $_.DisplayName -eq $a.Name })) {
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                }
                $ok++
            } catch {
                $fail++
                Write-Log ("Failed: {0} - {1}" -f $a.Label, $_.Exception.Message) 'ERROR'
            }
            $script:Progress.Value = $n
            [Windows.Forms.Application]::DoEvents()
        }
        Write-Log ("Done. Removed {0}, failed {1}." -f $ok, $fail)
        Load-Debloat
    }
})

# ====================================================================== STARTUP PAGE
$btnStartApply   = New-Btn 'Apply changes' 'primary' 150
$btnStartAll     = New-Btn 'Tick all' 'ghost' 90
$btnStartNone    = New-Btn 'Untick all' 'ghost' 100
$btnStartRefresh = New-Btn 'Refresh' 'ghost' 90
$Pg.Startup.Bar.Controls.AddRange(@($btnStartApply, $btnStartAll, $btnStartNone, $btnStartRefresh))

function Load-Startup {
    $lv = $Pg.Startup.List
    $lv.BeginUpdate(); $lv.Items.Clear(); $lv.Groups.Clear()
    $lv.ShowGroups = $false
    foreach ($e in (Get-StartupEntries)) {
        $it = New-Object Windows.Forms.ListViewItem($e.Name)
        [void]$it.SubItems.Add($e.Source)
        [void]$it.SubItems.Add($e.Command)
        $it.Tag = $e
        $it.Checked = $e.Enabled
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate(); Finish-List $lv
    Write-Log ("Found {0} startup entr{1}." -f $lv.Items.Count, $(if ($lv.Items.Count -eq 1) { 'y' } else { 'ies' }))
}

$btnStartAll.Add_Click({ foreach ($it in $Pg.Startup.List.Items) { $it.Checked = $true } })
$btnStartNone.Add_Click({ foreach ($it in $Pg.Startup.List.Items) { $it.Checked = $false } })
$btnStartRefresh.Add_Click({ Invoke-Busy { Load-Startup } })
$btnStartApply.Add_Click({
    Invoke-Busy {
        $changed = 0
        foreach ($it in $Pg.Startup.List.Items) {
            $e = $it.Tag
            if ($it.Checked -ne $e.Enabled) {
                try {
                    Set-StartupState $e.Approved $e.Name $it.Checked
                    $e.Enabled = $it.Checked
                    $changed++
                    Write-Log ("{0}: {1} at startup" -f $e.Name, $(if ($it.Checked) { 'enabled' } else { 'disabled' }))
                } catch { Write-Log ("Could not change {0}: {1}" -f $e.Name, $_.Exception.Message) 'ERROR' }
            }
        }
        if ($changed -eq 0) { Write-Log 'No startup changes to apply.' } else { Write-Log "Startup changes applied ($changed). They take effect at next sign-in." }
    }
})

# ====================================================================== TWEAKS PAGE
$btnTwkApply   = New-Btn 'Apply changes' 'primary' 150
$btnTwkRefresh = New-Btn 'Refresh' 'ghost' 90
$Pg.Tweaks.Bar.Controls.AddRange(@($btnTwkApply, $btnTwkRefresh))

function Load-Tweaks {
    $lv = $Pg.Tweaks.List
    $lv.BeginUpdate(); $lv.Items.Clear(); $lv.Groups.Clear(); $lv.ShowGroups = $true
    $groups = @{}
    foreach ($c in $TweakCats) {
        $groups[$c] = New-Object Windows.Forms.ListViewGroup($c, $c)
        [void]$lv.Groups.Add($groups[$c])
    }
    foreach ($t in $Tweaks) {
        if ($t.Only11 -and -not $IsWin11) { continue }
        if ($t.Only10 -and $IsWin11) { continue }
        $on = Test-Tweak $t
        $it = New-Object Windows.Forms.ListViewItem($t.Name)
        [void]$it.SubItems.Add($t.Desc)
        $it.ToolTipText = $t.Desc
        $it.Tag = @{ T = $t; Was = $on }
        $it.Group = $groups[$t.Cat]
        $it.Checked = $on
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate(); Finish-List $lv
    Write-Log ("{0} tweaks available for this PC." -f $lv.Items.Count)
}

$btnTwkRefresh.Add_Click({ Invoke-Busy { Load-Tweaks } })
$btnTwkApply.Add_Click({
    Invoke-Busy {
        $changed = 0; $restart = $false
        foreach ($it in $Pg.Tweaks.List.Items) {
            $t = $it.Tag.T
            if ($it.Checked -ne $it.Tag.Was) {
                try {
                    foreach ($e in $t.Entries) { Set-Entry $e $it.Checked }
                    $it.Tag.Was = $it.Checked
                    $changed++
                    if ($t.RestartExplorer) { $restart = $true }
                    Write-Log ("{0}: {1}" -f $t.Name, $(if ($it.Checked) { 'applied' } else { 'restored to default' }))
                } catch { Write-Log ("Tweak failed ({0}): {1}" -f $t.Name, $_.Exception.Message) 'ERROR' }
            }
        }
        if ($changed -eq 0) { Write-Log 'No tweak changes to apply.'; return }
        if ($restart) { Write-Log 'Restarting File Explorer to apply the change...'; Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }
        Write-Log "Tweaks applied ($changed). Some need a sign-out or restart to fully take effect."
    }
})

# ====================================================================== ABOUT PAGE
$about = New-Object Windows.Forms.FlowLayoutPanel
$about.Dock = 'Fill'; $about.FlowDirection = 'TopDown'; $about.WrapContents = $false; $about.AutoScroll = $true
$about.BackColor = $C.Bg
$about.Padding = New-Object Windows.Forms.Padding(17, 0, 17, 8)
[void](Set-Role $about 'bg')
$script:AboutWrap = New-Object System.Collections.ArrayList

function New-AboutLabel([string]$Text, [string]$Kind, [string]$Role, [int]$Top = 0, [bool]$Wrap = $false) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $Text; $l.Font = Fnt $Kind; $l.AutoSize = $true
    $l.Margin = New-Object Windows.Forms.Padding(3, $Top, 3, 0)
    $l.ForeColor = $C.Text
    if ($Wrap) { [void]$script:AboutWrap.Add($l) }
    [void](Set-Role $l $Role)
    $about.Controls.Add($l)
    return $l
}

# long labels wrap to the panel width, so no line can ever be cut off
$fitAbout = {
    $w = [Math]::Max(300, $about.ClientSize.Width - $about.Padding.Horizontal - [int](12 * $script:DpiScale))
    foreach ($l in $script:AboutWrap) { $l.MaximumSize = New-Object Drawing.Size($w, 0) }
}
$about.Add_Resize($fitAbout)
$about.Add_VisibleChanged($fitAbout)

[void](New-AboutLabel "WinCrow $AppVersion" 'Display' 'title' 4)
[void](New-AboutLabel 'Scavenge the bloat. Leave only bones.' 'Body' 'accent' 0)
[void](New-AboutLabel ('WinCrow strips Windows down to what you actually use: it removes bloated apps, cleans junk files and registry clutter, ' +
                       'controls what starts with Windows and flips the privacy, performance and interface switches that matter. Every change can be reversed from this window.') 'Body' 'title' 14 $true)
[void](New-AboutLabel 'DEVELOPER' 'Strong' 'accent' 18)
[void](New-AboutLabel $DevName 'Title' 'title' 0)
$lnk = New-Object Windows.Forms.LinkLabel
$lnk.Text = $DevEmail; $lnk.AutoSize = $true; $lnk.Margin = New-Object Windows.Forms.Padding(3, 0, 3, 0)
$lnk.Font = Fnt 'Body'; $lnk.Cursor = 'Hand'
$lnk.LinkColor = $C.Accent; $lnk.ActiveLinkColor = $C.Accent2; $lnk.VisitedLinkColor = $C.Accent; $lnk.LinkBehavior = 'HoverUnderline'
$lnk.Add_Click({ try { Start-Process "mailto:$DevEmail" } catch { } })
[void](Set-Role $lnk 'link')
$about.Controls.Add($lnk)
$info = New-Object Windows.Forms.TableLayoutPanel
$info.AutoSize = $true; $info.AutoSizeMode = 'GrowAndShrink'; $info.ColumnCount = 2; $info.RowCount = 3
$info.Margin = New-Object Windows.Forms.Padding(3, 16, 3, 0)
[void](Set-Role $info 'bg')
$infoRow = 0
foreach ($kv in @(@('Detected', "$OsCaption (build $Build)"), @('Installed', $InstallDir), @('Logs', $LogDir))) {
    $kl = New-Object Windows.Forms.Label
    $kl.Text = $kv[0]; $kl.AutoSize = $true; $kl.Font = Fnt 'Body'; $kl.Margin = New-Object Windows.Forms.Padding(0, 2, 24, 2)
    [void](Set-Role $kl 'sub')
    $vl = New-Object Windows.Forms.Label
    $vl.Text = $kv[1]; $vl.AutoSize = $true; $vl.Font = Fnt 'Body'; $vl.Margin = New-Object Windows.Forms.Padding(0, 2, 0, 2)
    [void](Set-Role $vl 'title')
    $info.Controls.Add($kl, 0, $infoRow); $info.Controls.Add($vl, 1, $infoRow)
    $infoRow++
}
$about.Controls.Add($info)
$lblUpdate = New-AboutLabel "Version $AppVersion. Press Check for updates to look for a newer version." 'Body' 'sub' 14 $true
$chkAuto = New-Object Windows.Forms.CheckBox
$chkAuto.Text = 'Check for updates when WinCrow starts'
$chkAuto.AutoSize = $true
$chkAuto.Checked = [bool]$script:Settings.AutoUpdate
$chkAuto.Margin = New-Object Windows.Forms.Padding(5, 8, 3, 0)
$chkAuto.ForeColor = $C.Text
[void](Set-Role $chkAuto 'bg')
$chkAuto.Add_CheckedChanged({ $script:Settings.AutoUpdate = $chkAuto.Checked; Save-Settings })
$about.Controls.Add($chkAuto)
$Pg.About.Page.Controls.Add($about)
$about.BringToFront()

$btnCheckUpd  = New-Btn 'Check for updates' 'primary' 160
$btnRepo      = New-Btn 'GitHub page' 'ghost' 110
$btnOpenLogs  = New-Btn 'Open logs folder' 'ghost' 140
$Pg.About.Bar.Controls.AddRange(@($btnCheckUpd, $btnRepo, $btnOpenLogs))
$btnOpenLogs.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$LogDir`"" })

# ====================================================================== CLEANER PAGE
$btnClRun     = New-Btn 'Clean selected' 'primary' 150
$btnClAnalyze = New-Btn 'Analyze' 'ghost' 100
$btnClAll     = New-Btn 'Select all' 'ghost' 100
$btnClNone    = New-Btn 'Select none' 'ghost' 110
$btnClDef     = New-Btn 'Defaults' 'ghost' 90
$Pg.Cleaner.Bar.Controls.AddRange(@($btnClRun, $btnClAnalyze, $btnClAll, $btnClNone, $btnClDef))

function Load-Cleaner {
    $lv = $Pg.Cleaner.List
    $lv.BeginUpdate(); $lv.Items.Clear(); $lv.Groups.Clear(); $lv.ShowGroups = $true
    $groups = @{}
    foreach ($c in $CleanCats) {
        $groups[$c] = New-Object Windows.Forms.ListViewGroup($c, $c)
        [void]$lv.Groups.Add($groups[$c])
    }
    foreach ($it in $Cleaners) {
        $li = New-Object Windows.Forms.ListViewItem($it.Name)
        [void]$li.SubItems.Add($it.Desc)
        [void]$li.SubItems.Add('?')
        $li.ToolTipText = $it.Desc
        $li.Tag = $it
        $li.Group = $groups[$it.Cat]
        $li.Checked = $it.On
        [void]$lv.Items.Add($li)
    }
    $lv.EndUpdate(); Finish-List $lv
}

$btnClAll.Add_Click({ foreach ($li in $Pg.Cleaner.List.Items) { $li.Checked = $true } })
$btnClNone.Add_Click({ foreach ($li in $Pg.Cleaner.List.Items) { $li.Checked = $false } })
$btnClDef.Add_Click({ foreach ($li in $Pg.Cleaner.List.Items) { $li.Checked = [bool]$li.Tag.On } })

$btnClAnalyze.Add_Click({
    Invoke-Busy {
        $lv = $Pg.Cleaner.List
        $script:Progress.Maximum = [Math]::Max(1, $lv.Items.Count)
        $total = 0.0; $n = 0
        Write-Log 'Measuring what can be cleaned...'
        foreach ($li in $lv.Items) {
            $n++
            $b = Get-CleanSize $li.Tag
            if ($null -eq $b) { $li.SubItems[2].Text = '-' }
            else {
                $li.SubItems[2].Text = Format-Size $b
                if ($li.Checked) { $total += $b }
            }
            $script:Progress.Value = $n
            [Windows.Forms.Application]::DoEvents()
        }
        Write-Log ('Analysis done. {0} can be cleaned from the ticked items.' -f (Format-Size $total))
    }
})

$btnClRun.Add_Click({
    $sel = @($Pg.Cleaner.List.CheckedItems)
    if ($sel.Count -eq 0) { Show-Msg 'Nothing is selected.'; return }
    $ans = [Windows.Forms.MessageBox]::Show("Clean $($sel.Count) item(s)?`n`nClose your browsers and other apps first so their files can be cleared. Cleaned files do not go to the Recycle Bin.", 'WinCrow', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Invoke-Busy {
        $script:Progress.Maximum = $sel.Count
        $freed = 0.0; $n = 0
        foreach ($li in $sel) {
            $n++
            $it = $li.Tag
            Write-Log ('Cleaning ' + $it.Name + '...')
            $before = Get-CleanSize $it
            try { Invoke-CleanItem $it } catch { Write-Log ('Failed: {0} - {1}' -f $it.Name, $_.Exception.Message) 'ERROR' }
            if ($null -ne $before) {
                $after = Get-CleanSize $it
                $d = [Math]::Max(0.0, ([double]$before - [double]$after))
                $freed += $d
                $li.SubItems[2].Text = (Format-Size $d) + ' freed'
            } else { $li.SubItems[2].Text = 'done' }
            $script:Progress.Value = $n
            [Windows.Forms.Application]::DoEvents()
        }
        Write-Log ('Cleaning finished. About {0} freed. Files that were in use were skipped.' -f (Format-Size $freed))
    }
})

# ====================================================================== REGISTRY PAGE
$btnRgScan  = New-Btn 'Scan for issues' 'primary' 130
$btnRgFix   = New-Btn 'Fix selected' 'danger' 120
$btnRgAll   = New-Btn 'Select all' 'ghost' 90
$btnRgNone  = New-Btn 'Select none' 'ghost' 100
$btnRgBak   = New-Btn 'Backups folder' 'ghost' 120
$chkRgRestore = New-Object Windows.Forms.CheckBox
$chkRgRestore.Text = 'Restore point first'; $chkRgRestore.Checked = $true; $chkRgRestore.AutoSize = $true
$chkRgRestore.ForeColor = $C.Text; $chkRgRestore.Margin = New-Object Windows.Forms.Padding(8, 8, 0, 0)
[void](Set-Role $chkRgRestore 'bg')
$Pg.Registry.Bar.Controls.AddRange(@($btnRgScan, $btnRgFix, $btnRgAll, $btnRgNone, $btnRgBak, $chkRgRestore))

$btnRgAll.Add_Click({ foreach ($li in $Pg.Registry.List.Items) { $li.Checked = $true } })
$btnRgNone.Add_Click({ foreach ($li in $Pg.Registry.List.Items) { $li.Checked = $false } })
$btnRgBak.Add_Click({
    New-Item -ItemType Directory -Path $RegBackupRoot -Force | Out-Null
    Start-Process explorer.exe -ArgumentList "`"$RegBackupRoot`""
})

$btnRgScan.Add_Click({
    Invoke-Busy {
        Write-Log 'Scanning the registry...'
        $lv = $Pg.Registry.List
        $issues = @(Find-RegistryIssues)
        $lv.BeginUpdate(); $lv.Items.Clear(); $lv.Groups.Clear(); $lv.ShowGroups = $true
        $counts = @{}
        foreach ($i in $issues) { if ($counts.ContainsKey($i.Cat)) { $counts[$i.Cat]++ } else { $counts[$i.Cat] = 1 } }
        $groups = @{}
        foreach ($c in ($counts.Keys | Sort-Object)) {
            $groups[$c] = New-Object Windows.Forms.ListViewGroup($c, ('{0} ({1})' -f $c, $counts[$c]))
            [void]$lv.Groups.Add($groups[$c])
        }
        foreach ($i in $issues) {
            $li = New-Object Windows.Forms.ListViewItem($i.Item)
            [void]$li.SubItems.Add($i.Path)
            [void]$li.SubItems.Add($i.Cat)
            $li.ToolTipText = ([string]$i.Item + "`n" + [string]$i.Path)
            $li.Tag = $i
            $li.Group = $groups[$i.Cat]
            $li.Checked = $true
            [void]$lv.Items.Add($li)
        }
        $lv.EndUpdate(); Finish-List $lv
        Write-Log ('Registry scan finished: {0} issue(s) found.' -f $issues.Count)
    }
})

$btnRgFix.Add_Click({
    $sel = @($Pg.Registry.List.CheckedItems | ForEach-Object { $_.Tag })
    if ($sel.Count -eq 0) { Show-Msg 'Nothing is selected. Press "Scan for issues" first.'; return }
    $ans = [Windows.Forms.MessageBox]::Show("Fix $($sel.Count) registry issue(s)?`n`nA .reg backup is saved before each change. To undo, open the Backups folder and double-click the .reg file.", 'WinCrow', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    Invoke-Busy {
        if ($chkRgRestore.Checked) { Write-Log 'Creating restore point...'; New-RestorePoint 'WinCrow - before registry cleaning' }
        $bak = Join-Path $RegBackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
        $res = Remove-RegIssues $sel $bak
        $fixed = @($res.Done)
        foreach ($li in @($Pg.Registry.List.Items)) { if ($fixed -contains $li.Tag) { $li.Remove() } }
        Write-Log ('Registry cleaned: {0} fixed, {1} failed. Backup saved in {2}' -f $fixed.Count, $res.Fail, $bak)
    }
})

# ====================================================================== LEFTOVERS PAGE
$btnLoScan   = New-Btn 'Scan' 'primary' 100
$btnLoRun    = New-Btn 'Remove selected' 'danger' 150
$btnLoAll    = New-Btn 'Select all' 'ghost' 90
$btnLoNone   = New-Btn 'Select none' 'ghost' 100
$btnLoOpenQ  = New-Btn 'Quarantine' 'ghost' 100
$btnLoEmptyQ = New-Btn 'Empty it' 'ghost' 80
$Pg.Leftovers.Bar.Controls.AddRange(@($btnLoScan, $btnLoRun, $btnLoAll, $btnLoNone, $btnLoOpenQ, $btnLoEmptyQ))

$btnLoAll.Add_Click({ foreach ($li in $Pg.Leftovers.List.Items) { $li.Checked = $true } })
$btnLoNone.Add_Click({ foreach ($li in $Pg.Leftovers.List.Items) { $li.Checked = $false } })
$btnLoOpenQ.Add_Click({
    New-Item -ItemType Directory -Path $QuarantineDir -Force | Out-Null
    Start-Process explorer.exe -ArgumentList "`"$QuarantineDir`""
})
$btnLoEmptyQ.Add_Click({
    if (-not (Test-Path -LiteralPath $QuarantineDir)) { Show-Msg 'The quarantine folder is already empty.'; return }
    $sz = Get-DirBytes $QuarantineDir
    $ans = [Windows.Forms.MessageBox]::Show("Permanently delete everything in quarantine ($(Format-Size $sz))?`n`nThis cannot be undone.", 'WinCrow', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Invoke-Busy {
        Get-ChildItem -LiteralPath $QuarantineDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log ('Quarantine emptied. {0} freed.' -f (Format-Size $sz))
    }
})

$btnLoScan.Add_Click({
    Invoke-Busy {
        Write-Log 'Looking for leftovers (this can take a minute)...'
        $lv = $Pg.Leftovers.List
        $found = @(Find-Leftovers)
        $lv.BeginUpdate(); $lv.Items.Clear(); $lv.Groups.Clear(); $lv.ShowGroups = $true
        $counts = @{}
        foreach ($i in $found) { if ($counts.ContainsKey($i.Cat)) { $counts[$i.Cat]++ } else { $counts[$i.Cat] = 1 } }
        $groups = @{}
        foreach ($c in ($counts.Keys | Sort-Object)) {
            $groups[$c] = New-Object Windows.Forms.ListViewGroup($c, ('{0} ({1})' -f $c, $counts[$c]))
            [void]$lv.Groups.Add($groups[$c])
        }
        foreach ($i in $found) {
            $li = New-Object Windows.Forms.ListViewItem($i.Path)
            [void]$li.SubItems.Add($i.Cat)
            [void]$li.SubItems.Add($i.Why)
            $li.ToolTipText = ([string]$i.Path + "`n" + [string]$i.Why)
            $li.Tag = $i
            $li.Group = $groups[$i.Cat]
            $li.Checked = ($i.Kind -ne 'Orphan')
            [void]$lv.Items.Add($li)
        }
        $lv.EndUpdate(); Finish-List $lv
        Write-Log ('Leftover scan finished: {0} item(s). Program folders are un-ticked: check each one before removing.' -f $found.Count)
    }
})

$btnLoRun.Add_Click({
    $sel = @($Pg.Leftovers.List.CheckedItems | ForEach-Object { $_.Tag })
    if ($sel.Count -eq 0) { Show-Msg 'Nothing is selected. Press "Scan" first.'; return }
    $orph = @($sel | Where-Object { $_.Kind -eq 'Orphan' }).Count
    $msg = "Remove $($sel.Count) item(s)?"
    if ($orph -gt 0) { $msg += "`n`n$orph program folder(s) are moved to WinCrow's quarantine folder, not deleted, so you can put them back." }
    $msg += "`n`nBroken shortcuts and empty folders are deleted."
    $ans = [Windows.Forms.MessageBox]::Show($msg, 'WinCrow', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    Invoke-Busy {
        $done = @(Remove-Leftovers $sel)
        foreach ($li in @($Pg.Leftovers.List.Items)) { if ($done -contains $li.Tag) { $li.Remove() } }
        Write-Log ('Leftovers: {0} of {1} removed.' -f $done.Count, $sel.Count)
    }
})

# ====================================================================== UPDATE UI
function Show-UpdateDialog($rel) {
    $notes = ([string]$rel.Notes -replace '\r', '').Trim()
    if ($notes.Length -gt 700) { $notes = $notes.Substring(0, 700) + '...' }
    $msg = "WinCrow $($rel.Version) is available. You have $AppVersion.`n`n"
    if ($notes) { $msg += "What is new:`n$notes`n`n" }
    $msg += "Yes = download and install now`nNo = open the GitHub page`nCancel = not now"
    $ans = [Windows.Forms.MessageBox]::Show($msg, 'WinCrow update', 'YesNoCancel', 'Information')
    if ($ans -eq 'Yes') {
        Invoke-Busy {
            try { Install-Update $rel }
            catch {
                Write-Log ('Update failed: ' + $_.Exception.Message) 'ERROR'
                Show-Msg ("The update could not be installed:`n`n" + $_.Exception.Message) 'Warning'
            }
        }
    } elseif ($ans -eq 'No') {
        try { Start-Process $rel.Page } catch { }
    }
}

function Show-UpdateResult($rel, [bool]$Manual) {
    switch ($rel.State) {
        'Newer' {
            $script:PendingUpdate = $rel
            $btnUpdate.Text = 'Update ' + $rel.Tag
            $btnUpdate.Visible = $true
            $lblUpdate.Text = "Version $($rel.Version) is available. You have $AppVersion."
            Write-Log ('Update available: ' + $rel.Tag)
            if ($Manual) { Show-UpdateDialog $rel }
        }
        'Current' {
            $lblUpdate.Text = "You are up to date (version $AppVersion)."
            if ($Manual) { Show-Msg "You are up to date.`n`nWinCrow $AppVersion is the latest version." }
        }
        'NoVersion' {
            $lblUpdate.Text = 'No version.txt was found on GitHub yet, so there is nothing to compare with.'
            if ($Manual) { Show-Msg 'No version.txt was found in the main branch of the GitHub project yet, so there is nothing to update to.' }
        }
        default {
            $lblUpdate.Text = 'Could not check for updates.'
            Write-Log ('Update check failed: ' + $rel.Msg) 'WARN'
            if ($Manual) { Show-Msg ("Could not check for updates:`n`n" + $rel.Msg) 'Warning' }
        }
    }
}

$btnUpdate.Add_Click({ if ($script:PendingUpdate) { Show-UpdateDialog $script:PendingUpdate } })

$btnCheckUpd.Add_Click({
    $script:ManualRel = $null
    Invoke-Busy {
        Write-Log 'Checking GitHub for updates...'
        $script:ManualRel = Read-Version (& $UpdateFetch $VersionUrl $UserAgent)
    }
    if ($script:ManualRel) { Show-UpdateResult $script:ManualRel $true }
})
$btnRepo.Add_Click({ try { Start-Process $RepoUrl } catch { } })

# Silent check at startup, in a background job so the window never waits on the network
function Start-AutoUpdateCheck {
    if (-not $script:Settings.AutoUpdate) { return }
    try {
        $script:UpdJob = Start-Job -ScriptBlock $UpdateFetch -ArgumentList $VersionUrl, $UserAgent
        $script:UpdTimer = New-Object Windows.Forms.Timer
        $script:UpdTimer.Interval = 600
        $script:UpdTimer.Add_Tick({
            if ($script:UpdJob.State -in @('Completed', 'Failed', 'Stopped')) {
                $script:UpdTimer.Stop()
                try {
                    $res = Receive-Job -Job $script:UpdJob -ErrorAction Stop | Select-Object -Last 1
                    Show-UpdateResult (Read-Version $res) $false
                } catch { }
                Remove-Job -Job $script:UpdJob -Force -ErrorAction SilentlyContinue
            }
        })
        $script:UpdTimer.Start()
    } catch { }
}

$form.Add_FormClosing({
    try { if ($script:UpdTimer) { $script:UpdTimer.Stop() } } catch { }
    try { Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue } catch { }
})

# ====================================================================== THEME SWITCHING
function Set-TitleBar {
    try {
        $v = $(if ($script:Theme -eq 'Dark') { 1 } else { 0 })
        [void][WinCrow.Dwm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$v, 4)
        [void][WinCrow.Dwm]::DwmSetWindowAttribute($form.Handle, 19, [ref]$v, 4)
    } catch { }
}

function Apply-Theme([string]$Name) {
    $script:Theme = $Name
    $script:C = $Themes[$Name]
    $form.SuspendLayout()
    $form.BackColor = $C.Bg; $form.ForeColor = $C.Text
    foreach ($ctl in @($script:Roles.Keys)) {
        $role = $script:Roles[$ctl]
        switch -Wildcard ($role) {
            'bg'     { $ctl.BackColor = $C.Bg; $ctl.ForeColor = $C.Text }
            'panel'  { $ctl.BackColor = $C.Panel }
            'title'  { $ctl.ForeColor = $C.Text }
            'sub'    { $ctl.ForeColor = $C.Dim }
            'accent' { $ctl.ForeColor = $C.Accent }
            'list'   { $ctl.BackColor = $C.Panel; $ctl.ForeColor = $C.Text }
            'log'    { $ctl.BackColor = $C.LogBg; $ctl.ForeColor = $C.LogFg }
            'nav'    { $ctl.FlatAppearance.MouseOverBackColor = $C.Hover }
            'link'   { $ctl.LinkColor = $C.Accent; $ctl.ActiveLinkColor = $C.Accent2; $ctl.VisitedLinkColor = $C.Accent }
            'btn:*'  { Style-Btn $ctl $role.Substring(4) }
        }
    }
    Show-Page $script:CurPage
    $btnTheme.Text = $(if ($Name -eq 'Dark') { 'Light theme' } else { 'Dark theme' })
    $form.ResumeLayout()
    $form.Invalidate($true)
    Set-TitleBar
}

$btnTheme.Add_Click({
    $next = $(if ($script:Theme -eq 'Dark') { 'Light' } else { 'Dark' })
    Apply-Theme $next
    $script:Settings.Theme = $next
    Save-Settings
    Write-Log "$next theme on."
})

# ====================================================================== GO
$form.Add_Shown({
    $form.Activate()
    Set-TitleBar
    $wa = [Windows.Forms.Screen]::FromControl($form).WorkingArea
    if ($form.Width -gt $wa.Width -or $form.Height -gt $wa.Height) {
        $form.MinimumSize = New-Object Drawing.Size([Math]::Min($form.MinimumSize.Width, $wa.Width), [Math]::Min($form.MinimumSize.Height, $wa.Height))
        $form.Size = New-Object Drawing.Size([Math]::Min($form.Width, $wa.Width), [Math]::Min($form.Height, $wa.Height))
        $form.Location = New-Object Drawing.Point($wa.Left, $wa.Top)
    }
    Write-Log "WinCrow $AppVersion - $OsCaption (build $Build)"
    if ($FirstRun) { Write-Log "First launch: installed to $InstallDir and added to the Start menu. Next time, open WinCrow from Start." }
    Invoke-Busy { Load-Debloat; Load-Cleaner; Load-Startup; Load-Tweaks }
    Start-AutoUpdateCheck
})

Apply-Theme $script:Theme
Show-Page 'Debloat'
try {
    [void]$form.ShowDialog()
} catch {
    try { Add-Content -LiteralPath (Join-Path $LogDir 'crash.log') -Value ("{0}  {1}" -f (Get-Date), $_ | Out-String) } catch { }
    Show-Msg ("WinCrow hit an error:`n`n" + $_.Exception.Message) 'Error'
}
