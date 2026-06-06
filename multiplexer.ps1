# ASSEMBLIES
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# SINGLE INSTANCE MUTEX
$createdNew = $false
$global:appMutex = New-Object System.Threading.Mutex($true, "Global\TorMultiplexer_SingleInstance", [ref]$createdNew)
if (-not $createdNew) {
    [System.Windows.Forms.MessageBox]::Show("Tor Multiplexer is already running!", "Already Running", 0, 48)
    [Environment]::Exit(0)
}

[System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::Default
[System.AppDomain]::CurrentDomain.add_ProcessExit({
    try {
        if ($null -ne $App) {
            Stop-AllEngines -isClosing $true
        }
        Disable-SystemProxy
    } catch {}
})

#  LEGACY UPDATE STUBS
$global:currentVersion       = "5.2.3"
$global:forceManualUpdate    = $true
$global:minAutoUpdateVersion = "5.2.1"

# SYSTEM PROXY REFRESH API
if (-not ("Win32.WinInet" -as [type])) {
    Add-Type -MemberDefinition @'
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
'@ -Name 'WinInet' -Namespace 'Win32' -PassThru | Out-Null
}

#  CENTRAL APP STATE
$App = [ordered]@{
    # Persisted + path config
    Config = [ordered]@{
        currentVersion       = "5.2.3"
        minAutoUpdateVersion = "5.2.1"
        repoRawUrl           = "https://raw.githubusercontent.com/RichTiTAN/Tor-Multiplexer/main/multiplexer.ps1"
        repoReleaseUrl       = "https://github.com/RichTiTAN/Tor-Multiplexer/releases"
        baseDir              = ""
        scriptPath           = ""
        cfgFile              = ""
        xrayDir              = ""
        haPath               = ""
        sbDir                = ""
        # user preferences (saved to JSON)
        autoStart            = $true
        launchOnBoot         = $false
        debugMode            = $false  
        lastConfig           = "Optimized"
        lastBridge           = "meek_lite"
        lastCount            = "6"
        lastXrayMode         = "Proxy Mode"
        lastManualSplit      = ""
        lastAppSplit         = ""
        lastBlockSplit       = ""
        enableDirect         = $false
        customBridgeLine     = ""
        v2rayChainJson       = ""
        enableV2rayChain     = $false
        outboundProxyAddress = ""
        outboundProxyPort    = ""
        outboundProxyType    = "SOCKS5"
        enableOutboundProxy  = $false
        outboundProxyUser    = ""
        outboundProxyPass    = ""
        enableOutboundAuth   = $false
        enableUpstreamDoh    = $false
        upstreamDohUrl       = "https://cloudflare-dns.com/dns-query"
        customExitCountry    = "us"
        minimizeToTray       = $false
        enableAdBlock        = $false

        # expert config defaults
        expertHardwareAccel       = $false
        expertStrictNodes         = $false
        expertFascistFirewall     = $false 
        expertCircuitBuildTimeout = ""
        expertKeepalivePeriod     = ""
        expertNewCircuitPeriod    = ""
        expertMaxCircuitDirtiness = ""
        expertNumEntryGuards      = ""
        expertEntryNodes          = ""
        expertExitNodes           = ""
        expertExcludeNodes        = ""
        expertExcludeExitNodes    = ""
        expertCustomTorrc         = ""
    }
    # Volatile connection / UI state
    State = [ordered]@{
        isFirstLaunch     = $true
        isConnected       = $false
        isEngineRunning   = $false
        abortBoot         = $false
        isGeoTracing      = $false
        isAdvancedOpen    = $false
        isLogsOpen        = $false
        ignoreComboChange = $false
        appInitialized    = $false
        previousBridge    = "meek_lite"
        previousConfig    = "Optimized"
        lanIp             = "UNKNOWN"
        sessionStartTime  = $null
        lastTotalBytes    = 0
        sessionDataBytes  = 0
        speedSamples      = @(0, 0, 0, 0, 0)
        tempProxyType     = "SOCKS5"
    }
    # Process handles, timers, async clients
    Runtime = [ordered]@{
        cmdDebugPid       = $null
        cmdDebugPid2      = $null
        xrayDohPid        = $null
        xrayRestartTimer  = $null
        isFetchingStats   = $false
        geoWebClient      = $null
        saveDebounceTimer = $null
        statsTimer        = $null
        sessionClockTimer = $null
        bootstrapTimer    = $null
        wavePhysicsTimer  = $null
        waveHoldTimer     = $null
        ringTimer         = $null
        ringT             = 643.0
        ringSpeed         = 0.0
        ringTargetSpeed   = 0.0
        ringState         = "Idle"
        pingTimer         = $null
        hideAdvTimer      = $null
        hideLogTimer      = $null
        geoSw             = $null
        sysTrayIcon       = $null
        updateDlClient    = $null
        torPids           = @($null,$null,$null,$null,$null,$null,$null,$null)
        staggerTimer      = $null
        staggerQueue      = $null
        bridgeWebClient   = $null
        logTimer          = $null
        logClearTimer     = $null
        pollDeadline      = $null
        pollSelCount      = $null
        pollMode          = $null
        pollWinStyle      = $null
        pollSelBridge     = $null
    }
    # WPF element references + pre-built brushes
    UI = [ordered]@{
        form                 = $null
        brGreen              = $null
        brGray               = $null
        brRed                = $null
        brWhite              = $null
        brTransparent        = $null
        brActiveRouting      = $null
        brInactiveRouting    = $null
        ringShineEllipse     = $null
        ringShineColor       = $null
        ringCanvas           = $null
        btnConnectedBg       = $null
        comboBridge          = $null
        comboConfig          = $null
        comboCount           = $null
        btnAction            = $null
        btnActionMainText    = $null
        btnActionSubText     = $null
        btnProxyMode         = $null
        btnVpnMode           = $null
        vpnToolTip           = $null
        btnClearProxy        = $null
        btnAutoStartMain     = $null
        btnAdvMain           = $null
        lblSessionTime       = $null
        btnDirectLbl         = $null
        btnDirectTog         = $null
        btnV2rayLbl          = $null
        btnV2rayTog          = $null
        btnOutboundLbl       = $null
        btnOutboundTog       = $null
        btnDohLbl            = $null
        btnDohTog            = $null
        btnAdBlockLbl        = $null
        btnAdBlockTog        = $null
        btnBootLbl           = $null
        btnBootTog           = $null
        btnDebugLbl          = $null
        btnDebugTog          = $null
        btnTrayLbl           = $null
        btnTrayTog           = $null
        btnLogsLbl           = $null
        btnLogsTog           = $null
        btnDesktop           = $null
        AdvancedCanvas       = $null
        AdvancedBorder       = $null
        LogsCanvas           = $null
        logBorder            = $null
        txtXrayLogs          = $null
        btnCloseLogs         = $null
        lblTorTitle          = $null
        logSeparator         = $null
        lblConnTitle         = $null
        lblTor1              = $null
        lblTor2              = $null
        lblTor3              = $null
        lblTor4              = $null
        lblTor5              = $null
        lblTor6              = $null
        lblTor7              = $null
        lblTor8              = $null
        UnifiedPanel         = $null
        lblSocksTitle        = $null
        lblSocksDataIPs      = $null
        lblSocksDataTags     = $null
        lblStatsTitle        = $null
        lblStatsData         = $null
        lblGeoData           = $null
        btnStatsPanel        = $null
        lblTitleText         = $null
        btnTitleUpdate       = $null
        btnMinimize          = $null
        btnClose             = $null
        splashOverlay        = $null
        borderClip           = $null
        windowOutline        = $null
    }
}

# PATH SETUP
$exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ($exePath -match 'powershell\.exe$|pwsh\.exe$|powershell_ise\.exe$') {
    $App.Config.baseDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($App.Config.baseDir)) {
        $App.Config.baseDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
    }
} else {
    $App.Config.baseDir = Split-Path -Parent -Path $exePath
}

if ([string]::IsNullOrEmpty($App.Config.baseDir) -or -not (Test-Path $App.Config.baseDir)) { 
    $App.Config.baseDir = Get-Location 
}
Set-Location -LiteralPath $App.Config.baseDir

function Get-AppPath {
    param([string]$Path)
    Join-Path $App.Config.baseDir $Path
}

$App.Config.scriptPath = $PSCommandPath
if ([string]::IsNullOrEmpty($App.Config.scriptPath)) { $App.Config.scriptPath = Get-AppPath "multiplexer.ps1" }
$App.Config.cfgFile    = Get-AppPath "Data\multiplexer_settings.json"
$App.Config.xrayDir    = Get-AppPath "Data\Xray"
$App.Config.haPath     = Get-AppPath "Data\HAproxy"
$App.Config.sbDir      = Get-AppPath "Data\sing_box"

#  LOAD SAVED SETTINGS
if (Test-Path $App.Config.cfgFile) {
    $App.State.isFirstLaunch = $false
    try {
        $s = Get-Content $App.Config.cfgFile -Raw | ConvertFrom-Json
        if ($null -ne $s.AutoStart)    { $App.Config.autoStart    = [bool]$s.AutoStart }
        if ($null -ne $s.LaunchOnBoot) { $App.Config.launchOnBoot = [bool]$s.LaunchOnBoot }
        if ($null -ne $s.IsLogsOpen)   { $App.State.isLogsOpen    = [bool]$s.IsLogsOpen }

        $cfgMap = @{
            "LastConfig"                = "lastConfig"
            "SelectedBridge"            = "lastBridge"
            "InstanceCount"             = "lastCount"
            "XrayMode"                  = "lastXrayMode"
            "ManualSplit"               = "lastManualSplit"
            "AppSplit"                  = "lastAppSplit"
            "BlockSplit"                = "lastBlockSplit"
            "EnableDirect"              = "enableDirect"
            "CustomBridgeLine"          = "customBridgeLine"
            "V2rayChainJson"            = "v2rayChainJson"
            "EnableV2rayChain"          = "enableV2rayChain"
            "EnableOutboundProxy"       = "enableOutboundProxy"
            "OutboundProxyAddress"      = "outboundProxyAddress"
            "OutboundProxyPort"         = "outboundProxyPort"
            "OutboundProxyType"         = "outboundProxyType"
            "OutboundProxyUser"         = "outboundProxyUser"
            "OutboundProxyPass"         = "outboundProxyPass"
            "EnableOutboundAuth"        = "enableOutboundAuth"
            "EnableUpstreamDoh"         = "enableUpstreamDoh"
            "UpstreamDohUrl"            = "upstreamDohUrl"
            "CustomExitCountry"         = "customExitCountry"
            "MinimizeToTray"            = "minimizeToTray"
            "EnableAdBlock"             = "enableAdBlock"
            "DebugMode"                 = "debugMode"   
            "ExpertHardwareAccel"       = "expertHardwareAccel"
            "ExpertStrictNodes"         = "expertStrictNodes"
            "ExpertFascistFirewall"     = "expertFascistFirewall"
            "ExpertCircuitBuildTimeout" = "expertCircuitBuildTimeout"
            "ExpertKeepalivePeriod"     = "expertKeepalivePeriod"
            "ExpertNewCircuitPeriod"    = "expertNewCircuitPeriod"
            "ExpertMaxCircuitDirtiness" = "expertMaxCircuitDirtiness"
            "ExpertNumEntryGuards"      = "expertNumEntryGuards"
            "ExpertEntryNodes"          = "expertEntryNodes"
            "ExpertExitNodes"           = "expertExitNodes"
            "ExpertExcludeNodes"        = "expertExcludeNodes"
            "ExpertExcludeExitNodes"    = "expertExcludeExitNodes"
            "ExpertCustomTorrc"         = "expertCustomTorrc"
        }

        foreach ($key in $cfgMap.Keys) {
            if ($null -ne $s.$key) { $App.Config[$cfgMap[$key]] = $s.$key }
        }
        if ($App.Config.lastConfig -eq "Stable" -or $App.Config.lastConfig -eq "Fast") {
            $App.Config.lastConfig = "Optimized"
        }
        
        if ($App.Config.lastBridge -eq "snowflake" -and $App.Config.lastXrayMode -eq "VPN Mode") {
            $App.Config.lastXrayMode = "Proxy Mode"
        }
    } catch {
        Write-Host "Config Load Error: $($_.Exception.Message)"
    }
}

#  DIALOG HELPER
function Show-AppDialog {
    param([string]$Title, [int]$Width, [int]$Height, [string]$InnerXaml,
          [scriptblock]$OnLoad, [scriptblock]$OnSave)
    
    $bW = $Width - 30
    $bH = $Height - 54
    $dialogTemplatePath = Get-AppPath "Data\DialogBase.xaml"
    if (-not (Test-Path $dialogTemplatePath)) {
        [System.Windows.Forms.MessageBox]::Show("DialogBase.xaml not found!", "Error", 0, 16)
        return $false
    }
    $xamlTemplate = Get-Content $dialogTemplatePath -Raw
    $xaml = $xamlTemplate.Replace("{Title}", $Title)
    $xaml = $xaml.Replace("{Width}", $Width.ToString())
    $xaml = $xaml.Replace("{Height}", $Height.ToString())
    $xaml = $xaml.Replace("{InnerWidth}", $bW.ToString())
    $xaml = $xaml.Replace("{InnerHeight}", $bH.ToString())
    $xaml = $xaml.Replace("{InnerXaml}", $InnerXaml)

    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    $dlg.Owner = $App.UI.form
    $dlg.Add_MouseLeftButtonDown({
        param($sender, $e)
        try { $dlg.DragMove() } catch {}
    }.GetNewClosure())

    $btnOk = $dlg.FindName("btnOk")
    if ($null -ne $btnOk) {
        $btnOk.Add_Click({
            if ($null -ne $OnSave) {
                $res = & $OnSave $dlg
                if ($res -eq $false) { return }
            }
            $dlg.DialogResult = $true
            $dlg.Close()
        }.GetNewClosure())
    }

    $btnCancel = $dlg.FindName("btnCancel")
    if ($null -ne $btnCancel) {
        $btnCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() }.GetNewClosure())
    }

    $btnCloseDialog = $dlg.FindName("btnCloseDialog")
    if ($null -ne $btnCloseDialog) {
        $btnCloseDialog.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() }.GetNewClosure())
    }

    $dlg.Add_Loaded({ if ($null -ne $OnLoad) { & $OnLoad $dlg } }.GetNewClosure())
    return $dlg.ShowDialog() -eq $true
}

#  LOAD MAIN WINDOW XAML FROM FILE
$xamlPath = Get-AppPath "Data\MainWindow.xaml"
if (-not (Test-Path $xamlPath)) {
    [System.Windows.Forms.MessageBox]::Show("MainWindow.xaml not found at:`n$xamlPath`n`nPlease place MainWindow.xaml in the same folder as this script.", "Missing XAML File", 0, 16)
    [Environment]::Exit(0)
}
$xaml = Get-Content $xamlPath -Raw

$xaml = $xaml -replace 'x:Class="[^"]*"', ''

#  COMPILE XAML
try {
    $App.UI.form = [Windows.Markup.XamlReader]::Parse($xaml)
    if (Test-Path (Get-AppPath "icon.ico")) {
        $App.UI.form.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([uri](Get-AppPath "icon.ico"))
    }
} catch {
    [System.Windows.Forms.MessageBox]::Show("App failed to compile the layout window.`n`nError: $($_.Exception.Message)", "Launch Crash Debugger", 0, 16)
    [Environment]::Exit(0)
}

#  MAP WPF NAMED ELEMENTS
$_names = @(
    "comboBridge","comboConfig","comboCount",
    "btnAction","btnActionMainText","btnActionSubText",
    "ringCanvas","loadingScannerBar","scannerTrans","scannerStop1","scannerStop2","scannerStop3",
    "btnProxyMode","btnVpnMode","vpnToolTip","btnClearProxy",
    "btnAutoStartMain","btnAdvMain","lblSessionTime",
    "btnDirectLbl","btnDirectTog","btnV2rayLbl","btnV2rayTog",
    "btnOutboundLbl","btnOutboundTog","btnDohLbl","btnDohTog",
    "btnAdBlockLbl","btnAdBlockTog","btnBootLbl","btnBootTog",
    "btnDebugLbl","btnDebugTog","btnTrayLbl","btnTrayTog",
    "btnLogsLbl","btnLogsTog","btnDesktop",
    "AdvancedCanvas","AdvancedBorder","LogsCanvas","logBorder",
    "txtXrayLogs","btnCloseLogs","lblTorTitle","logSeparator","lblConnTitle",
    "lblTor1","lblTor2","lblTor3","lblTor4","lblTor5","lblTor6","lblTor7","lblTor8",
    "UnifiedPanel","lblSocksTitle","lblSocksDataIPs","lblSocksDataTags",
    "lblStatsTitle","lblStatsData","lblGeoData","btnStatsPanel",
    "lblTitleText","btnTitleUpdate",
    # Custom chrome
    "btnMinimize","btnClose","splashOverlay",
    # Clip + outline
    "borderClip","windowOutline"
)
foreach ($n in $_names) { $App.UI[$n] = $App.UI.form.FindName($n) }
$App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)"

#   CUSTOM CHROME: drag / minimize / close 
$App.UI.form.add_MouseLeftButtonDown({
    param($sender, $e)
    $src = $e.OriginalSource
    $skip = $src -is [System.Windows.Controls.Button] -or
            $src -is [System.Windows.Controls.Primitives.ButtonBase] -or
            $src -is [System.Windows.Controls.ComboBox] -or
            $src -is [System.Windows.Controls.Primitives.ToggleButton] -or
            $src -is [System.Windows.Controls.TextBox] -or
            $src -is [System.Windows.Controls.ScrollViewer] -or
            ($src -is [System.Windows.Controls.TextBlock] -and
                ($src.Name -like "btnAction*" -or $src.Name -like "lbl*"))
    if (-not $skip) {
        try { $App.UI.form.DragMove() } catch {}
    }
})

# Minimize
$App.UI.btnMinimize.Add_Click({
    $App.UI.form.WindowState = [System.Windows.WindowState]::Minimized
})

# Close
$App.UI.btnClose.Add_Click({
    $App.UI.form.Close()
})

#  PRE-BUILD BRUSHES
$_bc = New-Object System.Windows.Media.BrushConverter
$App.UI.bc                = $_bc
$App.UI.brGreen           = $_bc.ConvertFromString("#68D391")
$App.UI.brGray            = $_bc.ConvertFromString("#A0AEC0")
$App.UI.brRed             = $_bc.ConvertFromString("#E53E3E")
$App.UI.brWhite           = $_bc.ConvertFromString("#FFFFFF")
$App.UI.brDarkRed         = $_bc.ConvertFromString("#8B4A4A") 
$App.UI.brDarkGray        = $_bc.ConvertFromString("#4A5568") 
$App.UI.brOrange          = $_bc.ConvertFromString("#F6AD55")  
$App.UI.brTransparent     = [System.Windows.Media.Brushes]::Transparent
$App.UI.brActiveRouting   = $_bc.ConvertFromString("#80646B75")
$App.UI.brInactiveRouting = [System.Windows.Media.Brushes]::Transparent

