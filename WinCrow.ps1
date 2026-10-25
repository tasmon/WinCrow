<#
.SYNOPSIS
    WinCrow - scavenge the bloat. Leave only bones.

.DESCRIPTION
    * Removes bloated Store apps (pick from a list)
    * Enables / disables startup apps (pick from a list)
    * 40+ privacy, performance and interface tweaks, each one reversible
    * Dark and light themes
    * First launch installs itself to "C:\Program Files\WinCrow" and adds a
      Start menu shortcut. After that, launch it from the Start menu.

    Easiest: run "WinCrow Installer.cmd".
    Or:      powershell -ExecutionPolicy Bypass -File .\WinCrow.ps1
    Remove:  Start menu app -> About -> Uninstall WinCrow   (or)   .\WinCrow.ps1 -Uninstall

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
$AppVersion   = '1.1.0'
$DevName      = 'Tasmon Islam'
$DevEmail     = 'tasmon@outlook.com'
$InstallDir   = Join-Path $env:ProgramFiles $AppName
$LogDir       = Join-Path $InstallDir 'Logs'
$IconPath     = Join-Path $InstallDir 'WinCrow.ico'
$SettingsPath = Join-Path $InstallDir 'settings.json'
$ShortcutPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\WinCrow.lnk'
$PsExe        = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ------------------------------------------------------------------ elevation
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Must run as admin in Windows PowerShell 5.1 (the Appx module needs it)
if (-not (Test-Admin) -or $PSVersionTable.PSEdition -eq 'Core') {
    if (-not $PSCommandPath) { Write-Warning 'Save WinCrow as a .ps1 file and run it from there.'; return }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    if ($Uninstall) { $argList += '-Uninstall' }
    if ($FirstRun)  { $argList += '-FirstRun' }
    try { Start-Process -FilePath $PsExe -Verb RunAs -ArgumentList $argList } catch { }
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

# ------------------------------------------------------------------ helpers
function Hex([string]$x) { [Drawing.ColorTranslator]::FromHtml($x) }

function Show-Msg([string]$Text, [string]$Icon = 'Information') {
    [void][Windows.Forms.MessageBox]::Show($Text, 'WinCrow', 'OK', $Icon)
}

function Pt([double]$x, [double]$y) { New-Object Drawing.PointF([single]$x, [single]$y) }

# The crow mark: a spiky black crow with a red eye on a blood-red disc (100x100 box)
function New-CrowBitmap([int]$Size) {
    $bmp = New-Object Drawing.Bitmap $Size, $Size
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([Drawing.Color]::Transparent)
    $g.ScaleTransform($Size / 100.0, $Size / 100.0)

    # blood-red disc
    $rect = New-Object Drawing.RectangleF 0, 0, 100, 100
    $disc = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (Hex '#E11D2E'), (Hex '#4A060C'), 55.0
    $g.FillEllipse($disc, 1, 1, 97, 97)
    $ringPen = New-Object Drawing.Pen (Hex '#0A0A0C'), 2.2
    $g.DrawEllipse($ringPen, 4, 4, 91, 91)

    # crow (scaled into the disc)
    $g.TranslateTransform(14, 14)
    $g.ScaleTransform(0.72, 0.72)
    $black = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, (Hex '#2E3038'), (Hex '#030304'), 70.0
    $edge  = New-Object Drawing.Pen (Hex '#000000'), 1.2
    $edge.LineJoin = 'Miter'
    $shapes = @(
        @((Pt 52 44), (Pt 0 8),   (Pt 28 46)),     # wing blades
        @((Pt 50 50), (Pt -2 34), (Pt 30 54)),
        @((Pt 48 56), (Pt 4 62),  (Pt 32 63)),
        @((Pt 40 66), (Pt 18 99), (Pt 52 73)),     # tail blades
        @((Pt 48 68), (Pt 38 101),(Pt 62 75)),
        @((Pt 54 44), (Pt 60 26), (Pt 82 34), (Pt 76 58))   # neck
    )
    foreach ($s in $shapes) {
        $pts = [Drawing.PointF[]]$s
        $g.FillPolygon($black, $pts)
        $g.DrawPolygon($edge, $pts)
    }
    $g.FillEllipse($black, 36, 40, 40, 34)    # body
    $g.FillEllipse($black, 58, 12, 26, 26)    # head
    # hooked beak
    $beak = New-Object Drawing.SolidBrush (Hex '#25262D')
    $g.FillPolygon($beak, [Drawing.PointF[]]@((Pt 81 19), (Pt 99 31), (Pt 91 34), (Pt 97 48), (Pt 82 39)))
    $hl = New-Object Drawing.Pen (Hex '#6B6E7A'), 1
    $g.DrawLine($hl, 82, 20, 98, 31)
    # glowing red eye
    $glow = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(90, 255, 40, 40))
    $g.FillEllipse($glow, 63, 15, 19, 17)
    $eye = New-Object Drawing.SolidBrush (Hex '#FF2D2D')
    $g.FillPolygon($eye, [Drawing.PointF[]]@((Pt 69 20), (Pt 79 22), (Pt 70 26)))
    # talons
    $leg = New-Object Drawing.Pen (Hex '#0A0A0C'), 3
    $leg.StartCap = 'Round'; $leg.EndCap = 'Round'
    $g.DrawLine($leg, 52, 72, 50, 90); $g.DrawLine($leg, 62, 70, 66, 90)
    $g.DrawLine($leg, 42, 91, 52, 89); $g.DrawLine($leg, 58, 92, 70, 89)

    foreach ($o in @($disc, $ringPen, $black, $edge, $beak, $hl, $glow, $eye, $leg)) { $o.Dispose() }
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

function Install-WinCrow {
    New-Item -ItemType Directory -Path $InstallDir, $LogDir -Force | Out-Null
    $dest = Join-Path $InstallDir 'WinCrow.ps1'
    if ($PSCommandPath -and ($PSCommandPath -ine $dest)) { Copy-Item -LiteralPath $PSCommandPath -Destination $dest -Force }
    Save-CrowIcon $IconPath
    New-WinCrowShortcut
}

function Invoke-Uninstall {
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

function Get-SavedTheme {
    try {
        $s = Get-Content -LiteralPath $SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($s.Theme -in 'Dark', 'Light') { return [string]$s.Theme }
    } catch { }
    return 'Dark'
}
function Save-Theme([string]$Name) {
    try { (@{ Theme = $Name } | ConvertTo-Json) | Set-Content -LiteralPath $SettingsPath -Encoding ASCII } catch { }
}

$script:Theme = Get-SavedTheme
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
            Label = $(if ($rule) { $rule.L } else { $nm })
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
    $b.Text = $Text; $b.Width = $W; $b.Height = 36; $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'
    $b.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
    $b.Margin = New-Object Windows.Forms.Padding(0, 0, 10, 0)
    Style-Btn $b $Kind
    [void](Set-Role $b "btn:$Kind")
    return $b
}

function Fit-Columns($lv) {
    $w = $lv.ClientSize.Width - 6
    $sum = ($lv.Tag | Measure-Object -Sum).Sum
    for ($i = 0; $i -lt $lv.Columns.Count; $i++) { $lv.Columns[$i].Width = [int]($w * $lv.Tag[$i] / $sum) }
}

function New-List([int[]]$Ratio) {
    $lv = New-Object Windows.Forms.ListView
    $lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true
    $lv.HeaderStyle = 'None'; $lv.BorderStyle = 'None'; $lv.MultiSelect = $false; $lv.ShowGroups = $true
    $lv.BackColor = $C.Panel; $lv.ForeColor = $C.Text
    $lv.Font = New-Object Drawing.Font('Segoe UI', 10)
    $lv.Tag = $Ratio
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
    $t.Font = New-Object Drawing.Font('Segoe UI Semibold', 15); $t.Location = New-Object Drawing.Point(20, 8)
    [void](Set-Role $t 'title')
    $s = New-Object Windows.Forms.Label
    $s.Text = $Sub; $s.AutoSize = $true; $s.ForeColor = $C.Dim
    $s.Font = New-Object Drawing.Font('Segoe UI', 9.5); $s.Location = New-Object Drawing.Point(22, 40)
    [void](Set-Role $s 'sub')
    $cap.Controls.AddRange(@($t, $s))

    $bar = New-Object Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Bottom'; $bar.Height = 60; $bar.BackColor = $C.Bg; $bar.WrapContents = $false
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
$form.MinimumSize = New-Object Drawing.Size(960, 620)
$form.BackColor = $C.Bg; $form.ForeColor = $C.Text
$form.Font = New-Object Drawing.Font('Segoe UI', 9.5)
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
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.TextRenderingHint = 'ClearTypeGridFit'
    $g.DrawImage($script:LogoBmp, 16, 9, 58, 58)
    $f1 = New-Object Drawing.Font('Segoe UI Black', 21)
    $f2 = New-Object Drawing.Font('Segoe UI', 9.5)
    $b1 = New-Object Drawing.SolidBrush $C.Text
    $b2 = New-Object Drawing.SolidBrush $C.Dim
    $b3 = New-Object Drawing.SolidBrush $C.Accent
    $g.DrawString('Win', $f1, $b1, 82, 6)
    $wWin = $g.MeasureString('Win', $f1).Width - 14
    $g.DrawString('Crow', $f1, $b3, (82 + $wWin), 6)
    $g.DrawString('Scavenge the bloat. Leave only bones.', $f2, $b2, 86, 48)
    $r = New-Object Drawing.Rectangle(0, ($s.Height - 3), $s.Width, 3)
    $gb = New-Object Drawing.Drawing2D.LinearGradientBrush $r, $C.Accent, $C.Accent2, 0.0
    $g.FillRectangle($gb, $r)
    foreach ($o in @($f1, $f2, $b1, $b2, $b3, $gb)) { $o.Dispose() }
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
foreach ($n in @(@{ K = 'Debloat'; T = '   Debloat' }, @{ K = 'Startup'; T = '   Startup apps' }, @{ K = 'Tweaks'; T = '   Tweaks' }, @{ K = 'About'; T = '   About' })) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $n.T; $b.Tag = $n.K; $b.TextAlign = 'MiddleLeft'; $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'
    $b.FlatAppearance.BorderSize = 0
    $b.Font = New-Object Drawing.Font('Segoe UI Semibold', 11)
    $b.Size = New-Object Drawing.Size(190, 48)
    $b.Location = New-Object Drawing.Point(0, (16 + $i * 50))
    $b.Add_Click({ param($s, $e) Show-Page $s.Tag })
    [void](Set-Role $b 'nav')
    $nav.Controls.Add($b)
    $NavBtns[$n.K] = $b
    $i++
}

$btnTheme = New-Btn 'Light theme' 'ghost' 160
$btnTheme.Margin = New-Object Windows.Forms.Padding(0)
$btnTheme.Location = New-Object Drawing.Point(15, 300)
$nav.Controls.Add($btnTheme)
$nav.Add_Resize({ $btnTheme.Location = New-Object Drawing.Point(15, ($nav.ClientSize.Height - 56)) })

# --- main area
$main = New-Object Windows.Forms.Panel
$main.Dock = 'Fill'; $main.BackColor = $C.Bg
[void](Set-Role $main 'bg')

$Pg.Debloat = New-Page 'Debloat' 'Tick the apps you want gone. Recommended ones are pre-ticked. Removal is for all users and also stops them returning on new accounts.' @(45, 55)
$Pg.Startup = New-Page 'Startup apps' 'Ticked = starts with Windows. Untick the ones you want to stop, then press Apply. Nothing is deleted - you can turn them back on here.' @(30, 18, 52)
$Pg.Tweaks  = New-Page 'Tweaks' 'Ticked = tweak is active. Tick to apply, untick to restore the Windows default.' @(38, 62)
$Pg.About   = New-Page 'About' '' $null
foreach ($k in 'Debloat', 'Startup', 'Tweaks', 'About') { $main.Controls.Add($Pg[$k].Page) }

$script:Progress = New-Object Windows.Forms.ProgressBar
$script:Progress.Dock = 'Bottom'; $script:Progress.Height = 6; $script:Progress.Style = 'Continuous'
$main.Controls.Add($script:Progress)

$script:LogBox = New-Object Windows.Forms.TextBox
$script:LogBox.Dock = 'Bottom'; $script:LogBox.Height = 120; $script:LogBox.Multiline = $true; $script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = 'Vertical'; $script:LogBox.BorderStyle = 'None'
$script:LogBox.BackColor = $C.LogBg; $script:LogBox.ForeColor = $C.LogFg
$script:LogBox.Font = New-Object Drawing.Font('Consolas', 9)
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
    Fit-Columns $lv
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
    $lv.EndUpdate(); Fit-Columns $lv
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
        $it.Tag = @{ T = $t; Was = $on }
        $it.Group = $groups[$t.Cat]
        $it.Checked = $on
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate(); Fit-Columns $lv
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
$about = New-Object Windows.Forms.Panel
$about.Dock = 'Fill'; $about.BackColor = $C.Bg
[void](Set-Role $about 'bg')

function New-AboutLabel([string]$Text, [string]$Font, [double]$Size, [string]$Role, [int]$X, [int]$Y, [int]$W = 0, [int]$H = 0) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $Text; $l.Font = New-Object Drawing.Font($Font, $Size); $l.Location = New-Object Drawing.Point($X, $Y)
    if ($W -gt 0) { $l.AutoSize = $false; $l.Size = New-Object Drawing.Size($W, $H) } else { $l.AutoSize = $true }
    $l.ForeColor = $C.Text
    [void](Set-Role $l $Role)
    $about.Controls.Add($l)
    return $l
}