# DYNAMIC CLIP GEOMETRY 
$_clipGeom = New-Object System.Windows.Media.RectangleGeometry
$_clipGeom.RadiusX = 8.0
$_clipGeom.RadiusY = 8.0
$App.UI.form.add_SizeChanged({
    if ($null -ne $App.UI.borderClip) {
        $_clipGeom.Rect = New-Object System.Windows.Rect(
            0, 0,
            $App.UI.borderClip.ActualWidth,
            $App.UI.borderClip.ActualHeight)
    }
}.GetNewClosure())

#  COMBO BOX POPULATION
function Add-ComboItem($combo, $text, $tag) {
    $cbi = New-Object System.Windows.Controls.ComboBoxItem
    $cbi.Content = $text
    $cbi.Tag     = $tag
    if ($tag -eq "Custom" -or $tag -eq "Expert") {
        $cbi.Add_PreviewMouseLeftButtonDown({
            param($sender, $e)
            $e.Handled = $true
            $combo.IsDropDownOpen = $false
            if ($combo.Name -eq "comboBridge") {
                $App.State.ignoreComboChange = $true
                $combo.SelectedItem = $sender
                DoEvents
                if (-not (Show-CustomBridgeDialog)) {
                    Set-ComboSelectedTag $combo $App.State.previousBridge
                } else { 
                    $App.State.previousBridge = "Custom"
                    $App.Config.lastBridge = "Custom"
                    Update-RoutingToggle
                    if ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
                }
                Save-Config
                $App.State.ignoreComboChange = $false
            } elseif ($combo.Name -eq "comboConfig") {
                $App.State.ignoreComboChange = $true
                $combo.SelectedItem = $sender
                DoEvents
                if ($tag -eq "Custom") {
                    if (-not (Show-ExitNodeDialog)) {
                        Set-ComboSelectedTag $combo $App.State.previousConfig
                    } else { 
                        $App.State.previousConfig = "Custom" 
                        $App.Config.lastConfig = "Custom"
                        if ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
                    }
                } elseif ($tag -eq "Expert") {
                    if (-not (Show-ExpertConfigDialog)) {
                        Set-ComboSelectedTag $combo $App.State.previousConfig
                    } else { 
                        $App.State.previousConfig = "Expert" 
                        $App.Config.lastConfig = "Expert"
                        if ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
                    }
                }
                Save-Config
                $App.State.ignoreComboChange = $false
            }
        }.GetNewClosure())
    }
    $combo.Items.Add($cbi) | Out-Null
}

Add-ComboItem $App.UI.comboBridge "Direct (None)" "Direct (None)"
Add-ComboItem $App.UI.comboBridge "meek_lite"     "meek_lite"
Add-ComboItem $App.UI.comboBridge "obfs4"         "obfs4"
Add-ComboItem $App.UI.comboBridge "snowflake"     "snowflake"
Add-ComboItem $App.UI.comboBridge "Custom"        "Custom"

Add-ComboItem $App.UI.comboConfig "Optimized"     "Optimized"
Add-ComboItem $App.UI.comboConfig "Custom"        "Custom"
Add-ComboItem $App.UI.comboConfig "Expert"        "Expert"

foreach ($n in 1..8) { Add-ComboItem $App.UI.comboCount "$n" "$n" }

function Set-ComboSelectedTag($combo, $tag) {
    foreach ($item in $combo.Items) {
        if ($item.Tag -eq $tag) { $combo.SelectedItem = $item; break }
    }
}

Set-ComboSelectedTag $App.UI.comboBridge $App.Config.lastBridge
Set-ComboSelectedTag $App.UI.comboConfig $App.Config.lastConfig
Set-ComboSelectedTag $App.UI.comboCount  $App.Config.lastCount

$App.State.previousBridge = if ($null -ne $App.UI.comboBridge.SelectedItem) { $App.UI.comboBridge.SelectedItem.Tag } else { "meek_lite" }
$App.State.previousConfig = if ($null -ne $App.UI.comboConfig.SelectedItem) { $App.UI.comboConfig.SelectedItem.Tag } else { "Optimized" }

#  BRIDGE DATA
$bridgeData = @{
    "meek_lite" = @{
        plugin = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec %%LYREBIRD%%"
        lines  = @("Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN")
    }
    "obfs4" = @{
        plugin = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec %%LYREBIRD%%"
        lines  = @(
            "Bridge obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0",
            "Bridge obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0",
            "Bridge obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0",
            "Bridge obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0",
            "Bridge obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=1",
            "Bridge obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1",
            "Bridge obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1"
        )
    }
    "snowflake" = @{
        plugin = "ClientTransportPlugin snowflake exec ../../TorBin/lyrebird.exe"
        lines  = @(
            "Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn",
            "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn"
        )
    }
}

#  WPF HELPERS
function DoEvents {
    if ($null -eq $App.UI.form -or $App.UI.form.Dispatcher.HasShutdownStarted) { return }
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $App.UI.form.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Action]{ $frame.Continue = $false }.GetNewClosure()
    ) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

# Start-ProcessDirect
function Start-ProcessDirect {
    param(
        [string]$FilePath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [bool]$Hidden = $true,
        [bool]$PassThru = $false
    )
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = $FilePath
        if ($Arguments)        { $psi.Arguments         = $Arguments }
        if ($WorkingDirectory) { $psi.WorkingDirectory   = $WorkingDirectory }
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $Hidden
        $psi.WindowStyle     = if ($Hidden) { [System.Diagnostics.ProcessWindowStyle]::Hidden } else { [System.Diagnostics.ProcessWindowStyle]::Normal }
        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($PassThru) { 
            return $proc 
        } elseif ($null -ne $proc) {
            $proc.Dispose() 
        }
    } catch {
        try {
            $ws = if ($Hidden) { "Hidden" } else { "Normal" }
            $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -WindowStyle $ws -PassThru -ErrorAction Stop
            if ($PassThru) { 
                return $proc 
            } elseif ($null -ne $proc) {
                $proc.Dispose() 
            }
        } catch {
            Write-Host "Process launch failed for '$FilePath': $($_.Exception.Message)"
        }
    }
}

function Set-SystemProxy {
    param([bool]$Enable)
    if ($Enable) {
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "ProxyEnable" -Value 1
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "ProxyServer" -Value "127.0.0.1:10818"
    } else {
        Disable-SystemProxy
    }
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Wait-NonBlocking($s) {
    $end = (Get-Date).AddSeconds($s)
    while ((Get-Date) -lt $end) {
        if ($App.State.abortBoot) { return }
        DoEvents
        [System.Threading.Thread]::Sleep(50)
    }
}

function Show-ToastNotification {
    param(
        [string]$Message,
        [string]$Type = "Error"
    )
    
    $delayTimer = New-Object System.Windows.Threading.DispatcherTimer
    $delayTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $delayTimer.add_Tick({
        $delayTimer.Stop()
        
        $toast = New-Object System.Windows.Window
        $toast.WindowStyle = [System.Windows.WindowStyle]::None
        $toast.AllowsTransparency = $true
        $toast.Background = [System.Windows.Media.Brushes]::Transparent
        $toast.ShowInTaskbar = $false
        $toast.Topmost = $true
        $toast.Owner = $App.UI.form
        $toast.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
        $toast.IsHitTestVisible = $false 
        $toast.ShowActivated = $false    

        $border = New-Object System.Windows.Controls.Border
        $border.Background = $App.UI.bc.ConvertFromString("#E62D3748") 
        $border.CornerRadius = New-Object System.Windows.CornerRadius(6)
        
        $border.Padding = New-Object System.Windows.Thickness(15, 5, 15, 5)

        $txt = New-Object System.Windows.Controls.TextBlock
        $txt.Text = $Message
        
        # Color based on Toast Type
        if ($Type -eq "Success") {
            $txt.Foreground = $App.UI.bc.ConvertFromString("#68D391") 
        } else {
            $txt.Foreground = $App.UI.bc.ConvertFromString("#E53E3E")
        }
        
        $txt.FontWeight = [System.Windows.FontWeights]::Bold
        $txt.FontSize = 13
        
        $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $txt.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

        $border.Child = $txt
        $toast.Content = $border

        $toast.Opacity = 0.0
        $toast.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
        $toast.Show()

        $toast.Left = $App.UI.form.Left + ($App.UI.form.ActualWidth / 2) - ($toast.ActualWidth / 2)
        $toast.Top  = $App.UI.form.Top + $App.UI.form.ActualHeight - $toast.ActualHeight - 20

        # Animation
        $durIn   = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(250))
        $animIn  = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, $durIn)

        $durOut  = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(500))
        $animOut = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, $durOut)
        $animOut.BeginTime = [TimeSpan]::FromMilliseconds(2750)

        $animOut.add_Completed({ $toast.Close() }.GetNewClosure())

        $sb = New-Object System.Windows.Media.Animation.Storyboard
        [System.Windows.Media.Animation.Storyboard]::SetTarget($animIn, $toast)
        [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($animIn, (New-Object System.Windows.PropertyPath([System.Windows.Window]::OpacityProperty)))
        [System.Windows.Media.Animation.Storyboard]::SetTarget($animOut, $toast)
        [System.Windows.Media.Animation.Storyboard]::SetTargetProperty($animOut, (New-Object System.Windows.PropertyPath([System.Windows.Window]::OpacityProperty)))

        $sb.Children.Add($animIn)
        $sb.Children.Add($animOut)
        $sb.Begin()
    }.GetNewClosure())
    $delayTimer.Start()
}

function Set-AutoConnectState([bool]$state, [bool]$animate) {
    $btn = $App.UI.btnAutoStartMain
    if ($null -eq $btn) { return }
    $tpl = $btn.Template
    if ($null -eq $tpl) { return }
    $trans1 = $tpl.FindName("transAutoConnect", $btn)
    $trans2 = $tpl.FindName("transOn", $btn)
    $txtOn  = $tpl.FindName("txtOn", $btn)
    $txtAC  = $tpl.FindName("txtAutoConnect", $btn)

    if ($null -eq $trans1 -or $null -eq $trans2 -or $null -eq $txtOn -or $null -eq $txtAC) { return }

    $dur = if ($animate) { New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(300)) } `
           else          { New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(0))   }
    $val1 = if ($state) { -10.0 } else { 0.0 }
    $trans1.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty,
        (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$val1, $dur)))
    $val2 = if ($state) { 44.0  } else { 0.0 }
    $trans2.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty,
        (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$val2, $dur)))
    $val3 = if ($state) { 1.0 } else { 0.0 }
    $txtOn.BeginAnimation([System.Windows.UIElement]::OpacityProperty,
        (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$val3, $dur)))
    $targetCol = if ($state) { [System.Windows.Media.ColorConverter]::ConvertFromString("#E2E8F0") } `
                 else        { [System.Windows.Media.ColorConverter]::ConvertFromString("#A0AEC0") }
    $cloned = if ($txtAC.Foreground -is [System.Windows.Media.SolidColorBrush]) { $txtAC.Foreground.Clone() } `
              else { New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#A0AEC0")) }
    $txtAC.Foreground = $cloned
    $cloned.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty,
        (New-Object System.Windows.Media.Animation.ColorAnimation($targetCol, $dur)))
}

function Set-AdvState([bool]$state) {
    $btn = $App.UI.btnAdvMain
    if ($null -eq $btn) { return }
    $txt = $btn.Template.FindName("txtAdv", $btn)
    if ($null -ne $txt) {
        $txt.Foreground = if ($state) { $App.UI.brWhite } else { $App.UI.brGray }
    }
}

function Set-WpfToggleState($btn, $state, $onText = "Enabled", $offText = "Disabled") {
    $btn.Background = $App.UI.brTransparent
    if ($btn.Name -eq "btnLogsTog") {
        $btn.Foreground = $App.UI.brGray
        $btn.Content    = if ($state) { "HIDE" } else { "SHOW" }
    } elseif ($state) {
        $btn.Content    = $onText.ToUpper()
        $btn.Foreground = $App.UI.brGreen
    } else {
        $btn.Content    = $offText.ToUpper()
        $btn.Foreground = $App.UI.brRed
    }
}

function Update-RoutingToggle {
    $App.UI.btnProxyMode.Background  = $App.UI.brInactiveRouting
    $App.UI.btnProxyMode.Foreground  = $App.UI.brGray
    $App.UI.btnClearProxy.Background = $App.UI.brInactiveRouting
    $App.UI.btnClearProxy.Foreground = $App.UI.brGray

    $activeBridge = if ($App.State.isEngineRunning -and $null -ne $App.Runtime.pollSelBridge) {
    $App.Runtime.pollSelBridge
} else {
    $App.Config.lastBridge
}
$isSnowflake = ($activeBridge -eq "snowflake")
$isLocked    = $isSnowflake

    if ($isLocked) {
        $App.UI.btnVpnMode.Background    = $App.UI.brInactiveRouting
        $App.UI.btnVpnMode.Foreground    = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#4A5568"))
        $App.UI.btnVpnMode.Cursor        = [System.Windows.Input.Cursors]::Arrow
        $App.UI.btnVpnMode.IsEnabled     = $false
        
        if ($isSnowflake) {
            $App.UI.vpnToolTip.Content = "VPN Mode is disabled when using the Snowflake bridge."
        } else {
            $App.UI.vpnToolTip.Content = "VPN Mode cannot be toggled while engines are running."
        }
        
        if ($App.Config.lastXrayMode -eq "VPN Mode") {
            $App.Config.lastXrayMode = "Proxy Mode"
        }
    } else {
        $App.UI.btnVpnMode.Background    = $App.UI.brInactiveRouting
        $App.UI.btnVpnMode.Foreground    = $App.UI.brGray
        $App.UI.btnVpnMode.Cursor        = [System.Windows.Input.Cursors]::Hand
        $App.UI.btnVpnMode.IsEnabled     = $true
        $App.UI.vpnToolTip.Content       = "Route your entire system's network globally through the secure tunnel."
    }
    
    $App.UI.vpnToolTip.Visibility = "Visible"

    switch ($App.Config.lastXrayMode) {
        "Proxy Mode"  { $App.UI.btnProxyMode.Background  = $App.UI.brActiveRouting; $App.UI.btnProxyMode.Foreground  = $App.UI.brWhite }
        "VPN Mode"    { 
            if (-not $isLocked) {
                $App.UI.btnVpnMode.Background = $App.UI.brActiveRouting
                $App.UI.btnVpnMode.Foreground = $App.UI.brWhite 
            }
        }
        "Clear Proxy" { $App.UI.btnClearProxy.Background = $App.UI.brActiveRouting; $App.UI.btnClearProxy.Foreground = $App.UI.brWhite }
    }

    $App.UI.btnDirectLbl.IsEnabled = $true; $App.UI.btnDirectLbl.Opacity = 1.0
    $App.UI.btnDirectTog.IsEnabled = $true; $App.UI.btnDirectTog.Opacity = 1.0
}

function Evaluate-ProxyExclusivity {
    $App.UI.btnOutboundLbl.IsEnabled = $true; $App.UI.btnOutboundLbl.Opacity = 1.0
    $App.UI.btnOutboundTog.IsEnabled = $true; $App.UI.btnOutboundTog.Opacity = 1.0
}

#  INITIAL UI STATE
function Force-InitialColors {
    Set-AutoConnectState $false $false
    Set-AdvState $App.State.isAdvancedOpen
    Set-WpfToggleState $App.UI.btnV2rayTog $App.Config.enableV2rayChain "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnDirectTog $App.Config.enableDirect "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnOutboundTog $App.Config.enableOutboundProxy "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnDohTog $App.Config.enableUpstreamDoh "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnBootTog $App.Config.launchOnBoot "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnDebugTog $App.Config.debugMode "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnTrayTog $App.Config.minimizeToTray "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnAdBlockTog $App.Config.enableAdBlock "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnLogsTog $App.State.isLogsOpen "HIDE" "SHOW"
}

Force-InitialColors
Update-RoutingToggle
Evaluate-ProxyExclusivity

#  POPUP DIALOGS
function Show-DirectRulesDialog {
    $ix = Get-Content (Get-AppPath "Data\DirectRulesDialog.xaml") -Raw
    $onLoad = {
        param($d)
        $d.FindName("txtDomains").Text = $App.Config.lastManualSplit
        $d.FindName("txtApps").Text    = $App.Config.lastAppSplit
        $d.FindName("txtBlock").Text   = $App.Config.lastBlockSplit
        if ($App.Config.lastXrayMode -eq "VPN Mode") {
            $d.FindName("txtDomains").IsEnabled = $false
            $d.FindName("txtDomains").Opacity   = 0.3
            $d.FindName("lblDomains").Text      = "Domains & IPs (Disabled in VPN Mode - Use App Bypass below)"
            $d.FindName("lblDomains").Opacity   = 0.5
            $d.FindName("txtApps").Focus() | Out-Null
        } else { $d.FindName("txtDomains").Focus() | Out-Null }
    }
    $onSave = {
        param($d)
        $App.Config.lastManualSplit = $d.FindName("txtDomains").Text.Trim()
        $App.Config.lastAppSplit    = $d.FindName("txtApps").Text.Trim()
        $App.Config.lastBlockSplit  = $d.FindName("txtBlock").Text.Trim()
    }

    $result = Show-AppDialog -Title "SPLIT TUNNELING AND PRIVACY ENGINE" -Width 480 -Height 375 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
    if ($result) {
        $hasRules = -not [string]::IsNullOrWhiteSpace($App.Config.lastManualSplit) -or
                    -not [string]::IsNullOrWhiteSpace($App.Config.lastAppSplit)
        if (-not $App.Config.enableDirect -and $hasRules) {
            $App.Config.enableDirect = $true
            Set-WpfToggleState $App.UI.btnDirectTog $true
        }
        Save-Config
        if ($App.State.isConnected) { 
        if ($App.Config.lastXrayMode -eq "VPN Mode") { Show-ToastNotification "Please reconnect to apply the changes safely." }
        else { Restart-Xray $App.Config.lastXrayMode }
    } elseif ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
    }
    return $result
}


function Show-CustomBridgeDialog {
    $ix = Get-Content (Get-AppPath "Data\CustomBridgeDialog.xaml") -Raw
    $onLoad = {
        param($d)
        
        $script:moatDialogWindow = $d
        $script:moatBorderMain   = $d.FindName("borderMain")
        
        $script:moatTxtInput = $d.FindName("txtInput")
        $script:moatTxtInput.Text = $App.Config.customBridgeLine
        $script:moatTxtInput.Focus() | Out-Null
        $script:moatTxtInput.CaretIndex = $script:moatTxtInput.Text.Length

        $script:moatPanGetBridges = $d.FindName("panGetBridges")
        $script:moatPanCaptcha    = $d.FindName("panCaptcha")
        $script:moatImgCaptcha    = $d.FindName("imgCaptcha")
        $script:moatTxtCaptchaSol = $d.FindName("txtCaptchaSol")
        $script:moatBtnCaptchaSubmit = $d.FindName("btnCaptchaSubmit")
        $script:moatBtnCaptchaCancel = $d.FindName("btnCaptchaCancel")

        $script:moatBtnWeb  = $d.FindName("btnGetWebTunnel")
        $script:moatBtnObfs = $d.FindName("btnGetObfs4")
        $script:moatBtnOk   = $d.FindName("btnOk")
        $script:moatBtnCancel = $d.FindName("btnCancel")
        
        $script:fetchingBridges = $false
        $script:moatChallengeId = ""
        $script:moatChallengeStr = ""

        # DYNAMIC UI SIZING
        $script:moatSetDialogHeight = {
            param($isCaptcha)
            
            $targetH  = if ($isCaptcha) { 320.0 } else { 260.0 }
            $tBorderH = if ($isCaptcha) { 266.0 } else { 206.0 }
            $tBtnTop  = if ($isCaptcha) { 220.0 } else { 165.0 }
            $tOpac    = if ($isCaptcha) { 1.0   } else { 0.0   }

            $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(250))
            
            if ($null -ne $script:moatDialogWindow) {
                $script:moatDialogWindow.BeginAnimation([System.Windows.Window]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetH, $dur)))
            }
            if ($null -ne $script:moatBorderMain) {
                $script:moatBorderMain.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBorderH, $dur)))
            }
            if ($null -ne $script:moatBtnOk) {
                $script:moatBtnOk.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBtnTop, $dur)))
            }
            if ($null -ne $script:moatBtnCancel) {
                $script:moatBtnCancel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBtnTop, $dur)))
            }
            if ($null -ne $script:moatPanCaptcha) {
    if ($isCaptcha) { 
        $script:moatPanCaptcha.Visibility = "Visible" 
        $script:moatPanCaptcha.IsHitTestVisible = $true
    } else {
        $script:moatPanCaptcha.IsHitTestVisible = $false
    }
    
    $script:moatPanCaptcha.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tOpac, $dur)))
    if (-not $isCaptcha) {
        $ht = New-Object System.Windows.Threading.DispatcherTimer
        $ht.Interval = [TimeSpan]::FromMilliseconds(250)
        $ht.add_Tick({ $ht.Stop(); if ($null -ne $script:moatPanCaptcha) { $script:moatPanCaptcha.Visibility = "Hidden" } }.GetNewClosure())
        $ht.Start()
    }
}
        }

        $script:moatEndpoints = @(
            "https://bridges.torproject.org/moat",
            "https://bridges2.torproject.org/moat",
            "https://tor.eff.org/moat"
        )

        $script:cancelFetchBlock = {
            if ($null -ne $App.Runtime.bridgeWebClient) {
                $App.Runtime.bridgeWebClient.CancelAsync()
                $App.Runtime.bridgeWebClient.Dispose()
                $App.Runtime.bridgeWebClient = $null
            }
            $script:fetchingBridges = $false
            if ($null -ne $script:moatBtnWeb)  { $script:moatBtnWeb.Content = "WEBTUNNEL"; $script:moatBtnWeb.IsEnabled = $true }
            if ($null -ne $script:moatBtnObfs) { $script:moatBtnObfs.Content = "OBFS4";     $script:moatBtnObfs.IsEnabled = $true }
            if ($null -ne $script:moatBtnOk)   { $script:moatBtnOk.IsEnabled = $true }
            
            if ($null -ne $script:moatPanGetBridges) { $script:moatPanGetBridges.Visibility = "Visible" }
            if ($null -ne $script:moatBtnCaptchaSubmit) {
                $script:moatBtnCaptchaSubmit.Content = "SUBMIT"
                $script:moatBtnCaptchaSubmit.IsEnabled = $true
            }
            
            & $script:moatSetDialogHeight $false
        }

        $script:RequestMoatCheck = {
            $solution = $script:moatTxtCaptchaSol.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($solution)) { return }

            $script:moatBtnCaptchaSubmit.Content = "VERIFYING..."
            $script:moatBtnCaptchaSubmit.IsEnabled = $false

            $url = $script:moatEndpoints[$script:moatIndex] + "/check"
            
            $reqBody = @{
                data = @( @{
                    id = $script:moatChallengeId
                    version = "0.1.0"
                    type = "moat-solution"
                    transport = $script:moatBridgeType
                    challenge = $script:moatChallengeStr
                    solution = $solution
                    qrcode = "false"
                } )
            } | ConvertTo-Json -Depth 5 -Compress

            $App.Runtime.bridgeWebClient = New-Object System.Net.WebClient
            try {
                $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
                $sysProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
                $App.Runtime.bridgeWebClient.Proxy = $sysProxy
            } catch {}

            $App.Runtime.bridgeWebClient.Headers.Add("Content-Type", "application/vnd.api+json")
            $App.Runtime.bridgeWebClient.Headers.Add("Accept", "application/vnd.api+json")
            $App.Runtime.bridgeWebClient.Encoding = [System.Text.Encoding]::UTF8

            $App.Runtime.bridgeWebClient.Add_UploadStringCompleted({
                param($sender, $e)
                $App.UI.form.Dispatcher.Invoke([System.Action]{
                    if ($e.Cancelled -or -not $script:fetchingBridges) { return }
                    if ($null -ne $e.Error) {
                        if ($null -ne $script:moatTxtCaptchaSol) { $script:moatTxtCaptchaSol.Text = "" }
                        if ($null -ne $script:moatBtnCaptchaSubmit) { $script:moatBtnCaptchaSubmit.Content = "NEW CAPTCHA..." }
                        $script:moatIndex = 0
                        & $script:RequestMoatChallenge
                        return
                    }

                    try {
                        $res = $e.Result | ConvertFrom-Json
                        if ($res.data -and $res.data[0].bridges -and $res.data[0].bridges.Count -gt 0) {
                            $lines = $res.data[0].bridges -join "`n"
                            $existing = $script:moatTxtInput.Text.Trim()
                            $newLines = $lines.Trim()
                            $script:moatTxtInput.Text = if ([string]::IsNullOrWhiteSpace($existing)) { $newLines } else { "$existing`n$newLines" }
                            $script:moatTxtInput.CaretIndex = $script:moatTxtInput.Text.Length
                            & $script:cancelFetchBlock
                        } else {
                            throw "No bridges returned."
                        }
                    } catch {
                        if ($null -ne $script:moatTxtCaptchaSol) { $script:moatTxtCaptchaSol.Text = "" }
                        if ($null -ne $script:moatBtnCaptchaSubmit) { $script:moatBtnCaptchaSubmit.Content = "NEW CAPTCHA..." }
                        $script:moatIndex = 0
                        & $script:RequestMoatChallenge
                    }
                })
                $sender.Dispose()
            })

            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            try { $App.Runtime.bridgeWebClient.UploadStringAsync([uri]$url, "POST", $reqBody) }
            catch { 
                if ($null -ne $script:moatTxtCaptchaSol) { $script:moatTxtCaptchaSol.Text = "" }
                $script:moatIndex = 0
                & $script:RequestMoatChallenge
            }
        }

        $script:RequestMoatChallenge = {
            if ($script:moatIndex -ge $script:moatEndpoints.Count) {
                & $script:cancelFetchBlock
                [System.Windows.MessageBox]::Show("Could not reach Tor Project servers.`nTry again later or check your network.`n`nAlternatively, you can get bridges manually:`n  - Telegram: @GetBridgesBot`n  - Email: bridges@torproject.org`n  - Browser: bridges.torproject.org", "Fetch Failed", 0, 48) | Out-Null
                return
            }

            if ($null -ne $script:moatBtnCaptchaSubmit) { $script:moatBtnCaptchaSubmit.Content = "FETCHING..." }
            $url = $script:moatEndpoints[$script:moatIndex] + "/fetch"
            $reqBody = @{ data = @( @{ version = "0.1.0"; type = "client-transports"; supported = @($script:moatBridgeType) } ) } | ConvertTo-Json -Depth 5 -Compress

            $App.Runtime.bridgeWebClient = New-Object System.Net.WebClient
            try {
                $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
                $sysProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
                $App.Runtime.bridgeWebClient.Proxy = $sysProxy
            } catch {}

            $App.Runtime.bridgeWebClient.Headers.Add("Content-Type", "application/vnd.api+json")
            $App.Runtime.bridgeWebClient.Headers.Add("Accept", "application/vnd.api+json")
            $App.Runtime.bridgeWebClient.Encoding = [System.Text.Encoding]::UTF8

            $App.Runtime.bridgeWebClient.Add_UploadStringCompleted({
                param($sender, $e)
                $App.UI.form.Dispatcher.Invoke([System.Action]{
                    if ($e.Cancelled -or -not $script:fetchingBridges) { return }
                    if ($null -ne $e.Error) {
                        $script:moatIndex++
                        & $script:RequestMoatChallenge
                        return
                    }

                    try {
                        $res = $e.Result | ConvertFrom-Json
                        
                        if ($res.data -and $res.data[0].id -and $res.data[0].image -and $res.data[0].challenge) {
                            $script:moatChallengeId = $res.data[0].id
                            $script:moatChallengeStr = $res.data[0].challenge
                            
                            $bytes = [Convert]::FromBase64String($res.data[0].image)
                            $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
                            $img = New-Object System.Windows.Media.Imaging.BitmapImage
                            $img.BeginInit(); $img.StreamSource = $ms; $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $img.EndInit(); $img.Freeze()
                            $script:moatImgCaptcha.Source = $img

                            $script:moatPanGetBridges.Visibility = "Hidden"
                            
                            & $script:moatSetDialogHeight $true

                            $script:moatTxtCaptchaSol.Text = ""
                            $script:moatBtnCaptchaSubmit.Content = "SUBMIT"
                            $script:moatBtnCaptchaSubmit.IsEnabled = $true
                            $script:moatTxtCaptchaSol.Focus() | Out-Null
                        } else {
                            $script:moatIndex++
                            & $script:RequestMoatChallenge
                        }
                    } catch {
                        $script:moatIndex++
                        & $script:RequestMoatChallenge
                    }
                })
                $sender.Dispose()
            })

            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            try { $App.Runtime.bridgeWebClient.UploadStringAsync([uri]$url, "POST", $reqBody) }
            catch { $script:moatIndex++; & $script:RequestMoatChallenge }
        }

        $startFetchWeb = {
            if ($script:fetchingBridges) { & $script:cancelFetchBlock; return }
            $script:fetchingBridges = $true
            $script:moatBridgeType = "webtunnel"
            $script:moatIndex = 0
            $script:moatBtnWeb.Content = "FETCHING..."
            $script:moatBtnObfs.IsEnabled = $false
            & $script:RequestMoatChallenge
        }
        
        $startFetchObfs = {
            if ($script:fetchingBridges) { & $script:cancelFetchBlock; return }
            $script:fetchingBridges = $true
            $script:moatBridgeType = "obfs4"
            $script:moatIndex = 0
            $script:moatBtnObfs.Content = "FETCHING..."
            $script:moatBtnWeb.IsEnabled = $false
            & $script:RequestMoatChallenge
        }

        if ($null -ne $script:moatTxtCaptchaSol) {
            $script:moatTxtCaptchaSol.Add_KeyDown({
                param($sender, $e)
                if ($e.Key -eq [System.Windows.Input.Key]::Enter -and $script:moatBtnCaptchaSubmit.IsEnabled) {
                    & $script:RequestMoatCheck
                }
            })
        }

        if ($null -ne $script:moatBtnWeb)          { $script:moatBtnWeb.Add_Click($startFetchWeb) }
        if ($null -ne $script:moatBtnObfs)         { $script:moatBtnObfs.Add_Click($startFetchObfs) }
        if ($null -ne $script:moatBtnCaptchaSubmit){ $script:moatBtnCaptchaSubmit.Add_Click($script:RequestMoatCheck) }
        if ($null -ne $script:moatBtnCaptchaCancel){ $script:moatBtnCaptchaCancel.Add_Click($script:cancelFetchBlock) }

        $silentCancel = {
            if ($null -ne $App.Runtime.bridgeWebClient) {
                $App.Runtime.bridgeWebClient.CancelAsync()
                $App.Runtime.bridgeWebClient.Dispose()
                $App.Runtime.bridgeWebClient = $null
            }
            $script:fetchingBridges = $false

            $script:moatDialogWindow     = $null
            $script:moatBorderMain       = $null
            $script:moatTxtInput         = $null
            $script:moatPanGetBridges    = $null
            $script:moatPanCaptcha       = $null
            $script:moatImgCaptcha       = $null
            $script:moatTxtCaptchaSol    = $null
            $script:moatBtnCaptchaSubmit = $null
            $script:moatBtnCaptchaCancel = $null
            $script:moatBtnWeb            = $null
            $script:moatBtnObfs           = $null
            $script:moatBtnOk             = $null
            $script:moatBtnCancel         = $null
        }

        $d.FindName("btnCancel").Add_Click($silentCancel)
        $btnCloseDialog = $d.FindName("btnCloseDialog")
        if ($null -ne $btnCloseDialog) { $btnCloseDialog.Add_Click($silentCancel) }
    }
    $onSave = {
        param($d)
        
        $inputText = $d.FindName("txtInput").Text.Trim()
        
        if ([string]::IsNullOrWhiteSpace($inputText)) {
            Show-ToastNotification "Custom bridge cannot be empty."
            return $false
        }
        
        if ($script:fetchingBridges) { 
            $null = & $script:cancelFetchBlock 
        }
        
        $App.Config.customBridgeLine = $inputText

        $script:moatDialogWindow     = $null
        $script:moatBorderMain       = $null
        $script:moatTxtInput         = $null
        $script:moatPanGetBridges    = $null
        $script:moatPanCaptcha       = $null
        $script:moatImgCaptcha       = $null
        $script:moatTxtCaptchaSol    = $null
        $script:moatBtnCaptchaSubmit = $null
        $script:moatBtnCaptchaCancel = $null
        $script:moatBtnWeb            = $null
        $script:moatBtnObfs           = $null
        $script:moatBtnOk             = $null
        $script:moatBtnCancel         = $null

        return $true
    }
    
    return Show-AppDialog -Title "CUSTOM BRIDGE CONFIGURATIONS" -Width 420 -Height 260 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

function Show-OutboundProxyDialog {
    $ix = Get-Content (Get-AppPath "Data\OutboundProxyDialog.xaml") -Raw
    $onLoad = {
        param($dlg)
        $cmbProxyType = $dlg.FindName("cmbProxyType"); $cmbAuth    = $dlg.FindName("cmbAuth")
        $txtAddr      = $dlg.FindName("txtAddr");       $txtPort    = $dlg.FindName("txtPort")
        $txtUser      = $dlg.FindName("txtUser");       $txtPass    = $dlg.FindName("txtPass")
        $panAuth      = $dlg.FindName("panAuth");       $btnOk      = $dlg.FindName("btnOk")
        $btnCancel    = $dlg.FindName("btnCancel");     $borderMain = $dlg.FindName("borderMain")

        $App.State.tempProxyType = if ([string]::IsNullOrEmpty($App.Config.outboundProxyType)) { "SOCKS5" } else { $App.Config.outboundProxyType }
        $txtAddr.Text = $App.Config.outboundProxyAddress
        $txtPort.Text = $App.Config.outboundProxyPort
        $txtUser.Text = $App.Config.outboundProxyUser
        $txtPass.Text = $App.Config.outboundProxyPass

        foreach ($item in $cmbProxyType.Items) { if ($item.Content -eq $App.State.tempProxyType) { $cmbProxyType.SelectedItem = $item; break } }
        $authTarget = if ($App.Config.enableOutboundAuth) { "Enabled" } else { "Disabled" }
        foreach ($item in $cmbAuth.Items) { if ($item.Content -eq $authTarget) { $cmbAuth.SelectedItem = $item; break } }

        $isFirstLoad = $true
        $evalAuth = {
            $isEnabled = ($null -ne $cmbAuth.SelectedItem -and $cmbAuth.SelectedItem.Content -eq "Enabled")
            $targetH = if ($isEnabled) { 320.0 } else { 263.0 }
            $tBorderH = if ($isEnabled) { 267.0 } else { 210.0 }
            $tBtnTop  = if ($isEnabled) { 225.0 } else { 168.0 }
            $tOpac    = if ($isEnabled) { 1.0   } else { 0.0   }
            if ($isFirstLoad) {
                $dlg.Height = $targetH; $borderMain.Height = $tBorderH
                $btnOk.SetValue([System.Windows.Controls.Canvas]::TopProperty,    [double]$tBtnTop)
                $btnCancel.SetValue([System.Windows.Controls.Canvas]::TopProperty,[double]$tBtnTop)
                $panAuth.Opacity    = $tOpac
                $panAuth.Visibility = if ($isEnabled) { "Visible" } else { "Hidden" }
            } else {
                if ($isEnabled) { $panAuth.Visibility = "Visible" }
                $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(250))
                $dlg.BeginAnimation(       [System.Windows.Window]::HeightProperty,           (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetH,  $dur)))
                $borderMain.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBorderH, $dur)))
                $btnOk.BeginAnimation(     [System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBtnTop,  $dur)))
                $btnCancel.BeginAnimation( [System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBtnTop,  $dur)))
                $panAuth.BeginAnimation(   [System.Windows.UIElement]::OpacityProperty,       (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tOpac,    $dur)))
                if (-not $isEnabled) {
                    $ht = New-Object System.Windows.Threading.DispatcherTimer
                    $ht.Interval = [TimeSpan]::FromMilliseconds(250)
                    $ht.add_Tick({ $ht.Stop(); if ($cmbAuth.SelectedItem.Content -eq "Disabled") { $panAuth.Visibility = "Hidden" } }.GetNewClosure())
                    $ht.Start()
                }
            }
        }.GetNewClosure()
        $cmbAuth.add_SelectionChanged({ & $evalAuth }.GetNewClosure())
        $cmbProxyType.add_SelectionChanged({
            if ($null -ne $cmbProxyType.SelectedItem) { $App.State.tempProxyType = $cmbProxyType.SelectedItem.Content }
        }.GetNewClosure())
        & $evalAuth
        $isFirstLoad = $false
        $txtAddr.Focus() | Out-Null; $txtAddr.CaretIndex = $txtAddr.Text.Length
    }
    $onSave = {
        param($d)
        $App.Config.outboundProxyAddress = $d.FindName("txtAddr").Text.Trim()
        $App.Config.outboundProxyPort    = $d.FindName("txtPort").Text.Trim()
        $App.Config.outboundProxyType    = $App.State.tempProxyType
        $cmbA = $d.FindName("cmbAuth")
        $App.Config.enableOutboundAuth   = ($null -ne $cmbA.SelectedItem -and $cmbA.SelectedItem.Content -eq "Enabled")
        $App.Config.outboundProxyUser    = $d.FindName("txtUser").Text.Trim()
        $App.Config.outboundProxyPass    = $d.FindName("txtPass").Text.Trim()
    }
    return Show-AppDialog -Title "OUTBOUND PROXY CONFIGURATION" -Width 420 -Height 280 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