[void](New-AboutLabel "WinCrow $AppVersion" 'Segoe UI Black' 20 'title' 20 6)
[void](New-AboutLabel 'Scavenge the bloat. Leave only bones.' 'Segoe UI' 10.5 'accent' 23 46)
[void](New-AboutLabel ('WinCrow strips Windows down to what you actually use: it removes bloated apps, controls what starts with Windows ' +
                       'and flips the privacy, performance and interface switches that matter. Every change can be reversed from this window.') 'Segoe UI' 10.5 'title' 22 84 680 56)
[void](New-AboutLabel 'DEVELOPER' 'Segoe UI Semibold' 9 'accent' 23 162)
[void](New-AboutLabel $DevName 'Segoe UI Semibold' 16 'title' 21 182)
$lnk = New-Object Windows.Forms.LinkLabel
$lnk.Text = $DevEmail; $lnk.AutoSize = $true; $lnk.Location = New-Object Drawing.Point(23, 220)
$lnk.Font = New-Object Drawing.Font('Segoe UI', 10.5); $lnk.Cursor = 'Hand'
$lnk.LinkColor = $C.Accent; $lnk.ActiveLinkColor = $C.Accent2; $lnk.VisitedLinkColor = $C.Accent; $lnk.LinkBehavior = 'HoverUnderline'
$lnk.Add_Click({ try { Start-Process "mailto:$DevEmail" } catch { } })
[void](Set-Role $lnk 'link')
$about.Controls.Add($lnk)
[void](New-AboutLabel ("Detected:    $OsCaption (build $Build)`r`nInstalled:   $InstallDir`r`nLogs:           $LogDir") 'Consolas' 9.5 'sub' 23 268 760 70)
$Pg.About.Page.Controls.Add($about)
$about.BringToFront()