function Show-DohDialog {
    $ix = Get-Content (Get-AppPath "Data\DohDialog.xaml") -Raw
    $onLoad = {
        param($dlg)
        $txtUpDoh = $dlg.FindName("txtUpDoh")
        $txtUpDoh.Text = $App.Config.upstreamDohUrl
        $txtUpDoh.Focus() | Out-Null; $txtUpDoh.CaretIndex = $txtUpDoh.Text.Length
    }
    $onSave = {
        param($d)
        $uDoh = $d.FindName("txtUpDoh").Text
        if (-not [string]::IsNullOrWhiteSpace($uDoh)) { $App.Config.upstreamDohUrl = $uDoh.Trim() }
    }
    return Show-AppDialog -Title "DNS SETTINGS" -Width 420 -Height 240 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

function Show-ExitNodeDialog {
    $ix = Get-Content (Get-AppPath "Data\ExitNodeDialog.xaml") -Raw
    $onLoad = {
        param($d)
        $cmb = $d.FindName("cmbCountries")
        $countries = [ordered]@{
            "Argentina"="ar";"Australia"="au";"Austria"="at";"Brazil"="br";"Canada"="ca";
            "Finland"="fi";"France"="fr";"Germany"="de";"Hong Kong"="hk";"Iceland"="is";
            "India"="in";"Iran"="ir";"Italy"="it";"Japan"="jp";"Mexico"="mx";
            "Netherlands"="nl";"New Zealand"="nz";"Romania"="ro";"Singapore"="sg";
            "South Africa"="za";"South Korea"="kr";"Spain"="es";"Sweden"="se";
            "Switzerland"="ch";"United Arab Emirates"="ae";"United Kingdom"="gb";"United States"="us"
        }
        foreach ($c in $countries.Keys) {
            $cbi = New-Object System.Windows.Controls.ComboBoxItem
            $cbi.Content = "$c ($($countries[$c].ToUpper()))"; $cbi.Tag = $countries[$c]
            $cmb.Items.Add($cbi) | Out-Null
        }
        foreach ($item in $cmb.Items) { if ($item.Tag -eq $App.Config.customExitCountry) { $cmb.SelectedItem = $item; break } }
        if ($null -eq $cmb.SelectedItem -and $cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }
    }
    $onSave = {
        param($d)
        $App.Config.customExitCountry = $d.FindName("cmbCountries").SelectedItem.Tag.ToLower()
    }
    return Show-AppDialog -Title "CUSTOM EXIT-NODE ROUTING" -Width 420 -Height 200 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

function Show-ExpertConfigDialog {
    $ix = Get-Content (Get-AppPath "Data\ExpertConfigDialog.xaml") -Raw
    $onLoad = {
        param($d)
        $hwTarget = if ($App.Config.expertHardwareAccel)   { "Enabled" } else { "Disabled" }
        foreach ($item in $d.FindName("cmbHW").Items) { if ($item.Content -eq $hwTarget) { $d.FindName("cmbHW").SelectedItem = $item; break } }
        $ffTarget = if ($App.Config.expertFascistFirewall) { "Enabled" } else { "Disabled" }
        foreach ($item in $d.FindName("cmbFF").Items) { if ($item.Content -eq $ffTarget) { $d.FindName("cmbFF").SelectedItem = $item; break } }
        $snTarget = if ($App.Config.expertStrictNodes)     { "Enabled" } else { "Disabled" }
        foreach ($item in $d.FindName("cmbSN").Items) { if ($item.Content -eq $snTarget) { $d.FindName("cmbSN").SelectedItem = $item; break } }
        $d.FindName("txtCBT").Text     = $App.Config.expertCircuitBuildTimeout
        $d.FindName("txtKP").Text      = $App.Config.expertKeepalivePeriod
        $d.FindName("txtNCP").Text     = $App.Config.expertNewCircuitPeriod
        $d.FindName("txtMCD").Text     = $App.Config.expertMaxCircuitDirtiness
        $d.FindName("txtNEG").Text     = $App.Config.expertNumEntryGuards
        $d.FindName("txtEN").Text      = $App.Config.expertEntryNodes
        $d.FindName("txtExit").Text    = $App.Config.expertExitNodes
        $d.FindName("txtExNodes").Text = $App.Config.expertExcludeNodes
        $d.FindName("txtExExit").Text  = $App.Config.expertExcludeExitNodes
        $d.FindName("txtRaw").Text     = $App.Config.expertCustomTorrc
    }
    $onSave = {
        param($d)
        $App.Config.expertHardwareAccel       = ($d.FindName("cmbHW").SelectedItem.Content  -eq "Enabled")
        $App.Config.expertFascistFirewall     = ($d.FindName("cmbFF").SelectedItem.Content  -eq "Enabled")
        $App.Config.expertStrictNodes         = ($d.FindName("cmbSN").SelectedItem.Content  -eq "Enabled")
        $App.Config.expertCircuitBuildTimeout = $d.FindName("txtCBT").Text.Trim()
        $App.Config.expertKeepalivePeriod     = $d.FindName("txtKP").Text.Trim()
        $App.Config.expertNewCircuitPeriod    = $d.FindName("txtNCP").Text.Trim()
        $App.Config.expertMaxCircuitDirtiness = $d.FindName("txtMCD").Text.Trim()
        $App.Config.expertNumEntryGuards      = $d.FindName("txtNEG").Text.Trim()
        $App.Config.expertEntryNodes          = $d.FindName("txtEN").Text.Trim()
        $App.Config.expertExitNodes           = $d.FindName("txtExit").Text.Trim()
        $App.Config.expertExcludeNodes        = $d.FindName("txtExNodes").Text.Trim()
        $App.Config.expertExcludeExitNodes    = $d.FindName("txtExExit").Text.Trim()
        $App.Config.expertCustomTorrc         = $d.FindName("txtRaw").Text.Trim()
    }
    return Show-AppDialog -Title "EXPERT TORRC CONFIGURATION" -Width 530 -Height 530 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

function Show-V2rayDialog {
    $ix = Get-Content (Get-AppPath "Data\V2rayDialog.xaml") -Raw
    $onLoad = {
        param($d)
        $t = $d.FindName("txtInput")
        $t.Text = $App.Config.v2rayChainJson
        $t.Focus() | Out-Null; $t.CaretIndex = $t.Text.Length
        $d.FindName("btnImport").Add_Click({
            $fd = New-Object System.Windows.Forms.OpenFileDialog
            $fd.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
            if ($fd.ShowDialog() -eq "OK") { $t.Text = Get-Content $fd.FileName -Raw }
        }.GetNewClosure())
    }
    $onSave = {
        param($d)
        $txt = $d.FindName("txtInput").Text
        if ([string]::IsNullOrWhiteSpace($txt)) { $App.Config.v2rayChainJson = ""; return $true }
        try {
            $parsed   = $txt | ConvertFrom-Json
            $testNode = if ($null -ne $parsed.outbounds) { $parsed.outbounds[0] } else { $parsed }
            if (-not $testNode.protocol) { throw "Missing Protocol" }
            $App.Config.v2rayChainJson = $txt.Trim()
            return $true
        } catch {
            Show-ToastNotification "Invalid Xray JSON syntax!"
            return $false
        }
    }
    return Show-AppDialog -Title "V2RAY OUTBOUND CHAIN CONFIGURATION" -Width 520 -Height 355 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

#  CORE LOGIC
function Request-ConfigSave {
    if ($null -eq $App.Runtime.saveDebounceTimer) {
        $App.Runtime.saveDebounceTimer = New-Object System.Windows.Threading.DispatcherTimer
        $App.Runtime.saveDebounceTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $App.Runtime.saveDebounceTimer.add_Tick({
            $App.Runtime.saveDebounceTimer.Stop()
            Save-Config
        }.GetNewClosure())
    }
    $App.Runtime.saveDebounceTimer.Stop()
    $App.Runtime.saveDebounceTimer.Start()
}

function Save-Config {
    $data = [ordered]@{
        AutoStart            = [bool]$App.Config.autoStart
        LaunchOnBoot         = [bool]$App.Config.launchOnBoot
        IsLogsOpen           = [bool]$App.State.isLogsOpen
        DebugMode            = [bool]$App.Config.debugMode      
        LastConfig           = if ($App.UI.comboConfig.SelectedItem) { $App.UI.comboConfig.SelectedItem.Tag } else { $App.Config.lastConfig }
        SelectedBridge       = if ($App.UI.comboBridge.SelectedItem) { $App.UI.comboBridge.SelectedItem.Tag } else { $App.Config.lastBridge }
        InstanceCount        = if ($App.UI.comboCount.SelectedItem)  { [int]$App.UI.comboCount.SelectedItem.Tag } else { [int]$App.Config.lastCount }
        XrayMode             = $App.Config.lastXrayMode
        ManualSplit          = $App.Config.lastManualSplit
        AppSplit             = $App.Config.lastAppSplit
        BlockSplit           = $App.Config.lastBlockSplit
        EnableDirect         = [bool]$App.Config.enableDirect
        CustomBridgeLine     = $App.Config.customBridgeLine
        EnableV2rayChain     = [bool]$App.Config.enableV2rayChain
        V2rayChainJson       = $App.Config.v2rayChainJson
        EnableOutboundProxy  = [bool]$App.Config.enableOutboundProxy
        OutboundProxyAddress = $App.Config.outboundProxyAddress
        OutboundProxyPort    = $App.Config.outboundProxyPort
        OutboundProxyType    = $App.Config.outboundProxyType
        OutboundProxyUser    = $App.Config.outboundProxyUser
        OutboundProxyPass    = $App.Config.outboundProxyPass
        EnableOutboundAuth   = [bool]$App.Config.enableOutboundAuth
        EnableUpstreamDoh    = [bool]$App.Config.enableUpstreamDoh
        UpstreamDohUrl       = $App.Config.upstreamDohUrl
        CustomExitCountry    = $App.Config.customExitCountry
        MinimizeToTray       = [bool]$App.Config.minimizeToTray
        EnableAdBlock        = [bool]$App.Config.enableAdBlock
        ExpertHardwareAccel       = [bool]$App.Config.expertHardwareAccel
        ExpertStrictNodes         = [bool]$App.Config.expertStrictNodes
        ExpertFascistFirewall     = [bool]$App.Config.expertFascistFirewall 
        ExpertCircuitBuildTimeout = $App.Config.expertCircuitBuildTimeout
        ExpertKeepalivePeriod     = $App.Config.expertKeepalivePeriod
        ExpertNewCircuitPeriod    = $App.Config.expertNewCircuitPeriod
        ExpertMaxCircuitDirtiness = $App.Config.expertMaxCircuitDirtiness
        ExpertNumEntryGuards      = $App.Config.expertNumEntryGuards
        ExpertEntryNodes          = $App.Config.expertEntryNodes
        ExpertExitNodes           = $App.Config.expertExitNodes
        ExpertExcludeNodes        = $App.Config.expertExcludeNodes
        ExpertExcludeExitNodes    = $App.Config.expertExcludeExitNodes
        ExpertCustomTorrc         = $App.Config.expertCustomTorrc
    }
    try { $data | ConvertTo-Json -Depth 10 | Set-Content -Path $App.Config.cfgFile -Force }
    catch { Write-Host "Failed to save config: $($_.Exception.Message)" }
}

function Write-XrayConfig {
    $rules = @( @{ type="field"; ip=@("127.0.0.0/8","::1","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16"); outboundTag="direct" } )
    $blockDomains = @()
    if ($App.Config.enableAdBlock) { $blockDomains += @("geosite:category-ads-all","domain:analytics.google.com","domain:google-analytics.com") }
    if ($App.Config.enableDirect -and -not [string]::IsNullOrWhiteSpace($App.Config.lastBlockSplit)) {
        $App.Config.lastBlockSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { $blockDomains += "domain:$_" }
    }
    if ($blockDomains.Count -gt 0) { $rules += @{ type="field"; domain=$blockDomains; outboundTag="block" } }
    if ($App.Config.enableDirect -and $App.Config.lastXrayMode -ne "VPN Mode" -and $App.Config.lastManualSplit) {
        $domains = @(); $ips = @()
        $App.Config.lastManualSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
            if ($_ -match "[a-zA-Z]") { $domains += "domain:$_" } else { $ips += $_ }
        }
        if ($domains.Count -gt 0) { $rules += @{ type="field"; domain=$domains; outboundTag="direct" } }
        if ($ips.Count    -gt 0) { $rules += @{ type="field"; ip=$ips;         outboundTag="direct" } }
    }
    $rules += @{ type="field"; network="tcp,udp"; outboundTag="proxy" }
    $inbounds = @(
        @{ listen="0.0.0.0"; port=10818; protocol="mixed"; tag="mixed-in"; settings=@{ udp=$true }; sniffing=@{ enabled=$true; destOverride=@("http","tls","quic","fakedns") } }
        @{ listen="127.0.0.1"; port=10899; protocol="dokodemo-door"; tag="api"; settings=@{ address="127.0.0.1" } }
    )
    $outbounds = @()
    if ($App.Config.enableV2rayChain -and -not [string]::IsNullOrWhiteSpace($App.Config.v2rayChainJson)) {
        try {
            $v2p  = $App.Config.v2rayChainJson | ConvertFrom-Json
            $v2ob = if ($null -ne $v2p.outbounds) { $v2p.outbounds | Where-Object { $_.protocol -notin @("freedom","blackhole") } | Select-Object -First 1 } else { $v2p }
            $v2ob.tag = "proxy"
            if ($null -ne $v2ob.streamSettings -and $null -ne $v2ob.streamSettings.tlsSettings) {
                if (-not $v2ob.streamSettings.tlsSettings.psobject.properties.match('allowInsecure').Count) {
                    $v2ob.streamSettings.tlsSettings | Add-Member -MemberType NoteProperty -Name "allowInsecure" -Value $true
                } else { $v2ob.streamSettings.tlsSettings.allowInsecure = $true }
            }
            if (-not $v2ob.psobject.properties.match('proxySettings').Count) {
                $v2ob | Add-Member -MemberType NoteProperty -Name "proxySettings" -Value @{ tag="torProxy" }
            } else { $v2ob.proxySettings = @{ tag="torProxy" } }
            $outbounds += $v2ob
            $outbounds += @{ tag="torProxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } }
        } catch { $outbounds += @{ tag="proxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } } }
    } else { $outbounds += @{ tag="proxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } } }
    if ($App.Config.enableAdBlock -or ($App.Config.enableDirect -and -not [string]::IsNullOrWhiteSpace($App.Config.lastBlockSplit))) {
        $outbounds += @{ tag="block"; protocol="blackhole"; settings=@{} }
    }
    $outbounds += @{ tag="direct"; protocol="freedom"; settings=@{} }
    $cfg = @{
        log      = @{ logLevel="info"; access="access.log"; error="error.log" }
        stats    = @{}
        api      = @{ tag="api"; services=@("StatsService") }
        policy   = @{ system=@{ statsInboundUplink=$true; statsInboundDownlink=$true } }
        inbounds = $inbounds; outbounds=$outbounds
        routing  = @{ domainStrategy="AsIs"; rules=(@( @{ type="field"; inboundTag=@("api"); outboundTag="api" } ) + $rules) }
    }
    if ($App.Config.enableUpstreamDoh -and -not [string]::IsNullOrWhiteSpace($App.Config.upstreamDohUrl)) {
        $cfg.Add("dns", @{ servers=@($App.Config.upstreamDohUrl) })
    }
    
    try { 
        $cfg | ConvertTo-Json -Depth 10 | Set-Content (Get-AppPath "Data\Xray\config.json") -ErrorAction Stop 
        return $true
    } catch { 
        [System.Windows.Forms.MessageBox]::Show("Failed to write Xray config. Check disk space and permissions.`n`n$($_.Exception.Message)", "Config Error", 0, 16)
        return $false 
    }
}

function Write-SingboxConfig {
    $currentExe = [System.IO.Path]::GetFileName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName).ToLower()
    $bypassApps = @(
        $currentExe,"tor.exe","tor","haproxy.exe","haproxy","lyrebird.exe","lyrebird",
        "xray.exe","xray","sing-box.exe","sing-box","cmd.exe","conhost.exe",
        "powershell.exe","pwsh.exe"
    )
    if ($App.Config.enableDirect -and -not [string]::IsNullOrWhiteSpace($App.Config.lastAppSplit)) {
        $App.Config.lastAppSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
            $appStr  = if ($_ -notmatch "\.exe$") { "$_.exe" } else { $_ }
            $baseStr = $_ -replace "\.exe$", ""
            if ($bypassApps -notcontains $appStr.ToLower())  { $bypassApps += $appStr.ToLower() }
            if ($bypassApps -notcontains $baseStr.ToLower()) { $bypassApps += $baseStr.ToLower() }
        }
    }
    $sbRules = @(
        @{ action = "sniff" }
        @{ protocol = "quic"; action = "reject"; method = "default" }
        @{ protocol = "dns"; action = "hijack-dns" }
        @{ port = @(53); network = "udp"; action = "hijack-dns" }
        @{ port = @(53); network = "tcp"; action = "hijack-dns" }
        @{ process_name = $bypassApps; action = "route"; outbound = "direct" }
        @{ network = "udp"; port = @(3478, 5349); action = "route"; outbound = "direct" }
        @{ ip_is_private = $true; action = "route"; outbound = "direct" }
    )
    $dnsServers = @( @{ tag = "dns_direct"; type = "udp"; server = "8.8.8.8" } )
    if ($App.Config.enableUpstreamDoh -and -not [string]::IsNullOrWhiteSpace($App.Config.upstreamDohUrl)) {
        if ($App.Config.upstreamDohUrl.StartsWith("https://")) {
            try {
                $u = [uri]$App.Config.upstreamDohUrl
                $dPath = if ($u.AbsolutePath -eq "/") { "/dns-query" } else { $u.PathAndQuery }
                $dnsServers += @{ tag = "dns_proxy"; type = "https"; server = $u.Host; path = $dPath; detour = "proxy" }
            } catch { $dnsServers += @{ tag = "dns_proxy"; type = "tcp"; server = "1.1.1.1"; detour = "proxy" } }
        } else { $dnsServers += @{ tag = "dns_proxy"; type = "tcp"; server = $App.Config.upstreamDohUrl; detour = "proxy" } }
    } else { $dnsServers += @{ tag = "dns_proxy"; type = "https"; server = "cloudflare-dns.com"; path = "/dns-query"; detour = "proxy" } }

    $sbConfig = @{
        log      = @{ level = "fatal" }
        dns      = @{ 
            servers  = $dnsServers
            rules    = @(
                @{ domain_keyword = @("stun","cdn77","datapacket"); action = "route"; server = "dns_direct" }
                @{ action = "route"; server = "dns_proxy" }
            )
            strategy = "ipv4_only"
        }
        inbounds = @( @{
            type                     = "tun"; tag = "tun-in"
            interface_name           = "singbox_tun"
            address                  = @("172.18.0.1/30")
            mtu                      = 9000; auto_route = $true; strict_route = $true
            stack                    = "mixed"; endpoint_independent_nat = $true
        } )
        outbounds = @(
            @{ type = "socks";  tag = "proxy";  server = "127.0.0.1"; server_port = 10818 }
            @{ type = "direct"; tag = "direct" }
        )
        route    = @{
            rules                   = $sbRules
            final                   = "proxy"
            default_domain_resolver = @{ server = "dns_direct" }
            auto_detect_interface   = $true
            find_process            = $true
        }
    }
    
    try { 
        $sbConfig | ConvertTo-Json -Depth 10 | Set-Content (Get-AppPath "Data\sing_box\config.json") -ErrorAction Stop
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to write Sing-Box config. Check disk space and permissions.`n`n$($_.Exception.Message)", "Config Error", 0, 16)
        return $false 
    }
}

function Disable-SystemProxy {
    try {
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "ProxyEnable" -Value 0 -ErrorAction SilentlyContinue
        [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    } catch {}
}

function Format-HAProxyConfig($activeCount) {
    $cfgPath = Get-AppPath "Data\HAproxy\haproxy.cfg"
    if (-not (Test-Path $cfgPath)) { return }
    
    $haData = Get-Content $cfgPath; $newData = @()
    
    foreach ($line in $haData) {
        if ($line -match "^listen stats|bind 127\.0\.0\.1:10888|mode http|stats enable|stats uri /stats") { 
            continue 
        }

        if ($line -match "^\s*#?\s*server\s+tor(\d+)") {
            if ([int]$matches[1] -le $activeCount) { $newData += ($line -replace "^\s*#+\s*", "    ") }
            else { $newData += if ($line -notmatch "^\s*#") { "    # $($line.TrimStart())" } else { $line } }
        } else { 
            $newData += $line 
        }
    }
    
    $oldText = $haData -join "`n"
    $newText = $newData -join "`n"
    
    if ($oldText -ne $newText) {
        $newData | Set-Content $cfgPath
    }
}

function Restart-Xray($targetMode) {
    Get-Process sing-box, xray -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($null -ne $_.Path -and ($_.Path -eq (Get-AppPath "Data\Xray\xray.exe") -or $_.Path -eq (Get-AppPath "Data\sing_box\sing-box.exe"))) {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Stop-RuntimePid "cmdDebugPid"
    Stop-RuntimePid "cmdDebugPid2"
    Stop-RuntimePid "xrayDohPid"

    if ($null -ne $App.Runtime.xrayRestartTimer) {
        $App.Runtime.xrayRestartTimer.Stop()
    }

    $App.Runtime.xrayRestartTimer = New-Object System.Windows.Threading.DispatcherTimer
    $App.Runtime.xrayRestartTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $App.Runtime.xrayRestartTimer.add_Tick({
        $App.Runtime.xrayRestartTimer.Stop()
        
        if (-not (Write-XrayConfig)) { return }

        if ($App.Config.debugMode) {
            $p = Start-Process "cmd.exe" -ArgumentList "/c `"title XrayDebug & .\xray.exe run -c config.json || pause`"" -WorkingDirectory $App.Config.xrayDir -WindowStyle Normal -PassThru
            $App.Runtime.cmdDebugPid = $p.Id
        } else {
            Start-ProcessDirect -FilePath (Get-AppPath "Data\Xray\xray.exe") -Arguments "run -c config.json" -WorkingDirectory $App.Config.xrayDir -Hidden $true
        }
        
        if ($targetMode -eq "VPN Mode") {
            if (-not (Write-SingboxConfig)) { return }
            if ($App.Config.debugMode) {
                $p2 = Start-Process "cmd.exe" -ArgumentList "/c `"title SingBoxDebug & .\sing-box.exe run -c config.json || pause`"" -WorkingDirectory $App.Config.sbDir -WindowStyle Normal -PassThru
                $App.Runtime.cmdDebugPid2 = $p2.Id
            } else { Start-ProcessDirect -FilePath (Get-AppPath "Data\sing_box\sing-box.exe") -Arguments "run -c config.json" -WorkingDirectory $App.Config.sbDir -Hidden $true }
        } elseif ($targetMode -eq "Proxy Mode") { Set-SystemProxy $true }

        if ($targetMode -ne "Proxy Mode") { Set-SystemProxy $false }

        if ($App.State.isConnected) {
            if ($null -ne $App.Runtime.pingTimer) { $App.Runtime.pingTimer.Stop() }
            $pt = New-Object System.Windows.Threading.DispatcherTimer
            $pt.Interval = [TimeSpan]::FromSeconds(1.5)
            $pt.add_Tick({ $pt.Stop(); Start-GeoPing }.GetNewClosure())
            $App.Runtime.pingTimer = $pt
            $pt.Start()
        }
    }.GetNewClosure())
    $App.Runtime.xrayRestartTimer.Start()
}
#  RING ANIMATION

$script:RING_W       = 294.0
$script:RING_H       = 55.0
$script:RING_PERIM   = 698.0
$script:RING_REST_T  = 643.0

function Get-RingXY($t) {
    $t = $t % $script:RING_PERIM
    if ($t -lt 0) { $t += $script:RING_PERIM }
    $top    = $script:RING_W          # 294
    $right  = $top + $script:RING_H   # 349
    $bottom = $right + $script:RING_W # 643
    if ($t -le $top) {
        return @{ X = $t;                           Y = 0.0 }
    } elseif ($t -le $right) {
        return @{ X = $script:RING_W;              Y = ($t - $top) }
    } elseif ($t -le $bottom) {
        return @{ X = $script:RING_W - ($t - $right); Y = $script:RING_H }
    } else {
        return @{ X = 0.0;                          Y = $script:RING_H - ($t - $bottom) }
    }
}

function Update-RingAnimation {
    param([string]$State)
    if ($null -eq $App.UI.ringCanvas) { return }

    $fadeElem = {
        param($elem, $toOpacity, $ms)
        try {
            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation($toOpacity, (New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($ms))))
            $elem.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $anim)
        } catch { $elem.Opacity = $toOpacity }
    }

    $fadeColor = {
        param($stop, $toColorHex, $ms)
        try {
            $toColor = [System.Windows.Media.ColorConverter]::ConvertFromString($toColorHex)
            $anim = New-Object System.Windows.Media.Animation.ColorAnimation($toColor, (New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($ms))))
            $stop.BeginAnimation([System.Windows.Media.GradientStop]::ColorProperty, $anim)
        } catch {}
    }

    switch ($State) {
        "Idle" {
            $App.Runtime.ringState = "Idle"
            & $fadeElem $App.UI.ringCanvas 0.0 400
            
            if ($null -ne $App.UI.scannerTrans) {
                $App.UI.scannerTrans.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
            }
        }

        "Connecting" {
            $App.Runtime.ringState = "Connecting"
            
            & $fadeElem $App.UI.ringCanvas 1.0 350

            if ($null -ne $App.UI.scannerStop1) {
                & $fadeColor $App.UI.scannerStop1 "#00B78854" 300
                & $fadeColor $App.UI.scannerStop2 "#FFB78854" 300
                & $fadeColor $App.UI.scannerStop3 "#00B78854" 300
            }

            if ($null -ne $App.UI.scannerTrans) {
                $dur  = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(1700))
                $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
                
$anim.From = 100.0
$anim.To = 290.0
                
                $anim.Duration = $dur
                $anim.AutoReverse = $true
                $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
                $anim.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
                $anim.EasingFunction.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
                $App.UI.scannerTrans.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $anim)
            }
        }

       "Connected" {
            $App.Runtime.ringState = "Connected"
            
            $App.UI.ringCanvas.Opacity = 1.0
            
            if ($null -ne $App.UI.scannerStop1) {
                & $fadeColor $App.UI.scannerStop1 "#0068D391" 600
                & $fadeColor $App.UI.scannerStop2 "#FF68D391" 600
                & $fadeColor $App.UI.scannerStop3 "#0068D391" 600
            }
        }
  }
 }

#  GEO-IP
function Start-GeoPing {
    if ($App.State.isGeoTracing) { return }
    $App.State.isGeoTracing = $true
    $App.UI.lblGeoData.Text       = "Loc: TRACING...`nPing: --"
    $App.UI.lblGeoData.Foreground = $App.UI.brGreen
    
    if ($null -ne $App.Runtime.geoWebClient) {
        $App.Runtime.geoWebClient.CancelAsync()
        $App.Runtime.geoWebClient.Dispose()
    }

    $App.Runtime.geoWebClient = New-Object System.Net.WebClient
    $App.Runtime.geoWebClient.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:10818")
    $App.Runtime.geoSw = [System.Diagnostics.Stopwatch]::StartNew()
    $App.Runtime.geoWebClient.Add_DownloadStringCompleted({
        param($sender, $e)
        $App.State.isGeoTracing = $false
        $App.Runtime.geoSw.Stop()
        $pingMs = $App.Runtime.geoSw.ElapsedMilliseconds
        $App.UI.form.Dispatcher.Invoke([System.Action]{
            if ($App.State.isConnected) {
                if (-not $e.Cancelled -and $null -eq $e.Error) {
                    try {
                        $data = $e.Result | ConvertFrom-Json
                        $routingMode = if ($null -ne $App.UI.comboConfig.SelectedItem) { $App.UI.comboConfig.SelectedItem.Tag } else { "Optimized" }
                        $cMap = @{ NA="NORTH AMERICA"; EU="EUROPE"; AS="ASIA"; SA="SOUTH AMERICA"; AF="AFRICA"; OC="OCEANIA"; AN="ANTARCTICA" }
                        $continent = if ($cMap[$data.continent_code]) { $cMap[$data.continent_code] } else { $data.continent_code }
                        $geoStr = ""
                        if ($App.Config.enableV2rayChain -or $routingMode -eq "Custom") {
                            $geoStr = $data.country
                        } elseif ($routingMode -eq "Expert") {
                            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertExitNodes) -and $App.Config.expertExitNodes -notmatch ",") {
                                $geoStr = $data.country
                            } else { $geoStr = $continent }
                        } else { $geoStr = $continent }
                        $App.UI.lblGeoData.Text       = "Loc: $($geoStr.ToUpper())`nPing: $($pingMs)ms"
                        $App.UI.lblGeoData.Foreground = $App.UI.brGreen
                    } catch { $App.UI.lblGeoData.Text = "Loc: ERROR`nPing: --"; $App.UI.lblGeoData.Foreground = $App.UI.brDarkRed }
                } else { $App.UI.lblGeoData.Text = "Loc: TIMEOUT`nPing: --"; $App.UI.lblGeoData.Foreground = $App.UI.brDarkRed }
            }
        })
        $sender.Dispose()
        $App.Runtime.geoWebClient = $null
    }.GetNewClosure())
    
    try { $App.Runtime.geoWebClient.DownloadStringAsync([uri]"https://get.geojs.io/v1/ip/geo.json") }
    catch { 
        $App.State.isGeoTracing = $false
        if ($null -ne $App.Runtime.geoWebClient) { 
            $App.Runtime.geoWebClient.Dispose()
            $App.Runtime.geoWebClient = $null
        }
    }
}

#  TORRC BUILDER 
function Build-TorrcConfig {
    param([string]$TorrcFile, [string]$SelBridge, [string]$SelConfig, [string]$Path)
    $c = @(Get-Content "$Path\$TorrcFile")
    $cleanCfg = @()
    foreach ($line in $c) {
        if ($line -match "^# --- MANAGED BRIDGES ---") { break }
        if ($line -notmatch "^UseBridges|^ClientTransportPlugin|^Bridge|^HTTPSProxy|^Socks5Proxy|^Socks5ProxyUsername|^Socks5ProxyPassword|^HTTPSProxyAuthenticator|^Log notice file|^MaxCircuitDirtiness|^ExitNodes|^StrictNodes|^CircuitBuildTimeout|^HardwareAccel|^KeepalivePeriod|^NewCircuitPeriod|^FascistFirewall|^ExcludeNodes|^ExcludeExitNodes|^DataDirectory|^GeoIPFile|^GeoIPv6File|^# --- DYNAMIC ROUTING ---") {
            if ($line.Trim()) { $cleanCfg += $line.Trim() }
        }
    }
    $cleanCfg += "","# --- DYNAMIC ROUTING ---"
    $cleanCfg += "DataDirectory ./Data"
    $cleanCfg += "GeoIPFile ../../TorBin/geoip"
    $cleanCfg += "GeoIPv6File ../../TorBin/geoip6"
    switch ($SelConfig) {
        "Optimized" {
            $cleanCfg += "CircuitBuildTimeout 10","KeepalivePeriod 60","NewCircuitPeriod 120","HardwareAccel 1"
            $cleanCfg += "ExitNodes {nl},{de},{it},{is},{fi},{au},{nz},{ch},{hk},{ae},{us}","StrictNodes 0"
        }
        "Custom" {
            if (-not [string]::IsNullOrWhiteSpace($App.Config.customExitCountry)) {
                $cleanCfg += "ExitNodes {$($App.Config.customExitCountry)}","StrictNodes 1"
            }
        }
        "Expert" {
            if ($App.Config.expertHardwareAccel)   { $cleanCfg += "HardwareAccel 1" } else { $cleanCfg += "HardwareAccel 0" }
            if ($App.Config.expertFascistFirewall)  { $cleanCfg += "FascistFirewall 1" }
            if ($App.Config.expertStrictNodes)     { $cleanCfg += "StrictNodes 1" } else { $cleanCfg += "StrictNodes 0" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertCircuitBuildTimeout)) { $cleanCfg += "CircuitBuildTimeout $($App.Config.expertCircuitBuildTimeout)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertKeepalivePeriod))    { $cleanCfg += "KeepalivePeriod $($App.Config.expertKeepalivePeriod)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertNewCircuitPeriod))   { $cleanCfg += "NewCircuitPeriod $($App.Config.expertNewCircuitPeriod)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertMaxCircuitDirtiness)){ $cleanCfg += "MaxCircuitDirtiness $($App.Config.expertMaxCircuitDirtiness)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertNumEntryGuards))     { $cleanCfg += "NumEntryGuards $($App.Config.expertNumEntryGuards)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertEntryNodes))         { $cleanCfg += "EntryNodes $($App.Config.expertEntryNodes)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertExitNodes))          { $cleanCfg += "ExitNodes $($App.Config.expertExitNodes)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertExcludeNodes))       { $cleanCfg += "ExcludeNodes $($App.Config.expertExcludeNodes)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertExcludeExitNodes))   { $cleanCfg += "ExcludeExitNodes $($App.Config.expertExcludeExitNodes)" }
            if (-not [string]::IsNullOrWhiteSpace($App.Config.expertCustomTorrc)) {
                $App.Config.expertCustomTorrc.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { $cleanCfg += $_ }
            }
        }
        default {
            $cleanCfg += "ExitNodes {nl},{de},{it},{is},{fi},{au},{nz},{ch},{hk},{ae},{us}","StrictNodes 0"
        }
    }
    $cleanCfg += "","# --- MANAGED BRIDGES ---"
    $cleanCfg += "Log notice file ./tor.log"
    if ($App.Config.enableOutboundProxy -and $App.Config.outboundProxyAddress -and $App.Config.outboundProxyPort) {
        if ($App.Config.outboundProxyType -eq "SOCKS5") {
            $cleanCfg += "Socks5Proxy $($App.Config.outboundProxyAddress):$($App.Config.outboundProxyPort)"
            if ($App.Config.enableOutboundAuth -and $App.Config.outboundProxyUser -and $App.Config.outboundProxyPass) {
                $cleanCfg += "Socks5ProxyUsername $($App.Config.outboundProxyUser)","Socks5ProxyPassword $($App.Config.outboundProxyPass)"
            }
        } elseif ($App.Config.outboundProxyType -eq "HTTPS") {
            $cleanCfg += "HTTPSProxy $($App.Config.outboundProxyAddress):$($App.Config.outboundProxyPort)"
            if ($App.Config.enableOutboundAuth -and $App.Config.outboundProxyUser -and $App.Config.outboundProxyPass) {
                $cleanCfg += "HTTPSProxyAuthenticator $($App.Config.outboundProxyUser):$($App.Config.outboundProxyPass)"
            }
        }
    }
    if ($SelBridge -eq "Custom") {
        if (-not [string]::IsNullOrWhiteSpace($App.Config.customBridgeLine)) {
            $cleanCfg += "UseBridges 1"
            $cleanCfg += "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel,snowflake exec ../../TorBin/lyrebird.exe"
            $App.Config.customBridgeLine.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch "^ClientTransportPlugin" } | ForEach-Object {
                $cleanCfg += if ($_ -notmatch "^Bridge\s") { "Bridge $_" } else { $_ }
            }
        } else {
            $cleanCfg += "UseBridges 0"
        }
    } elseif ($SelBridge -ne "Direct (None)") {
        $b = $bridgeData[$SelBridge]
        if ($null -ne $b) {
            $cleanCfg += "UseBridges 1"
            $cleanCfg += $b.plugin.Replace("%%LYREBIRD%%", "../../TorBin/lyrebird.exe")
            foreach ($bl in $b.lines) { $cleanCfg += $bl }
        } else {
            $cleanCfg += "UseBridges 0"
        }
    } else { 
        $cleanCfg += "UseBridges 0" 
    }
    
    return $cleanCfg
}

#  ENGINE CONTROL
function Stop-RuntimePid([string]$Key) {
    if ($null -ne $App.Runtime.$Key) {
        Stop-Process -Id $App.Runtime.$Key -Force -ErrorAction SilentlyContinue
        $App.Runtime.$Key = $null
    }
}

function Reset-ButtonText {
    $App.UI.btnActionMainText.Text       = "CONNECT"
    $App.UI.btnActionSubText.Text        = ""
    $App.UI.btnActionMainText.Foreground = $App.UI.brWhite
    Update-RingAnimation -State "Idle"
}

function Stop-AllEngines($isClosing = $false) {
    $App.State.abortBoot       = $true
    $App.State.isEngineRunning = $false
    if ($null -ne $App.Runtime.bootstrapTimer) { $App.Runtime.bootstrapTimer.Stop() }
    if ($null -ne $App.Runtime.staggerTimer)   { $App.Runtime.staggerTimer.Stop() }
    Set-SystemProxy $false
    $toKill = @()
    Get-Process tor, haproxy, xray, sing-box -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $p = $_.Path
            if ($null -ne $p -and (
                $p -eq (Get-AppPath "Data\Xray\xray.exe")         -or
                $p -eq (Get-AppPath "Data\HAproxy\haproxy.exe")   -or
                $p -eq (Get-AppPath "Data\sing_box\sing-box.exe") -or
                $p -eq (Get-AppPath "Data\TorBin\tor.exe")        -or
                $p -match "Data\\Tors\\Tor")) {
                $toKill += $_
            }
        } catch {}
    }
    foreach ($proc in $toKill) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    
    Stop-RuntimePid "cmdDebugPid"
    Stop-RuntimePid "cmdDebugPid2"
    Stop-RuntimePid "xrayDohPid"

    $App.State.isConnected      = $false
    $App.State.lastTotalBytes   = 0
    $App.State.sessionDataBytes = 0
    $App.State.sessionStartTime = $null
    $App.State.speedSamples     = @(0, 0, 0, 0, 0)
    $App.Runtime.isFetchingStats = $false

    if (-not $isClosing) {
        if ($null -ne $App.UI.lblSessionTime) { $App.UI.lblSessionTime.Text = "SESSION: OFFLINE"; $App.UI.lblSessionTime.Foreground = $App.UI.brGray }
        Reset-ButtonText
        $App.UI.btnAction.IsEnabled    = $true
        $App.UI.lblSocksTitle.Text     = "MIXED PORT"
        $App.UI.lblSocksDataIPs.Text   = "Waiting for connection..."
        $App.UI.lblSocksDataTags.Text  = ""
        $App.UI.lblStatsData.Text      = "Speed: 0 KB/s`nTotal: 0 MB"
        $App.UI.lblGeoData.Text        = "Loc: --`nPing: --"
        $App.UI.lblGeoData.Foreground  = $App.UI.brGreen
        Update-RoutingToggle
    }
}