$btnOpenLogs  = New-Btn 'Open logs folder' 'ghost' 150
$btnUninstall = New-Btn 'Uninstall WinCrow' 'danger' 160
$Pg.About.Bar.Controls.AddRange(@($btnOpenLogs, $btnUninstall))
$btnOpenLogs.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$LogDir`"" })
$btnUninstall.Add_Click({
    $ans = [Windows.Forms.MessageBox]::Show("Remove WinCrow, its Start menu shortcut and its folder?`n`n(Your Windows settings stay as they are.)", 'WinCrow', 'YesNo', 'Question')
    if ($ans -eq 'Yes') { Invoke-Uninstall; $form.Close() }
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
    Save-Theme $next
    Write-Log "$next theme on."
})

# ====================================================================== GO
$form.Add_Shown({
    $form.Activate()
    Set-TitleBar
    Write-Log "WinCrow $AppVersion - $OsCaption (build $Build)"
    if ($FirstRun) { Write-Log "First launch: installed to $InstallDir and added to the Start menu. Next time, open WinCrow from Start." }
    Invoke-Busy { Load-Debloat; Load-Startup; Load-Tweaks }
})

Apply-Theme $script:Theme
Show-Page 'Debloat'
try {
    [void]$form.ShowDialog()
} catch {
    try { Add-Content -LiteralPath (Join-Path $LogDir 'crash.log') -Value ("{0}  {1}" -f (Get-Date), $_ | Out-String) } catch { }
    Show-Msg ("WinCrow hit an error:`n`n" + $_.Exception.Message) 'Error'
}