function Update-LanIP {
    try {
        $_ips = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' } |
            ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
            Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and
                           $_.Address.ToString() -notmatch '^127\.|^169\.254\.' } |
            Select-Object -First 1
        if ($_ips) { $App.State.lanIp = $_ips.Address.ToString() }
        else { $App.State.lanIp = "UNKNOWN" }
    } catch { $App.State.lanIp = "UNKNOWN" }
}

function Start-Engines {
    try {
        $App.State.isEngineRunning = $true
        
        Update-LanIP
        $App.UI.btnActionMainText.Text       = "CONNECTING"
        $App.UI.btnActionMainText.Foreground = $App.UI.brOrange
        $App.UI.btnActionSubText.Foreground  = $App.UI.bc.ConvertFromString("#B78854")
        DoEvents

        for ($ki = 0; $ki -lt 8; $ki++) {
            $kpid = $App.Runtime.torPids[$ki]
            if ($null -ne $kpid) {
                try { Stop-Process -Id $kpid -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        Get-Process haproxy, xray, sing-box -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = $_.Path
                if ($null -ne $p -and (
                    $p -eq (Get-AppPath "Data\Xray\xray.exe")         -or
                    $p -eq (Get-AppPath "Data\HAproxy\haproxy.exe")   -or
                    $p -eq (Get-AppPath "Data\sing_box\sing-box.exe"))) {
                    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
        Stop-RuntimePid "cmdDebugPid"
        Stop-RuntimePid "cmdDebugPid2"
        Stop-RuntimePid "xrayDohPid"
        if ($null -ne $App.Runtime.bootstrapTimer) { $App.Runtime.bootstrapTimer.Stop() }
        if ($null -ne $App.Runtime.staggerTimer)   { $App.Runtime.staggerTimer.Stop() }
        Set-SystemProxy $false

        # Reset state
        $App.State.isConnected      = $false
        $App.State.lastTotalBytes   = 0
        $App.State.sessionDataBytes = 0
        $App.State.sessionStartTime = $null
        $App.State.speedSamples     = @(0,0,0,0,0)
        $App.Runtime.torPids = @($null,$null,$null,$null,$null,$null,$null,$null)

        $App.State.abortBoot = $false

        $App.UI.btnActionSubText.Text = "Clearing old engines..."
        Wait-NonBlocking 0.8

        if ($App.State.abortBoot) { 
            return 
        }

        $selBridge  = $App.UI.comboBridge.SelectedItem.Tag

        $selConfig = "Optimized"
        if ($App.UI.comboConfig.SelectedItem.Tag -eq "Custom") { $selConfig = "Custom" }
        if ($App.UI.comboConfig.SelectedItem.Tag -eq "Expert") { $selConfig = "Expert" }

        $selCount  = [int]($App.UI.comboCount.SelectedItem.Tag)
        
        $App.Runtime.pollSelCount  = $selCount
        $App.Runtime.pollMode      = $App.Config.lastXrayMode
        $App.Runtime.pollWinStyle  = if ($App.Config.debugMode) { "Normal" } else { "Hidden" }
        $App.Runtime.pollSelBridge = $App.UI.comboBridge.SelectedItem.Tag
        
        $mode      = $App.Config.lastXrayMode
        $torrcFile = "torrc"

        for ($i = 1; $i -le 8; $i++) {
            Remove-Item (Get-AppPath "Data\Tors\Tor$i\tor.log") -ErrorAction SilentlyContinue
            $lbl    = $App.UI.form.FindName("lblTor$i")
            $padded = $i.ToString().PadLeft(2,'0')
            if ($null -ne $lbl) {
                if ($i -le $selCount) { $lbl.Text = "Tor $padded`: Waiting..."; $lbl.Foreground = $App.UI.brGray }
                else                  { $lbl.Text = "Tor $padded`: Disabled";   $lbl.Foreground = $App.UI.brDarkGray }
            }
        }
        Remove-Item (Get-AppPath "Data\Xray\access.log")     -ErrorAction SilentlyContinue
        Remove-Item (Get-AppPath "Data\Xray\access.log.tmp") -ErrorAction SilentlyContinue
        if ($null -ne $App.UI.txtXrayLogs) { $App.UI.txtXrayLogs.Text = "" }

        $App.State.isEngineRunning           = $true
        Save-Config
        $winStyle                            = if ($App.Config.debugMode) { "Normal" } else { "Hidden" }
        $App.UI.btnActionMainText.Text       = "CONNECTING"
        $App.UI.btnActionMainText.Foreground = $App.UI.brOrange
        $App.UI.btnActionSubText.Foreground  = $App.UI.bc.ConvertFromString("#B78854")

        Update-RingAnimation -State "Connecting"
        Format-HAProxyConfig $selCount

        $staggerDelay = 1.5

        $i = 1
        while ($true) {
            if ($App.State.abortBoot -or $i -gt $App.Runtime.pollSelCount) { break }

            $padded = $i.ToString().PadLeft(2,'0')
            $App.UI.btnActionSubText.Text = "Launching Tor $i of $($App.Runtime.pollSelCount)"
            if ($i % 2 -eq 0) { DoEvents }

            $path = Get-AppPath "Data\Tors\Tor$i"
            
            Remove-Item "$path\tor.log" -ErrorAction SilentlyContinue 

            if (-not (Test-Path "$path\$torrcFile")) { $i++; continue }
            $cleanCfg = Build-TorrcConfig -TorrcFile $torrcFile -SelBridge $selBridge -SelConfig $selConfig -Path $path

            $cleanCfg | Set-Content "$path\$torrcFile"
            $torProc = Start-ProcessDirect -FilePath (Get-AppPath "Data\TorBin\tor.exe") -Arguments "-f $torrcFile" -WorkingDirectory $path -Hidden (-not $App.Config.debugMode) -PassThru $true
            if ($null -ne $torProc) { $App.Runtime.torPids[$i - 1] = $torProc.Id }
            $i++
            Wait-NonBlocking $staggerDelay
        }
        if ($App.State.abortBoot) { return }

        Format-HAProxyConfig $App.Runtime.pollSelCount

        # BOOTSTRAP POLLING 
        $isBridged    = ($selBridge -ne "Direct (None)")
        $hardTimeout  = if ($isBridged) { 300 } else { 180 }
        $App.Runtime.pollDeadline = (Get-Date).AddSeconds($hardTimeout)

        $App.UI.btnActionSubText.Text = "Waiting for Tor bootstrap..."

        if ($null -ne $App.Runtime.bootstrapTimer) { $App.Runtime.bootstrapTimer.Stop() }
        
        $App.Runtime.bootstrapTimer = New-Object System.Windows.Threading.DispatcherTimer
        $App.Runtime.bootstrapTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $App.Runtime.bootstrapTimer.add_Tick({
            if ($App.State.abortBoot) {
                $App.Runtime.bootstrapTimer.Stop()
                Reset-ButtonText
                return
            }

            $oneReady   = $false
            $bestPct    = -1
            $bestTorIdx = 1
            for ($i = 1; $i -le $App.Runtime.pollSelCount; $i++) {
                $logPath = Get-AppPath "Data\Tors\Tor$i\tor.log"
                if (-not (Test-Path $logPath)) { continue }
                try {
                    $fs      = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $sr      = New-Object System.IO.StreamReader($fs)
                    try {
                        $content = $sr.ReadToEnd()
                        $pm = [regex]::Matches($content, 'Bootstrapped (\d+)%')
                        if ($pm.Count -gt 0) {
                            $pct = [int]$pm[$pm.Count - 1].Groups[1].Value
                            if ($pct -gt $bestPct) { $bestPct = $pct; $bestTorIdx = $i }
                            if ($pct -eq 100) { $oneReady = $true }
                        }
                    } finally { $sr.Close(); $fs.Close() }
                } catch {}
            }
            if (-not $oneReady) {
                if ((Get-Date) -ge $App.Runtime.pollDeadline) {
                    $shortWarning = "Still Bootstrapping, Consider different bridges"
                    if ($App.UI.btnActionSubText.Text -ne $shortWarning) {
                        $App.UI.btnActionSubText.Text = $shortWarning
                    }
                } elseif ($bestPct -ge 0) {
                    $App.UI.btnActionSubText.Text = "Bootstrapping... $bestPct% (Tor $bestTorIdx)"
                }
                return
            }

            $App.Runtime.bootstrapTimer.Stop()

            $App.UI.btnActionSubText.Text = "Booting Core Engines"
            Remove-Item (Get-AppPath "Data\Xray\access.log") -ErrorAction SilentlyContinue
            Remove-Item (Get-AppPath "Data\Xray\error.log")  -ErrorAction SilentlyContinue
            if (Test-Path (Get-AppPath "Data\HAproxy\haproxy.exe")) {
    Start-ProcessDirect -FilePath (Get-AppPath "Data\HAproxy\haproxy.exe") -Arguments "-f haproxy.cfg" -WorkingDirectory $App.Config.haPath -Hidden (-not $App.Config.debugMode)
}

            Get-Process sing-box, xray -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    if ($null -ne $_.Path -and ($_.Path -eq (Get-AppPath "Data\Xray\xray.exe") -or $_.Path -eq (Get-AppPath "Data\sing_box\sing-box.exe"))) {
                        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                    }
                } catch {}
            }
            Stop-RuntimePid "cmdDebugPid"
            Stop-RuntimePid "cmdDebugPid2"
            Stop-RuntimePid "xrayDohPid"

            $xrayBootTimer = New-Object System.Windows.Threading.DispatcherTimer
            $xrayBootTimer.Interval = [TimeSpan]::FromMilliseconds(600)
            $xrayBootTimer.add_Tick({
                $xrayBootTimer.Stop()
                if ($App.State.abortBoot) { return }

                if (-not (Write-XrayConfig)) { return }

                if ($App.Config.debugMode) {
                    $p = Start-Process "cmd.exe" -ArgumentList "/c `"title XrayDebug & .\xray.exe run -c config.json || pause`"" -WorkingDirectory $App.Config.xrayDir -WindowStyle Normal -PassThru
                    $App.Runtime.cmdDebugPid = $p.Id
                } else {
                    Start-ProcessDirect -FilePath (Get-AppPath "Data\Xray\xray.exe") -Arguments "run -c config.json" -WorkingDirectory $App.Config.xrayDir -Hidden $true
                }

                if ($App.Runtime.pollMode -eq "VPN Mode") {
                    if (-not (Write-SingboxConfig)) { return }
                    if ($App.Config.debugMode) {
                        $p2 = Start-Process "cmd.exe" -ArgumentList "/c `"title SingBoxDebug & .\sing-box.exe run -c config.json || pause`"" -WorkingDirectory $App.Config.sbDir -WindowStyle Normal -PassThru
                        $App.Runtime.cmdDebugPid2 = $p2.Id
                    } else { Start-ProcessDirect -FilePath (Get-AppPath "Data\sing_box\sing-box.exe") -Arguments "run -c config.json" -WorkingDirectory $App.Config.sbDir -Hidden $true }
                }

                if ($App.Runtime.pollMode -eq "Proxy Mode") { Set-SystemProxy $true } else { Set-SystemProxy $false }

                $App.UI.lblSocksTitle.Text    = "MIXED PORT"
                $App.UI.lblSocksDataIPs.Text  = "127.0.0.1:10818`n$($App.State.lanIp)`:10818"
                $App.UI.lblSocksDataTags.Text = "(Local)`n(LAN)"
                $App.State.isConnected        = $true
                $App.State.lastTotalBytes     = 0
                $App.State.sessionDataBytes   = 0
                $App.State.speedSamples       = @(0,0,0,0,0)
                $App.State.sessionStartTime   = Get-Date
                $App.UI.btnActionMainText.Text       = "CONNECTED"
                $App.UI.btnActionSubText.Text        = ""
                $App.UI.btnActionMainText.Foreground = $App.UI.brGreen
                Start-GeoPing
                Update-RingAnimation -State "Connected"
            }.GetNewClosure())
            $xrayBootTimer.Start()
        }.GetNewClosure())
        $App.Runtime.bootstrapTimer.Start()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("A startup error occurred:`n$($_.Exception.Message)", "Error", 0, 16)
        Reset-ButtonText
    }
}

#  UPDATE
$App.UI.btnTitleUpdate.Add_Click({ Update-Application })
function Update-Application {
    $App.UI.btnTitleUpdate.IsEnabled = $false
    $App.UI.lblTitleText.Text = "CHECKING FOR UPDATES..."
    $wc = New-Object System.Net.WebClient
    $wc.Add_DownloadStringCompleted({
        param($sender, $e)
        $App.UI.form.Dispatcher.Invoke([System.Action]{
            if (-not $e.Cancelled -and $null -eq $e.Error) {
                if ($e.Result -match '\$App\.Config\.currentVersion\s*=\s*"([^"]+)"|\bcurrentVersion\s*=\s*"([^"]+)"') {
                    $remoteVer = if ($matches[1]) { $matches[1] } else { $matches[2] }
                    if ([version]$remoteVer -gt [version]$App.Config.currentVersion) {
                        $remoteMinVer = "0.0.0"
                        if ($e.Result -match 'minAutoUpdateVersion\s*=\s*"([^"]+)"') { $remoteMinVer = $matches[1] }
                        if ([version]$App.Config.currentVersion -lt [version]$remoteMinVer) {
                            $App.UI.lblTitleText.Text = "MANUAL UPDATE REQUIRED ($remoteVer)"
                            $App.UI.lblTitleText.Foreground = $App.UI.brRed
                            [System.Windows.Forms.MessageBox]::Show("A major update (v$remoteVer) is available!`n`nYour current version ($($App.Config.currentVersion)) is too old to update automatically.`n`nPlease download the latest release manually from GitHub.", "Manual Update Required", 0, 48)
                            Start-Process $App.Config.repoReleaseUrl
                            $App.UI.btnTitleUpdate.IsEnabled = $true
                            return
                        }
                        $App.UI.lblTitleText.Text       = "TOR MULTIPLEXER v$($App.Config.currentVersion) - UPDATE AVAILABLE ($remoteVer)"
                        $App.UI.lblTitleText.Foreground = $App.UI.brWhite
                        $msg = [System.Windows.Forms.MessageBox]::Show("Version $remoteVer is available! Update now?", "Update Available", 4, 64)
                        if ($msg -eq "Yes") {
                            $App.UI.lblTitleText.Text = "DOWNLOADING UPDATE... 0%"
                            DoEvents
                            $zipDownloadUrl = "https://github.com/RichTiTAN/Tor-Multiplexer/releases/latest/download/TorMultiplexer.zip" 
                            $baseDir  = $App.Config.baseDir
                            $zipPath  = Join-Path $baseDir "update_temp.zip"
                            $extPath  = Join-Path $baseDir "update_extracted"
                            if (Test-Path $extPath) { Remove-Item $extPath -Recurse -Force -ErrorAction SilentlyContinue }
                            $App.Runtime.updateDlClient = New-Object System.Net.WebClient
                            $dlClient = $App.Runtime.updateDlClient
                            $dlClient.add_DownloadProgressChanged({
                                param($s, $progressArgs)
                                $pct = $progressArgs.ProgressPercentage
                                $App.UI.form.Dispatcher.Invoke([System.Action]{
                                    $App.UI.lblTitleText.Text = "DOWNLOADING UPDATE... $pct%"
                                }.GetNewClosure())
                            }.GetNewClosure())
                            $dlClient.add_DownloadFileCompleted({
                                param($s, $completedArgs)
                                $App.UI.form.Dispatcher.Invoke([System.Action]{
                                    if ($completedArgs.Cancelled -or $null -ne $completedArgs.Error) {
                                        [System.Windows.Forms.MessageBox]::Show("Download failed.`n`nError: $($completedArgs.Error.Message)", "Update Error", 0, 16)
                                        $App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)"
                                        $App.UI.btnTitleUpdate.IsEnabled = $true
                                        return
                                    }
                                    try {
                                        $App.UI.lblTitleText.Text = "EXTRACTING UPDATE..."
                                        DoEvents

                                        $safeBaseDir = $App.Config.baseDir
                                        $safeZipPath = Join-Path $safeBaseDir "update_temp.zip"
                                        $safeExtPath = Join-Path $safeBaseDir "update_extracted"

                                        Expand-Archive -Path $safeZipPath -DestinationPath $safeExtPath -Force

                                        $extractedExePath = Get-ChildItem -Path $safeExtPath -Recurse -Filter "TorMultiplexer.exe" | Select-Object -First 1
                                        if ($null -eq $extractedExePath) { throw "TorMultiplexer.exe not found in the downloaded ZIP!" }

                                        $sourceDir  = $extractedExePath.Directory.FullName
                                        $currentExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

                                        $cmdArgs = "/c ping 127.0.0.1 -n 4 > nul & xcopy /Y /E /H /C /I `"$sourceDir\*`" `"$safeBaseDir`" & rmdir /S /Q `"$safeExtPath`" & del /Q `"$safeZipPath`" & start `"`" `"$currentExe`""

                                        Disable-SystemProxy
                                        Stop-AllEngines $true
                                        Start-Process cmd.exe -ArgumentList $cmdArgs -WindowStyle Hidden
                                        [Environment]::Exit(0)
                                    } catch {
                                        [System.Windows.Forms.MessageBox]::Show("Extraction failed.`n`nError: $($_.Exception.Message)", "Update Error", 0, 16)
                                        $App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)"
                                        $App.UI.btnTitleUpdate.IsEnabled = $true
                                    }
                                }.GetNewClosure())
                                $s.Dispose()
                            }.GetNewClosure())
                            $dlClient.DownloadFileAsync([uri]$zipDownloadUrl, $zipPath)
                        } else { $App.UI.btnTitleUpdate.IsEnabled = $true }
                    } else {
                        $App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)"
                        Show-ToastNotification "You are already on the latest version!" "Success"
                        $App.UI.btnTitleUpdate.IsEnabled = $true
                    }
                }
            } else {
                $App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)"
                Show-ToastNotification "Update check failed. Check your connection."
                $App.UI.btnTitleUpdate.IsEnabled = $true
            }
        }.GetNewClosure())
        $sender.Dispose()
    })
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { $wc.DownloadStringAsync([uri]$App.Config.repoRawUrl) }
    catch { $App.UI.btnTitleUpdate.IsEnabled = $true; $App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)" }
}

function Check-UpdateSilent {
    $localForm  = $App.UI.form
    $localTitle = $App.UI.lblTitleText
    $localVer   = $App.Config.currentVersion
    $localUrl   = $App.Config.repoRawUrl
    $localBrW   = $App.UI.brWhite
    $wc = New-Object System.Net.WebClient
    $wc.Add_DownloadStringCompleted({
        param($sender, $e)
        if (-not $e.Cancelled -and $null -eq $e.Error) {
            try {
                if ($e.Result -match '\$App\.Config\.currentVersion\s*=\s*"([^"]+)"|\bcurrentVersion\s*=\s*"([^"]+)"') {
                    $remoteVer = if ($matches[1]) { $matches[1] } else { $matches[2] }
                    if ([version]$remoteVer -gt [version]$localVer) {
                        $localForm.Dispatcher.Invoke([System.Action]{
                            if ($null -ne $localTitle) {
                                $localTitle.Text       = "TOR MULTIPLEXER v$localVer  -  UPDATE AVAILABLE"
                                $localTitle.Foreground = $localBrW
                            }
                        })
                    }
                }
            } catch {}
        }
        $sender.Dispose()
    }.GetNewClosure())
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { $wc.DownloadStringAsync([uri]$localUrl) } catch {}
}

function Update-BootShortcut {
    $taskName = "TorMultiplexer_AutoStart"
    if ($App.Config.launchOnBoot) {
        try {
            $exePath   = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            $action    = New-ScheduledTaskAction -Execute $exePath -WorkingDirectory $App.Config.baseDir
            $trigger   = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        } catch {
            Show-ToastNotification "Failed to create Auto-Start task (Check Permissions)."
            $App.Config.launchOnBoot = $false
            Set-WpfToggleState $App.UI.btnBootTog $false
        }
    } else {
        try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    }
    $old = Join-Path ([Environment]::GetFolderPath('Startup')) "TorMultiplexer.lnk"
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
}

#  SESSION CLOCK TIMER 
$App.Runtime.sessionClockTimer = New-Object System.Windows.Threading.DispatcherTimer
$App.Runtime.sessionClockTimer.Interval = [TimeSpan]::FromSeconds(1)
$App.Runtime.sessionClockTimer.add_Tick({
    if ($App.State.isConnected -and $null -ne $App.State.sessionStartTime -and $null -ne $App.UI.lblSessionTime) {
        $elapsed = (Get-Date) - $App.State.sessionStartTime
        $App.UI.lblSessionTime.Text       = "SESSION: " + $elapsed.ToString("hh\:mm\:ss")
        $App.UI.lblSessionTime.Foreground = $App.UI.brGreen
    }
}.GetNewClosure())
$App.Runtime.sessionClockTimer.Start()

#  STATS TIMER
$App.Runtime.statsTimer = New-Object System.Windows.Threading.DispatcherTimer
$App.Runtime.statsTimer.Interval = [TimeSpan]::FromSeconds(2)
$App.Runtime.statsTimer.add_Tick({
    if ($null -eq $App.UI.form -or $App.UI.form.Dispatcher.HasShutdownStarted) {
        $App.Runtime.statsTimer.Stop()
        return
    }
    if (-not $App.State.isConnected -or $App.Runtime.isFetchingStats) { return }
    $App.Runtime.isFetchingStats = $true

    $lastBytes    = $App.State.lastTotalBytes
    $sessionBytes = $App.State.sessionDataBytes
    $samples      = $App.State.speedSamples

    $syncResult = [System.Collections.Hashtable]::Synchronized(@{
        done         = $false
        curBytes     = [long]0
        statsText    = ""
        sessionBytes = $sessionBytes
        newSamples   = $samples
    })

    $ps = [PowerShell]::Create()
    $null = $ps.AddScript({
        param($lastBytes, $sessionBytes, $samples, $syncResult, $xrayDir)
        try {
            $xrayExe = Join-Path $xrayDir "xray.exe"
            if (-not (Test-Path $xrayExe)) { return }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $xrayExe
            $psi.Arguments = "api statsquery -server=127.0.0.1:10899"
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            
            if ($proc.WaitForExit(2000)) {
                $jsonOut = $proc.StandardOutput.ReadToEnd()
                $stats = $jsonOut | ConvertFrom-Json
                $upVal = [long]0; $dnVal = [long]0
                
                if ($null -ne $stats.stat) {
                    foreach ($item in $stats.stat) {
                        if ($item.name -match "uplink")   { $upVal += [long]$item.value }
                        if ($item.name -match "downlink") { $dnVal += [long]$item.value }
                    }
                }
                $curBytes = $upVal + $dnVal

                $syncResult.curBytes = $curBytes
                if ($curBytes -gt 0 -and $lastBytes -gt 0) {
                    $diff       = [Math]::Max([long]0, ($curBytes - $lastBytes))
                    $newSession = $sessionBytes + $diff
                    $newSamples = @($diff) + $samples[0..3]
                    
                    $avg = (($newSamples | Measure-Object -Average).Average) / 2
                    $spd = if ($avg -ge 1048576) { "$([Math]::Round($avg/1048576,2)) MB/s" } elseif ($avg -ge 1024) { "$([Math]::Round($avg/1024,1)) KB/s" } else { "$([int]$avg) B/s" }
                    $tot = if ($newSession -ge 1073741824) { "$([Math]::Round($newSession/1073741824,2)) GB" } elseif ($newSession -ge 1048576) { "$([Math]::Round($newSession/1048576,1)) MB" } else { "$([Math]::Round($newSession/1024,1)) KB" }
                    
                    $syncResult.statsText    = "Speed: $spd`nTotal: $tot"
                    $syncResult.sessionBytes = $newSession
                    $syncResult.newSamples   = $newSamples
                }
            } else {
                try { $proc.Kill() } catch {}
            }
        } catch {}
        $syncResult.done = $true
    })
    $null = $ps.AddParameters(@{
        lastBytes    = $lastBytes
        sessionBytes = $sessionBytes
        samples      = $samples
        syncResult   = $syncResult
        xrayDir      = $App.Config.xrayDir
    })

    $pollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $pollTimer.Interval = [TimeSpan]::FromMilliseconds(80)
    
    $asyncTask = $ps.BeginInvoke()

    $pollTimer.add_Tick({
        if (-not $syncResult.done) { return }
        $pollTimer.Stop()
        
        try {
            $ps.EndInvoke($asyncTask) | Out-Null
            $ps.Dispose()
        } catch {}

        if ($syncResult.curBytes -gt 0) {
            $App.State.lastTotalBytes = $syncResult.curBytes
            if ($syncResult.statsText -ne "") {
                $App.State.sessionDataBytes = $syncResult.sessionBytes
                $App.State.speedSamples     = $syncResult.newSamples
                if ($null -ne $App.UI.lblStatsData) { $App.UI.lblStatsData.Text = $syncResult.statsText }
            }
        }
        $App.Runtime.isFetchingStats = $false
    }.GetNewClosure())
    $pollTimer.Start()
}.GetNewClosure())
$App.Runtime.statsTimer.Start()

#  WINDOW SIZE / PANEL ANIMATION
function Update-WindowSize {
    if ($null -ne $App.Runtime.hideAdvTimer) { $App.Runtime.hideAdvTimer.Stop() }
    if ($null -ne $App.Runtime.hideLogTimer) { $App.Runtime.hideLogTimer.Stop() }
    $ts       = New-Object TimeSpan(0,0,0,0,300)
    $targetW  = if ($App.State.isLogsOpen -and $App.State.isAdvancedOpen) { 915.0  } else { 600.0 }
    $targetH  = if ($App.State.isAdvancedOpen -or $App.State.isLogsOpen)  { 524.0  } else { 330.0 }
    $panelTop = if ($App.State.isAdvancedOpen -or $App.State.isLogsOpen)  { 424.0  } else { 230.0 }

    if ($App.State.isAdvancedOpen -or $App.State.isLogsOpen) {
        $App.UI.UnifiedPanel.CornerRadius    = New-Object System.Windows.CornerRadius(0,0,4,4)
        $App.UI.UnifiedPanel.BorderThickness = New-Object System.Windows.Thickness(1,0,1,1)
    } else {
        $App.UI.UnifiedPanel.CornerRadius    = New-Object System.Windows.CornerRadius(4)
        $App.UI.UnifiedPanel.BorderThickness = New-Object System.Windows.Thickness(1)
    }

    $advOpac = if ($App.State.isAdvancedOpen) {
        $App.UI.AdvancedBorder.CornerRadius = New-Object System.Windows.CornerRadius(4,4,0,0)
        $App.UI.AdvancedCanvas.Visibility = "Visible"
        1.0
    } else { 0.0 }

    if ($App.State.isLogsOpen) {
        $App.UI.LogsCanvas.Visibility = "Visible"
        if ($null -ne $App.Runtime.logTimer -and -not $App.Runtime.logTimer.IsEnabled) { $App.Runtime.logTimer.Start() }
        if ($App.State.isAdvancedOpen) {
            # Side mode
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(580.0,  $ts)))
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,   $ts)))
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(300.0,  $ts)))
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(474.0,  $ts)))
            $App.UI.logBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
            $App.UI.logBorder.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(300.0,  $ts)))
            $App.UI.logBorder.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(474.0,  $ts)))
            $App.UI.btnCloseLogs.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(272.0,  $ts)))
            $App.UI.lblTor1.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(30.0, $ts)))
            $App.UI.lblTor2.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(48.0, $ts)))
            $App.UI.lblTor3.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(66.0, $ts)))
            $App.UI.lblTor4.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(84.0, $ts)))
            $App.UI.lblTor5.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(155.0,$ts)))
            $App.UI.lblTor5.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(30.0, $ts)))
            $App.UI.lblTor6.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(155.0,$ts)))
            $App.UI.lblTor6.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(48.0, $ts)))
            $App.UI.lblTor7.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(155.0,$ts)))
            $App.UI.lblTor7.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(66.0, $ts)))
            $App.UI.lblTor8.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(155.0,$ts)))
            $App.UI.lblTor8.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(84.0, $ts)))
            $App.UI.logSeparator.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.logSeparator.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(110.0, $ts)))
            $App.UI.logSeparator.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(270.0, $ts)))
            $App.UI.logSeparator.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(1.0,   $ts)))
            $App.UI.lblConnTitle.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblConnTitle.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(120.0, $ts)))
            $App.UI.txtXrayLogs.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.txtXrayLogs.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,      (New-Object System.Windows.Media.Animation.DoubleAnimation(138.0, $ts)))
            $App.UI.txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(270.0, $ts)))
            $App.UI.txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(321.0, $ts)))
        } else {
            # Bottom mode
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(230.0, $ts)))
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(550.0, $ts)))
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(194.0, $ts)))
            $App.UI.logBorder.CornerRadius = New-Object System.Windows.CornerRadius(4,4,0,0)
            $App.UI.logBorder.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(550.0, $ts)))
            $App.UI.logBorder.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(194.0, $ts)))
            $App.UI.btnCloseLogs.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(522.0, $ts)))
            $App.UI.lblTor1.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblTor1.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(31.0,  $ts)))
            $App.UI.lblTor2.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblTor2.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(50.0,  $ts)))
            $App.UI.lblTor3.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblTor3.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(69.0,  $ts)))
            $App.UI.lblTor4.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblTor4.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(88.0,  $ts)))
            $App.UI.lblTor5.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblTor5.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(107.0, $ts)))
            $App.UI.lblTor6.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblTor6.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(126.0, $ts)))
            $App.UI.lblTor7.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblTor7.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(145.0, $ts)))
            $App.UI.lblTor8.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $App.UI.lblTor8.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(164.0, $ts)))
            $App.UI.logSeparator.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(152.0, $ts)))
            $App.UI.logSeparator.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(0.0,   $ts)))
            $App.UI.logSeparator.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(1.0,   $ts)))
            $App.UI.logSeparator.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(193.0, $ts)))
            $App.UI.lblConnTitle.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(169.0, $ts)))
            $App.UI.lblConnTitle.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(10.0,  $ts)))
            $App.UI.txtXrayLogs.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(169.0, $ts)))
            $App.UI.txtXrayLogs.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,      (New-Object System.Windows.Media.Animation.DoubleAnimation(30.0,  $ts)))
            $App.UI.txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(364.0, $ts)))
            $App.UI.txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(150.0, $ts)))
        }
        $logOpac = 1.0
    } else { $logOpac = 0.0; if ($null -ne $App.Runtime.logTimer) { $App.Runtime.logTimer.Stop() } }

    $App.UI.form.BeginAnimation([System.Windows.Window]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation($targetW, $ts)))
    $App.UI.form.BeginAnimation([System.Windows.Window]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($targetH, $ts)))
    $App.UI.AdvancedCanvas.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($advOpac, $ts)))
    $App.UI.LogsCanvas.BeginAnimation([System.Windows.UIElement]::OpacityProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation($logOpac, $ts)))
    $App.UI.UnifiedPanel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($panelTop, $ts)))

    if (-not $App.State.isAdvancedOpen) {
        $App.Runtime.hideAdvTimer = New-Object System.Windows.Threading.DispatcherTimer
        $App.Runtime.hideAdvTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $App.Runtime.hideAdvTimer.add_Tick({ $App.Runtime.hideAdvTimer.Stop(); if (-not $App.State.isAdvancedOpen) { $App.UI.AdvancedCanvas.Visibility = "Hidden" } }.GetNewClosure())
        $App.Runtime.hideAdvTimer.Start()
    }
    if (-not $App.State.isLogsOpen) {
        $App.Runtime.hideLogTimer = New-Object System.Windows.Threading.DispatcherTimer
        $App.Runtime.hideLogTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $App.Runtime.hideLogTimer.add_Tick({ $App.Runtime.hideLogTimer.Stop(); if (-not $App.State.isLogsOpen) { $App.UI.LogsCanvas.Visibility = "Hidden" } }.GetNewClosure())
        $App.Runtime.hideLogTimer.Start()
    }
}

#  LIVE LOGS TIMER
$App.Runtime.logTimer = New-Object System.Windows.Threading.DispatcherTimer
$App.Runtime.logTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
$App.Runtime.logTimer.add_Tick({
    try {
        if (-not $App.State.isLogsOpen -or $null -eq $App.UI.comboCount.SelectedItem) { return }
        $selCount = [int]($App.UI.comboCount.SelectedItem.Tag)
        if (-not $App.State.isEngineRunning) {
            for ($i = 1; $i -le 8; $i++) {
                $lbl = $App.UI.form.FindName("lblTor$i")
                if ($null -ne $lbl) {
                    $padded = $i.ToString().PadLeft(2,'0')
                    if ($i -le $selCount) { $lbl.Text = "Tor $padded`: Offline";  $lbl.Foreground = $App.UI.brDarkGray }
                    else                  { $lbl.Text = "Tor $padded`: Disabled"; $lbl.Foreground = $App.UI.brDarkGray }
                }
            }
            if ($null -ne $App.UI.txtXrayLogs) { $App.UI.txtXrayLogs.Text = "" }
            return
        }
        for ($i = 1; $i -le 8; $i++) {
            $lbl = $App.UI.form.FindName("lblTor$i")
            if ($null -eq $lbl) { continue }
            $padded = $i.ToString().PadLeft(2,'0')
            if ($i -gt $selCount) { $lbl.Text = "Tor $padded`: Disabled"; $lbl.Foreground = $App.UI.brDarkGray; continue }
            
            if ($lbl.Text -match "100%") { continue }

            $logPath = Get-AppPath "Data\Tors\Tor$i\tor.log"
            if (Test-Path $logPath) {
                try {
                    $fs = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $sr = New-Object System.IO.StreamReader($fs)
                    try {
                        $content = $sr.ReadToEnd()
                        $pm = [regex]::Matches($content, 'Bootstrapped (\d+)%')
                        if ($pm.Count -gt 0) {
                            $pct = $pm[$pm.Count-1].Groups[1].Value
                            $lbl.Text       = "Tor $padded`: $pct%"
                            $lbl.Foreground = if ($pct -eq "100") { $App.UI.brGreen } else { $App.UI.brOrange }
                        } else { $lbl.Text = "Tor $padded`: Booting..."; $lbl.Foreground = $App.UI.brGray }
                    } finally { $sr.Close(); $fs.Close() }
                } catch {}
            } else { $lbl.Text = "Tor $padded`: Waiting..."; $lbl.Foreground = $App.UI.brGray }
        }
        $xrayLog = Get-AppPath "Data\Xray\access.log"
        if (Test-Path $xrayLog) {
            try {
                $fs = New-Object System.IO.FileStream($xrayLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr = New-Object System.IO.StreamReader($fs)
                try {
                    $content = $sr.ReadToEnd()
                    $lines   = $content -split "`r?`n" | Where-Object { $_ -match "accepted|proxy" -and $_ -notmatch ":10899" }
                    $cleaned = ($lines | Select-Object -Last 15) | ForEach-Object { $_ -replace "^.*?\s\d{2}:\d{2}:\d{2}\s+(127\.0\.0\.1:\d+\s+)?","" }
                    if ($null -ne $App.UI.txtXrayLogs) { $App.UI.txtXrayLogs.Text = $cleaned -join "`n"; $App.UI.txtXrayLogs.ScrollToEnd() }
                } finally { $sr.Close(); $fs.Close() }
            } catch {}
        }
    } catch {}
}.GetNewClosure())

# LOG AUTO-CLEANER
$App.Runtime.logClearTimer = New-Object System.Windows.Threading.DispatcherTimer
$App.Runtime.logClearTimer.Interval = [TimeSpan]::FromHours(2)
$App.Runtime.logClearTimer.add_Tick({
    try {
        foreach ($lf in @("Data\Xray\access.log","Data\Xray\error.log")) {
            $fp = Get-AppPath $lf
            if (Test-Path $fp) {
                $fs = New-Object System.IO.FileStream($fp, [System.IO.FileMode]::Truncate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                $fs.Close()
            }
        }
    } catch {
        Clear-Content (Get-AppPath "Data\Xray\access.log") -ErrorAction SilentlyContinue
        Clear-Content (Get-AppPath "Data\Xray\error.log")  -ErrorAction SilentlyContinue
    }
})
$App.Runtime.logClearTimer.Start()

#  SYSTEM TRAY
if (Test-Path (Get-AppPath "icon.ico")) {
    $App.Runtime.sysTrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $App.Runtime.sysTrayIcon.Icon    = New-Object System.Drawing.Icon((Get-AppPath "icon.ico"))
    $App.Runtime.sysTrayIcon.Text    = "Tor Multiplexer"
    $App.Runtime.sysTrayIcon.Visible = $true
    $restoreAction = {
        $App.UI.form.Dispatcher.Invoke([System.Action]{
            $App.UI.form.ShowInTaskbar = $true
            $App.UI.form.WindowState   = [System.Windows.WindowState]::Normal
            $App.UI.form.Activate() | Out-Null
        })
    }
    $App.Runtime.sysTrayIcon.add_DoubleClick($restoreAction)
    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $trayMenu.Items.Add("Show Window").add_Click($restoreAction)
    $trayMenu.Items.Add("Exit Application").add_Click({ $App.UI.form.Dispatcher.Invoke([System.Action]{ $App.UI.form.Close() }) })
    $App.Runtime.sysTrayIcon.ContextMenuStrip = $trayMenu
}

$App.UI.form.add_StateChanged({
    if ($App.UI.form.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $App.UI.form.ShowInTaskbar = -not $App.Config.minimizeToTray
    }
})

#  COMBO EVENTS
$App.UI.comboBridge.add_SelectionChanged({
    if ($App.State.ignoreComboChange) { return }
    $selTag = $App.UI.comboBridge.SelectedItem.Tag
    if ($selTag -eq "Custom") {
        $App.State.ignoreComboChange = $true
        if (-not (Show-CustomBridgeDialog)) { Set-ComboSelectedTag $App.UI.comboBridge $App.State.previousBridge }
        else { $App.State.previousBridge = "Custom" }
        $App.State.ignoreComboChange = $false
    } else { $App.State.previousBridge = $selTag }
    if ($App.State.previousBridge -eq "snowflake" -and $App.Config.lastXrayMode -eq "VPN Mode") {
        $App.Config.lastXrayMode = "Proxy Mode"
        if ($App.State.isConnected) { Restart-Xray "Proxy Mode" }
    }
    $App.Config.lastBridge = $App.State.previousBridge
    Update-RoutingToggle
    Save-Config

    if ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
})

$App.UI.comboConfig.add_SelectionChanged({
    if ($App.State.ignoreComboChange) { return }
    $tag = $App.UI.comboConfig.SelectedItem.Tag
    if ($tag -eq "Custom") {
        $App.State.ignoreComboChange = $true
        if (-not (Show-ExitNodeDialog)) { Set-ComboSelectedTag $App.UI.comboConfig $App.State.previousConfig }
        else { $App.State.previousConfig = "Custom" }
        $App.State.ignoreComboChange = $false
    } elseif ($tag -eq "Expert") {
        $App.State.ignoreComboChange = $true
        if (-not (Show-ExpertConfigDialog)) { Set-ComboSelectedTag $App.UI.comboConfig $App.State.previousConfig }
        else { $App.State.previousConfig = "Expert" }
        $App.State.ignoreComboChange = $false
    } else { $App.State.previousConfig = $tag }
    Request-ConfigSave

    if ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
})

$App.UI.comboCount.add_SelectionChanged({
    Request-ConfigSave
    if (-not $App.State.isEngineRunning -or $App.State.isConnected) { return }
    
    $newCount = [int]($App.UI.comboCount.SelectedItem.Tag)
    $curCount = $App.Runtime.pollSelCount
    if ($null -eq $curCount) { $curCount = 0 }

    if ($newCount -lt $curCount) {
        for ($i = $newCount + 1; $i -le 8; $i++) {
            $torPid = $App.Runtime.torPids[$i - 1]
            if ($null -ne $torPid) {
                $proc = Get-Process -Id $torPid -ErrorAction SilentlyContinue
                if ($null -ne $proc) {
                    Stop-Process -Id $torPid -Force -ErrorAction SilentlyContinue
                    try { $proc.WaitForExit(300) | Out-Null } catch {} 
                }
                $App.Runtime.torPids[$i - 1] = $null
            }
            $lbl = $App.UI.form.FindName("lblTor$i")
            $pad = $i.ToString().PadLeft(2,'0')
            if ($null -ne $lbl) { $lbl.Text = "Tor $pad`: Disabled"; $lbl.Foreground = $App.UI.brDarkGray }
        }
        $App.Runtime.pollSelCount = $newCount
        Format-HAProxyConfig $newCount

    } elseif ($newCount -gt $curCount -and $null -ne $App.Runtime.pollSelCount) {
        $App.Runtime.pollSelCount = $newCount
        Format-HAProxyConfig $newCount

        $isInBootstrapPhase = ($null -ne $App.Runtime.bootstrapTimer -and $App.Runtime.bootstrapTimer.IsEnabled)
        
        if ($null -eq $App.Runtime.staggerQueue) { $App.Runtime.staggerQueue = [System.Collections.Generic.List[int]]::new() }

        for ($i = $curCount + 1; $i -le $newCount; $i++) {
            $lbl = $App.UI.form.FindName("lblTor$i")
            $pad = $i.ToString().PadLeft(2,'0')
            if ($null -ne $lbl) { $lbl.Text = "Tor $pad`: Waiting..."; $lbl.Foreground = $App.UI.brGray }
            
            $path = Get-AppPath "Data\Tors\Tor$i"
            Remove-Item "$path\tor.log" -Force -ErrorAction SilentlyContinue
            
            if ($isInBootstrapPhase) { $App.Runtime.staggerQueue.Add($i) }
        }

        if ($isInBootstrapPhase -and $App.Runtime.staggerQueue.Count -gt 0) {
            if ($null -ne $App.Runtime.staggerTimer) { $App.Runtime.staggerTimer.Stop() }
            
            $App.Runtime.staggerTimer = New-Object System.Windows.Threading.DispatcherTimer
            $App.Runtime.staggerTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
            $App.Runtime.staggerTimer.add_Tick({
                if ($App.State.abortBoot -or -not $App.State.isEngineRunning -or $App.Runtime.staggerQueue.Count -eq 0) {
                    $App.Runtime.staggerTimer.Stop(); return
                }
                
                $i = $App.Runtime.staggerQueue[0]
                $App.Runtime.staggerQueue.RemoveAt(0)
                
                $path       = Get-AppPath "Data\Tors\Tor$i"
                $_torrcFile = "torrc"
                $_selConfig = if ($App.UI.comboConfig.SelectedItem.Tag -eq "Custom") { "Custom" } elseif ($App.UI.comboConfig.SelectedItem.Tag -eq "Expert") { "Expert" } else { "Optimized" }

                Remove-Item "$path\tor.log" -Force -ErrorAction SilentlyContinue

                if (Test-Path "$path\$_torrcFile") {
                    $cleanCfg = Build-TorrcConfig -TorrcFile $_torrcFile -SelBridge $App.Runtime.pollSelBridge -SelConfig $_selConfig -Path $path
                    $cleanCfg | Set-Content "$path\$_torrcFile"
                    
                    try {
                        $torProc = Start-ProcessDirect -FilePath (Get-AppPath "Data\TorBin\tor.exe") -Arguments "-f $_torrcFile" -WorkingDirectory $path -Hidden $true -PassThru $true
                        if ($null -ne $torProc) { $App.Runtime.torPids[$i - 1] = $torProc.Id }
                    } catch {}
                }

                if ($App.Runtime.staggerQueue.Count -eq 0) { $App.Runtime.staggerTimer.Stop() }
            }.GetNewClosure())
            $App.Runtime.staggerTimer.Start()
        }
    }
})

#  BUTTON EVENTS
$App.UI.btnStatsPanel.add_Click({ if ($App.State.isConnected) { Start-GeoPing } })
$App.UI.btnAction.add_Click({
    if ($App.State.isConnected -or $App.UI.btnActionMainText.Text -eq "CONNECTING") { Stop-AllEngines } else { Start-Engines }
})
$App.UI.btnAutoStartMain.Add_Click({
    $App.Config.autoStart = -not $App.Config.autoStart
    Set-AutoConnectState $App.Config.autoStart $true
    Request-ConfigSave
})
$App.UI.btnAdvMain.Add_Click({
    $App.State.isAdvancedOpen = -not $App.State.isAdvancedOpen
    Set-AdvState $App.State.isAdvancedOpen
    Update-WindowSize
})
$App.UI.btnDesktop.Add_Click({
    try {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\TorMultiplexer.lnk")
        $sc.TargetPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $sc.WorkingDirectory = $App.Config.baseDir
        $sc.Save()
        Show-ToastNotification "Desktop shortcut created successfully!" "Success"
    } catch { Show-ToastNotification "Failed to create shortcut." }
})
$App.UI.btnCloseLogs.add_Click({
    if ($App.State.isLogsOpen) {
        $App.State.isLogsOpen = $false
        Set-WpfToggleState $App.UI.btnLogsTog $false "HIDE" "SHOW"
        Update-WindowSize; Request-ConfigSave
    }
})

$toggleModeAction = {
    param($mode)
    if ($App.Config.lastXrayMode -ne $mode) {
        $App.Config.lastXrayMode = $mode
        Update-RoutingToggle; Request-ConfigSave
        if ($App.State.isConnected) { Restart-Xray $mode }
    }
}
$App.UI.btnProxyMode.add_Click({  & $toggleModeAction "Proxy Mode"  })
$App.UI.btnClearProxy.add_Click({ & $toggleModeAction "Clear Proxy" })
$App.UI.btnVpnMode.add_Click({  
    if ($App.UI.comboBridge.SelectedItem.Tag -eq "snowflake") { return }
    & $toggleModeAction "VPN Mode"    
})

$App.UI.btnV2rayTog.Add_Click({
    if (-not $App.Config.enableV2rayChain -and [string]::IsNullOrWhiteSpace($App.Config.v2rayChainJson)) {
        if (-not (Show-V2rayDialog)) { return }
    }
    $App.Config.enableV2rayChain = -not $App.Config.enableV2rayChain
    Set-WpfToggleState $App.UI.btnV2rayTog $App.Config.enableV2rayChain
    Request-ConfigSave
    if ($App.State.isConnected) { 
        if ($App.Config.lastXrayMode -eq "VPN Mode") { Show-ToastNotification "Please reconnect to apply the changes safely." }
        else { Restart-Xray $App.Config.lastXrayMode }
    } elseif ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
})
$App.UI.btnV2rayLbl.Add_Click({ Show-V2rayDialog | Out-Null; Set-WpfToggleState $App.UI.btnV2rayTog $App.Config.enableV2rayChain })

$App.UI.btnDirectTog.Add_Click({
    $newState = -not $App.Config.enableDirect
    if ($newState -and [string]::IsNullOrWhiteSpace($App.Config.lastManualSplit) -and [string]::IsNullOrWhiteSpace($App.Config.lastAppSplit)) {
        if (-not (Show-DirectRulesDialog)) { return }
    }
    $App.Config.enableDirect = $newState
    Set-WpfToggleState $App.UI.btnDirectTog $App.Config.enableDirect
    Request-ConfigSave
    if ($App.State.isConnected) { 
        if ($App.Config.lastXrayMode -eq "VPN Mode") { Show-ToastNotification "Please reconnect to apply the changes safely." }
        else { Restart-Xray $App.Config.lastXrayMode }
    } elseif ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
})
$App.UI.btnDirectLbl.Add_Click({ Show-DirectRulesDialog | Out-Null })

$App.UI.btnOutboundTog.Add_Click({
    $newState = -not $App.Config.enableOutboundProxy
    if ($newState -and [string]::IsNullOrWhiteSpace($App.Config.outboundProxyAddress)) {
        if (-not (Show-OutboundProxyDialog)) { return }
    }
    $App.Config.enableOutboundProxy = $newState
    Set-WpfToggleState $App.UI.btnOutboundTog $App.Config.enableOutboundProxy
    Request-ConfigSave

    if ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
})

$App.UI.btnOutboundLbl.Add_Click({ 
    if (Show-OutboundProxyDialog) {
        Set-WpfToggleState $App.UI.btnOutboundTog $App.Config.enableOutboundProxy
        if ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
    }
})

$App.UI.btnDohTog.Add_Click({
    if ($App.Config.enableUpstreamDoh) {
        $App.Config.enableUpstreamDoh = $false
        Set-WpfToggleState $App.UI.btnDohTog $false; Request-ConfigSave; Evaluate-ProxyExclusivity
    } else {
        if (-not (Show-DohDialog)) { Set-WpfToggleState $App.UI.btnDohTog $false }
        else {
            $App.Config.enableUpstreamDoh = $true
            Set-WpfToggleState $App.UI.btnDohTog $true
            Request-ConfigSave
            Evaluate-ProxyExclusivity
        }
    }

    # Smart Restart Logic
    if ($App.State.isConnected) { 
        if ($App.Config.lastXrayMode -eq "VPN Mode") { Show-ToastNotification "Please reconnect to apply the changes safely." }
        else { Restart-Xray $App.Config.lastXrayMode }
    } elseif ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
})

$App.UI.btnDohLbl.Add_Click({ 
    if (Show-DohDialog) {
        Set-WpfToggleState $App.UI.btnDohTog $App.Config.enableUpstreamDoh
        
        # Smart Restart Logic
        if ($App.State.isConnected) { 
            if ($App.Config.lastXrayMode -eq "VPN Mode") { Show-ToastNotification "Please reconnect to apply the changes safely." }
            else { Restart-Xray $App.Config.lastXrayMode }
        } elseif ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
    }
})

# Simple toggles
$App.UI.btnBootTog.Add_Click({
    $App.Config.launchOnBoot = -not $App.Config.launchOnBoot
    Set-WpfToggleState $App.UI.btnBootTog $App.Config.launchOnBoot; Update-BootShortcut; Request-ConfigSave
})
$App.UI.btnDebugTog.Add_Click({
    $App.Config.debugMode = -not $App.Config.debugMode
    Set-WpfToggleState $App.UI.btnDebugTog $App.Config.debugMode
    Request-ConfigSave  
})
$App.UI.btnTrayTog.Add_Click({
    $App.Config.minimizeToTray = -not $App.Config.minimizeToTray
    Set-WpfToggleState $App.UI.btnTrayTog $App.Config.minimizeToTray; Request-ConfigSave
})
$App.UI.btnLogsTog.Add_Click({
    $App.State.isLogsOpen = -not $App.State.isLogsOpen
    Set-WpfToggleState $App.UI.btnLogsTog $App.State.isLogsOpen "HIDE" "SHOW"; Update-WindowSize; Request-ConfigSave
})
$App.UI.btnAdBlockTog.Add_Click({
    $App.Config.enableAdBlock = -not $App.Config.enableAdBlock
    Set-WpfToggleState $App.UI.btnAdBlockTog $App.Config.enableAdBlock; Request-ConfigSave
    if ($App.State.isConnected) { 
            if ($App.Config.lastXrayMode -eq "VPN Mode") { Show-ToastNotification "Please reconnect to apply the changes safely." }
            else { Restart-Xray $App.Config.lastXrayMode }
        } elseif ($App.State.isEngineRunning) { Show-ToastNotification "Please reconnect to apply the changes." }
})

# Label -> toggle relay
$App.UI.btnBootLbl.Add_Click({    $App.UI.btnBootTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$App.UI.btnDebugLbl.Add_Click({   $App.UI.btnDebugTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$App.UI.btnTrayLbl.Add_Click({    $App.UI.btnTrayTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$App.UI.btnLogsLbl.Add_Click({    $App.UI.btnLogsTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$App.UI.btnAdBlockLbl.Add_Click({ $App.UI.btnAdBlockTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

#  WINDOW CLOSE
$App.UI.form.add_Closing({
    if ($null -ne $App.Runtime.saveDebounceTimer -and $App.Runtime.saveDebounceTimer.IsEnabled) {
        $App.Runtime.saveDebounceTimer.Stop()
        Save-Config
    }
    if ($null -ne $App.Runtime.statsTimer)      { $App.Runtime.statsTimer.Stop() }
    if ($null -ne $App.Runtime.sessionClockTimer) { $App.Runtime.sessionClockTimer.Stop() }
    if ($null -ne $App.Runtime.logTimer)        { $App.Runtime.logTimer.Stop() }
    if ($null -ne $App.Runtime.logClearTimer)   { $App.Runtime.logClearTimer.Stop() }
    if ($null -ne $App.Runtime.ringTimer)          { $App.Runtime.ringTimer.Stop() }
    if ($null -ne $App.Runtime.waveHoldTimer)      { $App.Runtime.waveHoldTimer.Stop() }
    if ($null -ne $App.Runtime.hideAdvTimer)     { $App.Runtime.hideAdvTimer.Stop() }
    if ($null -ne $App.Runtime.hideLogTimer)     { $App.Runtime.hideLogTimer.Stop() }
    if ($null -ne $App.Runtime.pingTimer)        { $App.Runtime.pingTimer.Stop() }
    try {
        if ($null -ne $App.Runtime.updateDlClient) {
            $App.Runtime.updateDlClient.CancelAsync()
            $App.Runtime.updateDlClient.Dispose()
            $App.Runtime.updateDlClient = $null
        }
    } catch {}
    try {
        if ($null -ne $App.Runtime.geoWebClient) {
            $App.Runtime.geoWebClient.CancelAsync()
            $App.Runtime.geoWebClient.Dispose()
            $App.Runtime.geoWebClient = $null
        }
    } catch {}
    Stop-AllEngines $true
    if ($null -ne $App.Runtime.sysTrayIcon) {
        $App.Runtime.sysTrayIcon.Visible = $false
        $App.Runtime.sysTrayIcon.Dispose()
    }
})

$App.UI.form.add_Closed({ [Environment]::Exit(0) })

#  CONTENT RENDERED 
$App.UI.form.add_ContentRendered({
    try {
        if ($App.State.appInitialized) { return }
        $App.State.appInitialized = $true

        if ($null -ne $App.UI.borderClip) {
            $_clipGeom.Rect = New-Object System.Windows.Rect(
                0, 0,
                $App.UI.borderClip.ActualWidth,
                $App.UI.borderClip.ActualHeight)
            $App.UI.borderClip.Clip = $_clipGeom
        }

        $splashHold = New-Object System.Windows.Threading.DispatcherTimer
        $splashHold.Interval = [TimeSpan]::FromMilliseconds(900)
        $splashHold.add_Tick({
            $splashHold.Stop()
            $fadeDur  = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(650))
            $fadeAnim = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, $fadeDur)
            $fadeAnim.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase
            $fadeAnim.add_Completed({
                $App.UI.splashOverlay.Visibility       = "Collapsed"
                $App.UI.splashOverlay.IsHitTestVisible = $false
                if ($App.State.isLogsOpen) { Update-WindowSize }
            }.GetNewClosure())
            $App.UI.splashOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeAnim)
            if ($null -ne $App.UI.windowOutline) {
                $outlineAnim = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, $fadeDur)
                $outlineAnim.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase
                $App.UI.windowOutline.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $outlineAnim)
            }
        }.GetNewClosure())
        $splashHold.Start()

        # Normal startup tasks 
        Check-UpdateSilent
        if ($App.Config.autoStart) {
            $animT = New-Object System.Windows.Threading.DispatcherTimer
            $animT.Interval = [TimeSpan]::FromMilliseconds(150)
            $animT.add_Tick({ $animT.Stop(); Set-AutoConnectState $true $true }.GetNewClosure())
            $animT.Start()
        }
        if ($App.Config.autoStart -and -not $App.State.isFirstLaunch) {
            $bootT = New-Object System.Windows.Threading.DispatcherTimer
            $bootT.Interval = [TimeSpan]::FromMilliseconds(500)
            $bootT.add_Tick({
                $bootT.Stop()
                if (-not $App.State.abortBoot) { Start-Engines }
            }.GetNewClosure())
            $bootT.Start()
        }
    } catch {
        $msg = "Error: $($_.Exception.Message)`nStack: $($_.ScriptStackTrace)"
        $msg | Out-File (Get-AppPath "debug_log.txt") -Append
        [System.Windows.MessageBox]::Show($msg, "CRASH DETAIL")
    }
})

#  LAUNCH
Update-RingAnimation -State "Idle"
if ($null -ne $App.UI.form) {
    try { $App.UI.form.ShowDialog() | Out-Null }
    catch { [System.Windows.Forms.MessageBox]::Show("ShowDialog failed: $($_.Exception.Message)") }
} else {
    [System.Windows.Forms.MessageBox]::Show("Main Form is NULL - XAML parse failed.")
}
