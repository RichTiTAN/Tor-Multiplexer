# --- ADMIN ELEVATION (SILENT) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    [Environment]::Exit(0)
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- LOCK SCOPE FOR EVENT HANDLERS ---
$global:baseDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($global:baseDir)) { $global:baseDir = (Get-Location).Path }

$global:scriptPath = $PSCommandPath
if ([string]::IsNullOrEmpty($global:scriptPath)) { $global:scriptPath = $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrEmpty($global:scriptPath)) { $global:scriptPath = Join-Path $global:baseDir "multiplexer.ps1" }

# --- SYSTEM PROXY REFRESH API ---
if (-not ("Win32.WinInet" -as [type])) {
    $MethodDefinition = @'
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
'@
    Add-Type -MemberDefinition $MethodDefinition -Name 'WinInet' -Namespace 'Win32' -PassThru | Out-Null
}

# --- VERSION CONTROL ---
$global:currentVersion = "4.6" 
$repoRawUrl = "https://raw.githubusercontent.com/RichTiTAN/Tor-Multiplexer/main/multiplexer.ps1"

# --- GLOBAL BOOT FLAG & STATE ---
$global:abortBoot = $false
$global:isConnected = $false
$global:cmdDebugPid = $null 
$global:cmdDebugPid2 = $null 
$global:lastTotalBytes = 0
$global:sessionDataBytes = 0

# --- CONFIGURATION & PATHS ---
$cfgFile = "$global:baseDir\multiplexer_settings.json"
$xrayDir = "$global:baseDir\Data\Xray"
$haPath  = "$global:baseDir\Data\HAproxy"
$sbDir   = "$global:baseDir\Data\sing_box"

# --- DYNAMIC BUTTON TEXT STATES ---
$global:btnMainText = "CONNECT"
$global:btnSubText  = "(click to start)"

$autoStart = $true; $launchOnBoot = $false; $lastConfig = "Stable (default)"; $lastBridge = "meek_lite"; $lastCount = "6 (default)"; $global:lastXrayMode = "Proxy Mode"; $global:lastManualSplit = ""; $global:enableDirect = $false; $global:customBridgeLine = ""; $global:v2rayChainJson = ""; $global:enableV2rayChain = $false
$global:outboundProxyAddress = ""; $global:outboundProxyPort = ""; $global:outboundProxyType = "SOCKS5"; $global:enableOutboundProxy = $false
$global:outboundProxyUser = ""; $global:outboundProxyPass = ""; $global:enableOutboundAuth = $false
$isFirstLaunch = $true 

if (Test-Path $cfgFile) {
    $isFirstLaunch = $false
    try {
        $s = Get-Content $cfgFile -Raw | ConvertFrom-Json
        if ($null -ne $s.AutoStart) { $autoStart = [bool]$s.AutoStart }
        if ($null -ne $s.LaunchOnBoot) { $launchOnBoot = [bool]$s.LaunchOnBoot }
        if ($null -ne $s.LastConfig) { $lastConfig = if ($s.LastConfig -match "Fast") { "Fast" } else { "Stable (default)" } }
        if ($null -ne $s.SelectedBridge) { $lastBridge = [string]$s.SelectedBridge }
        if ($null -ne $s.InstanceCount) { 
            $c = [int]$s.InstanceCount
            $lastCount = if ($c -eq 6) { "6 (default)" } else { [string]$c }
        }
        if ($null -ne $s.ManualSplit) { $global:lastManualSplit = [string]$s.ManualSplit }
        if ($null -ne $s.EnableDirect) { $global:enableDirect = [bool]$s.EnableDirect }
        if ($null -ne $s.CustomBridgeLine) { $global:customBridgeLine = [string]$s.CustomBridgeLine }
        if ($null -ne $s.V2rayChainJson) { $global:v2rayChainJson = [string]$s.V2rayChainJson }
        if ($null -ne $s.EnableV2rayChain) { $global:enableV2rayChain = [bool]$s.EnableV2rayChain }
        if ($null -ne $s.EnableOutboundProxy) { $global:enableOutboundProxy = [bool]$s.EnableOutboundProxy }
        if ($null -ne $s.OutboundProxyAddress) { $global:outboundProxyAddress = [string]$s.OutboundProxyAddress }
        if ($null -ne $s.OutboundProxyPort) { $global:outboundProxyPort = [string]$s.OutboundProxyPort }
        if ($null -ne $s.OutboundProxyType) { $global:outboundProxyType = [string]$s.OutboundProxyType }
        if ($null -ne $s.OutboundProxyUser) { $global:outboundProxyUser = [string]$s.OutboundProxyUser }
        if ($null -ne $s.OutboundProxyPass) { $global:outboundProxyPass = [string]$s.OutboundProxyPass }
        if ($null -ne $s.EnableOutboundAuth) { $global:enableOutboundAuth = [bool]$s.EnableOutboundAuth }
        if ($null -ne $s.XrayMode) { 
            if ($s.XrayMode -eq "Clear Proxy" -or $s.XrayMode -eq "None") { $global:lastXrayMode = "Clear Proxy" }
            elseif ($s.XrayMode -eq "VPN Mode") { $global:lastXrayMode = "VPN Mode" }
            else { $global:lastXrayMode = "Proxy Mode" }
        }
    } catch {}
}

# --- ASSET INTEGRITY CHECK ---
$global:hasVpnComponents = $true
if (-not (Test-Path "$sbDir\sing-box.exe")) {
    $global:hasVpnComponents = $false
    if ($global:lastXrayMode -eq "VPN Mode") { $global:lastXrayMode = "Proxy Mode" } # Graceful fallback
}

# --- THE ULTIMATE IP EXTRACTION ---
$lanIp = "UNKNOWN"
$ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { 
    $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notmatch '^127\.' -and $_.ToString() -notmatch '^169\.254\.' 
}
if ($ips) { $lanIp = $ips[0].ToString() }

# --- THEME SETUP ---
$classyFont = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$smallFont  = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$microFont  = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular) 
$statsFont  = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$colorBg = [System.Drawing.ColorTranslator]::FromHtml("#1A1A1B"); $colorBtn = [System.Drawing.ColorTranslator]::FromHtml("#3A3F44"); $colorText = [System.Drawing.ColorTranslator]::FromHtml("#E2E8F0"); $colorIP = [System.Drawing.ColorTranslator]::FromHtml("#A0AEC0") 

# Desaturated Custom Toggle Palette
$colorTogOn  = [System.Drawing.ColorTranslator]::FromHtml("#4E7A5E") 
$colorTogOff = [System.Drawing.ColorTranslator]::FromHtml("#8B4A4A")
$colorTogLbl = [System.Drawing.ColorTranslator]::FromHtml("#2D3748")

# --- SAFE RELATIVE BRIDGE DATABASE ---
$bridgeData = @{
    "meek_lite" = @{ "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN") }
    "obfs4" = @{ "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0", "Bridge obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0", "Bridge obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0", "Bridge obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0", "Bridge obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=1", "Bridge obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1", "Bridge obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1") }
    "snowflake" = @{ "plugin" = "ClientTransportPlugin snowflake exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn", "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn") }
}

# --- CORNER FIX (Uses true Diameter mapping) ---
function Set-RoundedCorners($control, $radius) {
    $d = $radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($control.Width - $d, 0, $d, $d, 270, 90)
    $path.AddArc($control.Width - $d, $control.Height - $d, $d, $d, 0, 90)
    $path.AddArc(0, $control.Height - $d, $d, $d, 90, 90)
    $path.CloseAllFigures()
    $control.Region = New-Object System.Drawing.Region($path)
}

function Set-ToggleState($btn, $state, $onText="Enabled", $offText="Disabled") {
    if ($state) { $btn.Text = $onText; $btn.BackColor = $colorTogOn }
    else { $btn.Text = $offText; $btn.BackColor = $colorTogOff }
}

function Save-Config {
    $selConfig = if ($comboConfig.SelectedItem.ToString() -match "Stable") { "Stable" } else { "Fast" }
    $selCount = [int]($comboCount.SelectedItem.ToString().Replace(" (default)", ""))
    @{ AutoStart = [bool]$autoStart; LaunchOnBoot = [bool]$launchOnBoot; LastConfig = $selConfig; SelectedBridge = $comboBridge.SelectedItem; InstanceCount = $selCount; XrayMode = $global:lastXrayMode; ManualSplit = $global:lastManualSplit; EnableDirect = $global:enableDirect; CustomBridgeLine = $global:customBridgeLine; EnableV2rayChain = $global:enableV2rayChain; V2rayChainJson = $global:v2rayChainJson; EnableOutboundProxy = $global:enableOutboundProxy; OutboundProxyAddress = $global:outboundProxyAddress; OutboundProxyPort = $global:outboundProxyPort; OutboundProxyType = $global:outboundProxyType; OutboundProxyUser = $global:outboundProxyUser; OutboundProxyPass = $global:outboundProxyPass; EnableOutboundAuth = $global:enableOutboundAuth } | ConvertTo-Json -Depth 10 | Set-Content $cfgFile
}

function Update-BootShortcut {
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "TorMultiplexer.lnk"
    if ($launchOnBoot) {
        try { 
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($shortcutPath)
            $Shortcut.TargetPath = Join-Path $global:baseDir "Launch Multiplexer.vbs"
            $Shortcut.WorkingDirectory = $global:baseDir
            $Shortcut.Save() 
        } catch { 
            [System.Windows.Forms.MessageBox]::Show("Failed to create Startup shortcut.", "Error", 0, 16)
            $script:launchOnBoot = $false; Set-ToggleState $btnBootTog $false
        }
    } else { if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue } }
}

# --- SETUP THE WINDOW ---
$form = New-Object Windows.Forms.Form
$form.Text = "Tor Multiplexer - v$global:currentVersion"
$form.ClientSize = New-Object Drawing.Size(600, 265)
$form.StartPosition = "CenterScreen"
$form.BackColor = $colorBg

# Clean and Instant Form Kill Switch
$form.Add_FormClosing({ Stop-AllEngines $true })
$form.Add_FormClosed({ [Environment]::Exit(0) })


# --- MODAL DIALOGS ---
function Show-DirectRulesDialog {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = "Split Tunneling Rules"; $dlg.Size = New-Object Drawing.Size(420, 220); $dlg.StartPosition = "CenterParent"; $dlg.BackColor = $colorBg; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = "Enter Domains or IPs to bypass Tor (comma separated):"; $lbl.ForeColor = $colorText; $lbl.Location = "15,15"; $lbl.AutoSize = $true
    $txt = New-Object Windows.Forms.TextBox; $txt.Location = "15,40"; $txt.Size = "375, 80"; $txt.Multiline = $true; $txt.ScrollBars = "Vertical"; $txt.BackColor = "#2D3748"; $txt.ForeColor = "White"; $txt.Text = $global:lastManualSplit; $txt.BorderStyle = "FixedSingle"
    $btnOk = New-Object Windows.Forms.Button; $btnOk.Text = "Save"; $btnOk.Location = "300, 135"; $btnOk.Size = "90,30"; $btnOk.DialogResult = "OK"; $btnOk.BackColor = $colorBtn; $btnOk.ForeColor = $colorText; $btnOk.FlatStyle = "Flat"
    $dlg.Controls.AddRange(@($lbl, $txt, $btnOk)); $dlg.AcceptButton = $btnOk
    if ($dlg.ShowDialog() -eq "OK") { $global:lastManualSplit = $txt.Text.Trim(); return $true }
    $dlg.Dispose(); return $false
}

function Show-OutboundProxyDialog {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = "Outbound Proxy Configuration"; $dlg.Size = New-Object Drawing.Size(335, 230); $dlg.StartPosition = "CenterParent"; $dlg.BackColor = $colorBg; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
    
    $lblAddr = New-Object Windows.Forms.Label; $lblAddr.Text = "Address/IP:"; $lblAddr.ForeColor = $colorText; $lblAddr.Location = "15,15"; $lblAddr.AutoSize = $true
    $txtAddr = New-Object Windows.Forms.TextBox; $txtAddr.Location = "15,35"; $txtAddr.Size = "180, 25"; $txtAddr.BackColor = "#2D3748"; $txtAddr.ForeColor = "White"; $txtAddr.Text = $global:outboundProxyAddress; $txtAddr.BorderStyle = "FixedSingle"
    
    $lblPort = New-Object Windows.Forms.Label; $lblPort.Text = "Port:"; $lblPort.ForeColor = $colorText; $lblPort.Location = "210,15"; $lblPort.AutoSize = $true
    $txtPort = New-Object Windows.Forms.TextBox; $txtPort.Location = "210,35"; $txtPort.Size = "85, 25"; $txtPort.BackColor = "#2D3748"; $txtPort.ForeColor = "White"; $txtPort.Text = $global:outboundProxyPort; $txtPort.BorderStyle = "FixedSingle"
    
    $tempType = $global:outboundProxyType
    if ([string]::IsNullOrEmpty($tempType)) { $tempType = "SOCKS5" }

    $btnHttps = New-Object Windows.Forms.Button; $btnHttps.Text = "HTTPS"; $btnHttps.Location = "15, 75"; $btnHttps.Size = "135, 30"; $btnHttps.FlatStyle = "Flat"; $btnHttps.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnHttps 4; $btnHttps.ForeColor = "White"; $btnHttps.Cursor = "Hand"
    $btnSocks = New-Object Windows.Forms.Button; $btnSocks.Text = "SOCKS5"; $btnSocks.Location = "160, 75"; $btnSocks.Size = "135, 30"; $btnSocks.FlatStyle = "Flat"; $btnSocks.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnSocks 4; $btnSocks.ForeColor = "White"; $btnSocks.Cursor = "Hand"

    function Update-TypeButtons {
        if ($tempType -eq "HTTPS") { $btnHttps.BackColor = $colorTogOn; $btnSocks.BackColor = $colorTogOff }
        else { $btnSocks.BackColor = $colorTogOn; $btnHttps.BackColor = $colorTogOff }
    }
    Update-TypeButtons
    $btnHttps.Add_Click({ $tempType = "HTTPS"; Update-TypeButtons })
    $btnSocks.Add_Click({ $tempType = "SOCKS5"; Update-TypeButtons })

    # Authentication Toggle (Red = Hide, Green = Show)
    $btnAuthLbl = New-Object Windows.Forms.Button; $btnAuthLbl.Location = "15, 120"; $btnAuthLbl.Size = "180, 25"; $btnAuthLbl.Text = "Authentication"; $btnAuthLbl.BackColor = $colorTogLbl; $btnAuthLbl.ForeColor = $colorText; $btnAuthLbl.FlatStyle = "Flat"; $btnAuthLbl.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAuthLbl 4; $btnAuthLbl.Font = $smallFont
    $btnAuthTog = New-Object Windows.Forms.Button; $btnAuthTog.Location = "200, 120"; $btnAuthTog.Size = "95, 25"; $btnAuthTog.FlatStyle = "Flat"; $btnAuthTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAuthTog 4; $btnAuthTog.Font = $smallFont; $btnAuthTog.ForeColor = $colorText; $btnAuthTog.Cursor = "Hand"
    Set-ToggleState $btnAuthTog $global:enableOutboundAuth "Show" "Hide"

    $lblUser = New-Object Windows.Forms.Label; $lblUser.Text = "Username:"; $lblUser.ForeColor = $colorText; $lblUser.Location = "15,160"; $lblUser.AutoSize = $true
    $txtUser = New-Object Windows.Forms.TextBox; $txtUser.Location = "15,180"; $txtUser.Size = "135, 25"; $txtUser.BackColor = "#2D3748"; $txtUser.ForeColor = "White"; $txtUser.Text = $global:outboundProxyUser; $txtUser.BorderStyle = "FixedSingle"
    
    $lblPass = New-Object Windows.Forms.Label; $lblPass.Text = "Password:"; $lblPass.ForeColor = $colorText; $lblPass.Location = "160,160"; $lblPass.AutoSize = $true
    $txtPass = New-Object Windows.Forms.TextBox; $txtPass.Location = "160,180"; $txtPass.Size = "135, 25"; $txtPass.BackColor = "#2D3748"; $txtPass.ForeColor = "White"; $txtPass.Text = $global:outboundProxyPass; $txtPass.BorderStyle = "FixedSingle"

    $btnOk = New-Object Windows.Forms.Button; $btnOk.Text = "Save"; $btnOk.Size = "80,30"; $btnOk.DialogResult = "OK"; $btnOk.BackColor = $colorBtn; $btnOk.ForeColor = $colorText; $btnOk.FlatStyle = "Flat"; Set-RoundedCorners $btnOk 4
    $btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Size = "80,30"; $btnCancel.DialogResult = "Cancel"; $btnCancel.BackColor = $colorBtn; $btnCancel.ForeColor = $colorText; $btnCancel.FlatStyle = "Flat"; Set-RoundedCorners $btnCancel 4

    function Evaluate-AuthView {
        $isAuthOn = ($btnAuthTog.Text -eq "Show")
        $lblUser.Visible = $isAuthOn; $txtUser.Visible = $isAuthOn
        $lblPass.Visible = $isAuthOn; $txtPass.Visible = $isAuthOn
        if ($isAuthOn) { 
            $dlg.ClientSize = New-Object Drawing.Size(335, 280)
            $btnOk.Location = "120, 230"; $btnCancel.Location = "215, 230"
        } else { 
            $dlg.ClientSize = New-Object Drawing.Size(335, 210)
            $btnOk.Location = "120, 160"; $btnCancel.Location = "215, 160"
        }
    }
    Evaluate-AuthView

    $btnAuthTog.Add_Click({ 
        $newState = ($btnAuthTog.Text -eq "Hide") # If currently red/hide, switch to true
        Set-ToggleState $btnAuthTog $newState "Show" "Hide"
        Evaluate-AuthView 
    })
    $btnAuthLbl.Add_Click({ $btnAuthTog.PerformClick() })

    $dlg.Controls.AddRange(@($lblAddr, $txtAddr, $lblPort, $txtPort, $btnHttps, $btnSocks, $btnAuthLbl, $btnAuthTog, $lblUser, $txtUser, $lblPass, $txtPass, $btnOk, $btnCancel))
    $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel

    if ($dlg.ShowDialog() -eq "OK") { 
        $global:outboundProxyAddress = $txtAddr.Text.Trim()
        $global:outboundProxyPort = $txtPort.Text.Trim()
        $global:outboundProxyType = $tempType
        $global:enableOutboundAuth = ($btnAuthTog.Text -eq "Show")
        $global:outboundProxyUser = $txtUser.Text.Trim()
        $global:outboundProxyPass = $txtPass.Text.Trim()
        return $true 
    }
    $dlg.Dispose(); return $false
}

function Show-CustomBridgeDialog {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = "Custom Bridge Configuration"; $dlg.Size = New-Object Drawing.Size(420, 220); $dlg.StartPosition = "CenterParent"; $dlg.BackColor = $colorBg; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = "Paste your custom bridge configurations here:"; $lbl.ForeColor = $colorText; $lbl.Location = "15,15"; $lbl.AutoSize = $true
    $txt = New-Object Windows.Forms.TextBox; $txt.Location = "15,40"; $txt.Size = "375, 80"; $txt.Multiline = $true; $txt.ScrollBars = "Vertical"; $txt.BackColor = "#2D3748"; $txt.ForeColor = "White"; $txt.Text = $global:customBridgeLine; $txt.BorderStyle = "FixedSingle"
    $btnOk = New-Object Windows.Forms.Button; $btnOk.Text = "Save"; $btnOk.Location = "210, 135"; $btnOk.Size = "80,30"; $btnOk.DialogResult = "OK"; $btnOk.BackColor = $colorBtn; $btnOk.ForeColor = $colorText; $btnOk.FlatStyle = "Flat"
    $btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = "300, 135"; $btnCancel.Size = "90,30"; $btnCancel.DialogResult = "Cancel"; $btnCancel.BackColor = $colorBtn; $btnCancel.ForeColor = $colorText; $btnCancel.FlatStyle = "Flat"
    $dlg.Controls.AddRange(@($lbl, $txt, $btnOk, $btnCancel)); $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel
    if ($dlg.ShowDialog() -eq "OK") { $global:customBridgeLine = $txt.Text.Trim(); return $true }
    $dlg.Dispose(); return $false
}

function Show-V2rayDialog {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = "V2Ray Outbound Chain Configuration"; $dlg.Size = New-Object Drawing.Size(520, 360); $dlg.StartPosition = "CenterParent"; $dlg.BackColor = $colorBg; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = "Paste the full v2rayN JSON or raw Xray Outbound below:"; $lbl.ForeColor = $colorText; $lbl.Location = "15,15"; $lbl.AutoSize = $true
    $txt = New-Object Windows.Forms.TextBox; $txt.Location = "15,40"; $txt.Size = "475, 210"; $txt.Multiline = $true; $txt.ScrollBars = "Vertical"; $txt.BackColor = "#2D3748"; $txt.ForeColor = "White"; $txt.Text = $global:v2rayChainJson; $txt.BorderStyle = "FixedSingle"
    
    $btnImport = New-Object Windows.Forms.Button; $btnImport.Text = "Import .json File"; $btnImport.Location = "15, 265"; $btnImport.Size="120, 30"; $btnImport.BackColor = $colorBtn; $btnImport.ForeColor = $colorText; $btnImport.FlatStyle = "Flat"
    $btnImport.Add_Click({
        $fd = New-Object System.Windows.Forms.OpenFileDialog; $fd.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
        if ($fd.ShowDialog() -eq "OK") { $txt.Text = Get-Content $fd.FileName -Raw }
    })
    
    $btnOk = New-Object Windows.Forms.Button; $btnOk.Text = "Validate & Save"; $btnOk.Location = "270, 265"; $btnOk.Size="110, 30"; $btnOk.DialogResult = "OK"; $btnOk.BackColor = "#4F7C9B"; $btnOk.ForeColor = "White"; $btnOk.FlatStyle = "Flat"
    $btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = "390, 265"; $btnCancel.Size="100, 30"; $btnCancel.DialogResult = "Cancel"; $btnCancel.BackColor = $colorBtn; $btnCancel.ForeColor = $colorText; $btnCancel.FlatStyle = "Flat"
    
    $dlg.Controls.AddRange(@($lbl, $txt, $btnImport, $btnOk, $btnCancel)); $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel
    if ($dlg.ShowDialog() -eq "OK") {
        if ([string]::IsNullOrWhiteSpace($txt.Text)) { $global:v2rayChainJson = ""; return $true }
        try { 
            $parsed = $txt.Text | ConvertFrom-Json 
            $testNode = if ($null -ne $parsed.outbounds) { $parsed.outbounds[0] } else { $parsed }
            if (-not $testNode.protocol) { throw "Missing Protocol" }
            $global:v2rayChainJson = $txt.Text.Trim(); return $true 
        } 
        catch { [System.Windows.Forms.MessageBox]::Show("Invalid Xray JSON! Please check your copied config.", "Error", 0, 16); return $false }
    }
    $dlg.Dispose(); return $false
}

# --- UI LAYOUT: TOP DROPDOWN BLOCKS ---
$lblBridge = New-Object Windows.Forms.Label; $lblBridge.Location = "20, 25"; $lblBridge.Size = "75, 26"; $lblBridge.Text = "Bridge Type"; $lblBridge.BackColor = $colorTogLbl; $lblBridge.ForeColor = $colorText; $lblBridge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter; $lblBridge.Font = $microFont
$comboBridge = New-Object Windows.Forms.ComboBox; $comboBridge.Location = "95, 25"; $comboBridge.Size = "95, 26"; $comboBridge.DropDownStyle = "DropDownList"; $comboBridge.FlatStyle = "Flat"; $comboBridge.BackColor = "#1A202C"; $comboBridge.ForeColor = "#E2E8F0"; $comboBridge.Font = $microFont; $comboBridge.DrawMode = "OwnerDrawFixed"; $comboBridge.ItemHeight = 20
$null = $comboBridge.Items.AddRange(@("Direct (None)", "meek_lite", "obfs4", "snowflake", "Custom")); $comboBridge.SelectedItem = $lastBridge

$global:previousBridge = $comboBridge.SelectedItem
$comboBridge.Add_SelectedIndexChanged({
    if ($comboBridge.SelectedItem -eq "Custom") {
        if (-not (Show-CustomBridgeDialog)) { $comboBridge.SelectedItem = $global:previousBridge } else { $global:previousBridge = "Custom" }
    } else { $global:previousBridge = $comboBridge.SelectedItem }
    Save-Config
})

$lblConfig = New-Object Windows.Forms.Label; $lblConfig.Location = "205, 25"; $lblConfig.Size = "75, 26"; $lblConfig.Text = "Routing"; $lblConfig.BackColor = $colorTogLbl; $lblConfig.ForeColor = $colorText; $lblConfig.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter; $lblConfig.Font = $microFont
$comboConfig = New-Object Windows.Forms.ComboBox; $comboConfig.Location = "280, 25"; $comboConfig.Size = "95, 26"; $comboConfig.DropDownStyle = "DropDownList"; $comboConfig.FlatStyle = "Flat"; $comboConfig.BackColor = "#1A202C"; $comboConfig.ForeColor = "#E2E8F0"; $comboConfig.Font = $microFont; $comboConfig.DrawMode = "OwnerDrawFixed"; $comboConfig.ItemHeight = 20
$null = $comboConfig.Items.AddRange(@("Stable (default)", "Fast")); $comboConfig.SelectedItem = $lastConfig
$comboConfig.Add_SelectedIndexChanged({ Save-Config })

$lblCount = New-Object Windows.Forms.Label; $lblCount.Location = "390, 25"; $lblCount.Size = "85, 26"; $lblCount.Text = "Tor Engines"; $lblCount.BackColor = $colorTogLbl; $lblCount.ForeColor = $colorText; $lblCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter; $lblCount.Font = $microFont
$comboCount = New-Object Windows.Forms.ComboBox; $comboCount.Location = "475, 25"; $comboCount.Size = "95, 26"; $comboCount.DropDownStyle = "DropDownList"; $comboCount.FlatStyle = "Flat"; $comboCount.BackColor = "#1A202C"; $comboCount.ForeColor = "#E2E8F0"; $comboCount.Font = $microFont; $comboCount.DrawMode = "OwnerDrawFixed"; $comboCount.ItemHeight = 20
$null = $comboCount.Items.AddRange(@("1","2","3","4","5","6 (default)","7","8")); $comboCount.SelectedItem = $lastCount
$comboCount.Add_SelectedIndexChanged({ Save-Config })

# --- UI LAYOUT: LEFT SIDE VERTICAL CONTROLS ---
$btnUpdate = New-Object Windows.Forms.Button; $btnUpdate.Location = "20, 80"; $btnUpdate.Size = "205, 25"; $btnUpdate.Text = "Check for Updates"; $btnUpdate.BackColor = $colorBtn; $btnUpdate.ForeColor = $colorText; $btnUpdate.FlatStyle = "Flat"; $btnUpdate.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnUpdate 4; $btnUpdate.Font = $smallFont; $btnUpdate.Cursor = [System.Windows.Forms.Cursors]::Hand

$btnAutoStartLbl = New-Object Windows.Forms.Button; $btnAutoStartLbl.Location = "20, 110"; $btnAutoStartLbl.Size = "130, 25"; $btnAutoStartLbl.Text = "Auto-connect"; $btnAutoStartLbl.BackColor = $colorTogLbl; $btnAutoStartLbl.ForeColor = $colorText; $btnAutoStartLbl.FlatStyle = "Flat"; $btnAutoStartLbl.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAutoStartLbl 4; $btnAutoStartLbl.Font = $smallFont
$btnAutoStartTog = New-Object Windows.Forms.Button; $btnAutoStartTog.Location = "155, 110"; $btnAutoStartTog.Size = "70, 25"; $btnAutoStartTog.FlatStyle = "Flat"; $btnAutoStartTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAutoStartTog 4; $btnAutoStartTog.Font = $smallFont; $btnAutoStartTog.ForeColor = $colorText; $btnAutoStartTog.Cursor = "Hand"
Set-ToggleState $btnAutoStartTog $autoStart


$btnAdvLbl = New-Object Windows.Forms.Button; $btnAdvLbl.Location = "20, 140"; $btnAdvLbl.Size = "130, 25"; $btnAdvLbl.Text = "Advanced Settings"; $btnAdvLbl.BackColor = $colorTogLbl; $btnAdvLbl.ForeColor = $colorText; $btnAdvLbl.FlatStyle = "Flat"; $btnAdvLbl.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAdvLbl 4; $btnAdvLbl.Font = $smallFont
$btnAdvTog = New-Object Windows.Forms.Button; $btnAdvTog.Location = "155, 140"; $btnAdvTog.Size = "70, 25"; $btnAdvTog.FlatStyle = "Flat"; $btnAdvTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAdvTog 4; $btnAdvTog.Font = $smallFont; $btnAdvTog.ForeColor = $colorText; $btnAdvTog.Cursor = "Hand"
$showAdvanced = $false
Set-ToggleState $btnAdvTog $showAdvanced "Show" "Hide"


# --- UI LAYOUT: RIGHT-SIDE ACTIONS ---
$btnProxyMode = New-Object Windows.Forms.Button; $btnProxyMode.Location = "270, 75"; $btnProxyMode.Size = "98, 30"; $btnProxyMode.FlatStyle = "Flat"; $btnProxyMode.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnProxyMode 4; $btnProxyMode.Text = "Proxy Mode"; $btnProxyMode.Font = $smallFont; $btnProxyMode.Cursor = "Hand"

$btnVpnMode = New-Object Windows.Forms.Button; $btnVpnMode.Location = "371, 75"; $btnVpnMode.Size = "98, 30"; $btnVpnMode.FlatStyle = "Flat"; $btnVpnMode.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnVpnMode 4; $btnVpnMode.Text = "VPN Mode"; $btnVpnMode.Font = $smallFont; 
if (-not $global:hasVpnComponents) {
    $btnVpnMode.Cursor = "No"
    $vpnToolTip = New-Object System.Windows.Forms.ToolTip
    $vpnToolTip.AutoPopDelay = 5000; $vpnToolTip.InitialDelay = 100; $vpnToolTip.ReshowDelay = 500; $vpnToolTip.ShowAlways = $true
    $vpnToolTip.SetToolTip($btnVpnMode, "You need to download the full version from GitHub to use VPN Mode.")
} else {
    $btnVpnMode.Cursor = "Hand"
}

$btnClearProxy = New-Object Windows.Forms.Button; $btnClearProxy.Location = "472, 75"; $btnClearProxy.Size = "98, 30"; $btnClearProxy.FlatStyle = "Flat"; $btnClearProxy.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnClearProxy 4; $btnClearProxy.Text = "Clear Proxy"; $btnClearProxy.Font = $smallFont; $btnClearProxy.Cursor = "Hand"

function Update-RoutingToggle {
    $btnProxyMode.BackColor = "#2D3748"; $btnProxyMode.ForeColor = "#A0AEC0"
    $btnClearProxy.BackColor = "#2D3748"; $btnClearProxy.ForeColor = "#A0AEC0"
    
    if (-not $global:hasVpnComponents) { $btnVpnMode.BackColor = "#1A202C"; $btnVpnMode.ForeColor = "#4A5568" } 
    else { $btnVpnMode.BackColor = "#2D3748"; $btnVpnMode.ForeColor = "#A0AEC0" }
    
    if ($global:lastXrayMode -eq "Proxy Mode") { $btnProxyMode.BackColor = "#4F7C9B"; $btnProxyMode.ForeColor = "#FFFFFF" } 
    elseif ($global:lastXrayMode -eq "VPN Mode" -and $global:hasVpnComponents) { $btnVpnMode.BackColor = "#4F7C9B"; $btnVpnMode.ForeColor = "#FFFFFF" }
    elseif ($global:lastXrayMode -eq "Clear Proxy") { $btnClearProxy.BackColor = "#4A5568"; $btnClearProxy.ForeColor = "#FFFFFF" }
}
Update-RoutingToggle 

$btnAction = New-Object Windows.Forms.Button; $btnAction.Location = "270, 109"; $btnAction.Size = "300, 60"; $btnAction.BackColor = $colorBtn; $btnAction.ForeColor = $colorText; $btnAction.FlatStyle = "Flat"; $btnAction.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAction 8; $btnAction.Text = ""; $btnAction.Cursor = [System.Windows.Forms.Cursors]::Hand

$btnAction.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics; $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold); $fontSub = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
    if ($global:isConnected) { $tColor = [System.Drawing.ColorTranslator]::FromHtml("#68D391") } elseif ($global:btnMainText -eq "CONNECTING...") { $tColor = [System.Drawing.ColorTranslator]::FromHtml("#F6AD55") } else { $tColor = $sender.ForeColor }
    $brush = New-Object System.Drawing.SolidBrush($tColor)
    $szMain = $g.MeasureString($global:btnMainText, $fontMain); $szSub = $g.MeasureString($global:btnSubText, $fontSub)
    $startY = ($sender.Height - ($szMain.Height + $szSub.Height + 2)) / 2
    $g.DrawString($global:btnMainText, $fontMain, $brush, ($sender.Width - $szMain.Width) / 2, $startY)
    $g.DrawString($global:btnSubText, $fontSub, $brush, ($sender.Width - $szSub.Width) / 2, $startY + $szMain.Height + 2)
    $fontMain.Dispose(); $fontSub.Dispose(); $brush.Dispose()
})

$btnAction.Add_Click({ if ($global:isConnected -or $global:btnMainText -eq "CONNECTING...") { Stop-AllEngines } else { Start-Engines } })


# --- UI LAYOUT: ADVANCED OPTIONS (CLEAN 2-COLUMN GRID) ---
$lblAdvSepTitle = New-Object Windows.Forms.Label; $lblAdvSepTitle.Text = "Advanced Options"; $lblAdvSepTitle.ForeColor = "#A0AEC0"; $lblAdvSepTitle.Font = $smallFont; $lblAdvSepTitle.Location = "20, 185"; $lblAdvSepTitle.AutoSize = $true; $lblAdvSepTitle.Visible = $false
$lblAdvSepLine = New-Object Windows.Forms.Label; $lblAdvSepLine.BackColor = "#3A3F44"; $lblAdvSepLine.Size = "420, 1"; $lblAdvSepLine.Location = "150, 194"; $lblAdvSepLine.Visible = $false

# ROW 1 (Y=215)
$btnDirectConfig = New-Object Windows.Forms.Button; $btnDirectConfig.Text = "Split Tunneling"; $btnDirectConfig.Location = "20, 215"; $btnDirectConfig.Size="170, 25"; $btnDirectConfig.BackColor = $colorTogLbl; $btnDirectConfig.ForeColor = $colorText; $btnDirectConfig.FlatStyle = "Flat"; $btnDirectConfig.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnDirectConfig 4; $btnDirectConfig.Visible = $false; $btnDirectConfig.Font = $smallFont; $btnDirectConfig.Cursor = "Hand"
$btnDirectTog = New-Object Windows.Forms.Button; $btnDirectTog.Location = "195, 215"; $btnDirectTog.Size="85, 25"; $btnDirectTog.FlatStyle = "Flat"; $btnDirectTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnDirectTog 4; $btnDirectTog.Visible = $false; $btnDirectTog.Font = $smallFont; $btnDirectTog.ForeColor = $colorText; $btnDirectTog.Cursor = "Hand"
Set-ToggleState $btnDirectTog $global:enableDirect

$btnV2rayConfig = New-Object Windows.Forms.Button; $btnV2rayConfig.Text = "Custom v2ray Exit-Node"; $btnV2rayConfig.Location = "300, 215"; $btnV2rayConfig.Size="180, 25"; $btnV2rayConfig.BackColor = $colorTogLbl; $btnV2rayConfig.ForeColor = $colorText; $btnV2rayConfig.FlatStyle = "Flat"; $btnV2rayConfig.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnV2rayConfig 4; $btnV2rayConfig.Visible = $false; $btnV2rayConfig.Font = $smallFont; $btnV2rayConfig.Cursor = "Hand"
$btnV2rayTog = New-Object Windows.Forms.Button; $btnV2rayTog.Location = "485, 215"; $btnV2rayTog.Size="85, 25"; $btnV2rayTog.FlatStyle = "Flat"; $btnV2rayTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnV2rayTog 4; $btnV2rayTog.Visible = $false; $btnV2rayTog.Font = $smallFont; $btnV2rayTog.ForeColor = $colorText; $btnV2rayTog.Cursor = "Hand"
Set-ToggleState $btnV2rayTog $global:enableV2rayChain

# ROW 2 (Y=250)
$btnOutboundConfig = New-Object Windows.Forms.Button; $btnOutboundConfig.Text = "Outbound Proxy"; $btnOutboundConfig.Location = "20, 250"; $btnOutboundConfig.Size="170, 25"; $btnOutboundConfig.BackColor = $colorTogLbl; $btnOutboundConfig.ForeColor = $colorText; $btnOutboundConfig.FlatStyle = "Flat"; $btnOutboundConfig.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnOutboundConfig 4; $btnOutboundConfig.Visible = $false; $btnOutboundConfig.Font = $smallFont; $btnOutboundConfig.Cursor = "Hand"
$btnOutboundTog = New-Object Windows.Forms.Button; $btnOutboundTog.Location = "195, 250"; $btnOutboundTog.Size="85, 25"; $btnOutboundTog.FlatStyle = "Flat"; $btnOutboundTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnOutboundTog 4; $btnOutboundTog.Visible = $false; $btnOutboundTog.Font = $smallFont; $btnOutboundTog.ForeColor = $colorText; $btnOutboundTog.Cursor = "Hand"
Set-ToggleState $btnOutboundTog $global:enableOutboundProxy

$btnBootLbl = New-Object Windows.Forms.Button; $btnBootLbl.Location = "300, 250"; $btnBootLbl.Size = "180, 25"; $btnBootLbl.Text = "Launch on Start-up"; $btnBootLbl.BackColor = $colorTogLbl; $btnBootLbl.ForeColor = $colorText; $btnBootLbl.FlatStyle = "Flat"; $btnBootLbl.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnBootLbl 4; $btnBootLbl.Font = $smallFont; $btnBootLbl.Visible = $false
$btnBootTog = New-Object Windows.Forms.Button; $btnBootTog.Location = "485, 250"; $btnBootTog.Size = "85, 25"; $btnBootTog.FlatStyle = "Flat"; $btnBootTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnBootTog 4; $btnBootTog.Font = $smallFont; $btnBootTog.ForeColor = $colorText; $btnBootTog.Cursor = "Hand"; $btnBootTog.Visible = $false
Set-ToggleState $btnBootTog $launchOnBoot

# ROW 3 (Y=285)
$btnDebugLbl = New-Object Windows.Forms.Button; $btnDebugLbl.Location = "20, 285"; $btnDebugLbl.Size = "170, 25"; $btnDebugLbl.Text = "Debug Mode"; $btnDebugLbl.BackColor = $colorTogLbl; $btnDebugLbl.ForeColor = $colorText; $btnDebugLbl.FlatStyle = "Flat"; $btnDebugLbl.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnDebugLbl 4; $btnDebugLbl.Font = $smallFont; $btnDebugLbl.Visible = $false
$btnDebugTog = New-Object Windows.Forms.Button; $btnDebugTog.Location = "195, 285"; $btnDebugTog.Size = "85, 25"; $btnDebugTog.FlatStyle = "Flat"; $btnDebugTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnDebugTog 4; $btnDebugTog.Font = $smallFont; $btnDebugTog.ForeColor = $colorText; $btnDebugTog.Cursor = "Hand"; $btnDebugTog.Visible = $false
$debugMode = $false
Set-ToggleState $btnDebugTog $debugMode

$btnDesktop = New-Object Windows.Forms.Button; $btnDesktop.Location = "300, 285"; $btnDesktop.Size = "270, 25"; $btnDesktop.Text = "Create Desktop Shortcut"; $btnDesktop.BackColor = $colorBtn; $btnDesktop.ForeColor = $colorText; $btnDesktop.FlatStyle = "Flat"; $btnDesktop.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnDesktop 4; $btnDesktop.Font = $smallFont; $btnDesktop.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnDesktop.Visible = $false


# --- SOCKS & STATS PANELS ---
$pnlSocks = New-Object Windows.Forms.Panel; $pnlSocks.Size = "260, 65"; $pnlSocks.BackColor = "#2D3748"; $pnlSocks.Location = "20, 185"
Set-RoundedCorners $pnlSocks 4
$lblSocksTitle = New-Object Windows.Forms.Label; $lblSocksTitle.Location = "10, 8"; $lblSocksTitle.Size = "240, 15"; $lblSocksTitle.ForeColor = "#A0AEC0"; $lblSocksTitle.Font = $smallFont; $lblSocksTitle.Text = "Mixed Port:"
$lblSocksDataIPs = New-Object Windows.Forms.Label; $lblSocksDataIPs.Location = "10, 26"; $lblSocksDataIPs.Size = "180, 35"; $lblSocksDataIPs.ForeColor = "#E2E8F0"; $lblSocksDataIPs.Font = $smallFont; $lblSocksDataIPs.Text = "Waiting for connection..."
$lblSocksDataTags = New-Object Windows.Forms.Label; $lblSocksDataTags.Location = "190, 26"; $lblSocksDataTags.Size = "60, 35"; $lblSocksDataTags.ForeColor = "#A0AEC0"; $lblSocksDataTags.Font = $smallFont; $lblSocksDataTags.Text = ""; $lblSocksDataTags.TextAlign = "TopRight"
$pnlSocks.Controls.AddRange(@($lblSocksTitle, $lblSocksDataIPs, $lblSocksDataTags))

$pnlStats = New-Object Windows.Forms.Panel; $pnlStats.Size = "270, 65"; $pnlStats.BackColor = "#2D3748"; $pnlStats.Location = "300, 185"
Set-RoundedCorners $pnlStats 4
$lblStatsTitle = New-Object Windows.Forms.Label; $lblStatsTitle.Location = "10, 8"; $lblStatsTitle.Size = "250, 15"; $lblStatsTitle.ForeColor = "#A0AEC0"; $lblStatsTitle.Font = $smallFont; $lblStatsTitle.Text = "Stats:"
$lblStatsData = New-Object Windows.Forms.Label; $lblStatsData.Location = "10, 26"; $lblStatsData.Size = "250, 35"; $lblStatsData.ForeColor = "#68D391"; $lblStatsData.Font = $statsFont; $lblStatsData.Text = "Speed: 0 KB/s`nTotal: 0 MB"
$pnlStats.Controls.AddRange(@($lblStatsTitle, $lblStatsData))


# --- DYNAMIC RESIZING EVENT ---
function Toggle-AdvancedView {
    $show = $script:showAdvanced
    $lblAdvSepTitle.Visible = $show; $lblAdvSepLine.Visible = $show
    $btnDirectConfig.Visible = $show; $btnDirectTog.Visible = $show
    $btnV2rayConfig.Visible = $show; $btnV2rayTog.Visible = $show
    $btnOutboundConfig.Visible = $show; $btnOutboundTog.Visible = $show
    $btnDesktop.Visible = $show; 
    $btnBootLbl.Visible = $show; $btnBootTog.Visible = $show
    $btnDebugLbl.Visible = $show; $btnDebugTog.Visible = $show

    if ($show) { 
        $form.ClientSize = New-Object Drawing.Size(600, 420)
        $pnlSocks.Location = "20, 335"; $pnlStats.Location = "300, 335" 
    } else { 
        $form.ClientSize = New-Object Drawing.Size(600, 265)
        $pnlSocks.Location = "20, 185"; $pnlStats.Location = "300, 185"
    }
}


# --- ASYNC NON-BLOCKING STATS ENGINE ---
$global:webClient = New-Object System.Net.WebClient
$global:isFetchingStats = $false

$global:webClient.Add_DownloadStringCompleted({
    param($sender, $e)
    if (-not $e.Cancelled -and $e.Error -eq $null) {
        $rows = $e.Result -split "`n"
        
        $torServers = $rows | Where-Object { $_ -match ",tor\d+," }
        $currentBytes = 0
        
        foreach ($server in $torServers) {
            $cols = $server -split ","
            if ($cols.Count -ge 10) { 
                $currentBytes += [long]$cols[8] + [long]$cols[9] 
            }
        }
        
        if ($global:lastTotalBytes -gt 0) {
            $diff = $currentBytes - $global:lastTotalBytes
            if ($diff -lt 0) { $diff = 0 } 
            
            $global:sessionDataBytes += $diff
            
            $speedStr = if ($diff -ge 1048576) { "$([Math]::Round($diff/1048576, 2)) MB/s" } elseif ($diff -ge 1024) { "$([Math]::Round($diff/1024, 1)) KB/s" } else { "$diff B/s" }
            $totStr = if ($global:sessionDataBytes -ge 1073741824) { "$([Math]::Round($global:sessionDataBytes/1073741824, 2)) GB" } elseif ($global:sessionDataBytes -ge 1048576) { "$([Math]::Round($global:sessionDataBytes/1048576, 1)) MB" } else { "$([Math]::Round($global:sessionDataBytes/1024, 1)) KB" }
            
            $lblStatsData.Text = "Speed: $speedStr`nTotal: $totStr"
        }
        if ($currentBytes -gt 0) { $global:lastTotalBytes = $currentBytes }
    }
    $global:isFetchingStats = $false
})

$statsTimer = New-Object Windows.Forms.Timer; $statsTimer.Interval = 1000
$statsTimer.Add_Tick({
    if ($global:isConnected -and -not $global:isFetchingStats) {
        $global:isFetchingStats = $true
        try { $global:webClient.DownloadStringAsync([uri]"http://127.0.0.1:10888/stats;csv") } 
        catch { $global:isFetchingStats = $false }
    }
})


# --- EVENT BINDINGS (CUSTOM TOGGLES) ---

# Auto Connect
$btnAutoStartTog.Add_Click({
    $script:autoStart = -not $script:autoStart
    Set-ToggleState $btnAutoStartTog $script:autoStart
    Save-Config
})
$btnAutoStartLbl.Add_Click({ $btnAutoStartTog.PerformClick() })

# Advanced Options
$btnAdvTog.Add_Click({
    $script:showAdvanced = -not $script:showAdvanced
    Set-ToggleState $btnAdvTog $script:showAdvanced "Show" "Hide"
    Toggle-AdvancedView
})
$btnAdvLbl.Add_Click({ $btnAdvTog.PerformClick() })

# Direct Rules Toggles
$btnDirectTog.Add_Click({
    $global:enableDirect = -not $global:enableDirect
    Set-ToggleState $btnDirectTog $global:enableDirect
    Save-Config
    if ($global:isConnected) { Restart-Xray $global:lastXrayMode }
})
$btnDirectConfig.Add_Click({ Show-DirectRulesDialog })

# Outbound Proxy Toggles
$btnOutboundTog.Add_Click({
    if ($global:isConnected) {
        [System.Windows.Forms.MessageBox]::Show("You cannot enable or disable the Outbound Proxy while connected. Please disconnect first.", "Action Denied", 0, 48)
        return
    }
    $global:enableOutboundProxy = -not $global:enableOutboundProxy
    Set-ToggleState $btnOutboundTog $global:enableOutboundProxy
    Save-Config
})
$btnOutboundConfig.Add_Click({ Show-OutboundProxyDialog })

# Chain V2Ray Config
$btnV2rayTog.Add_Click({
    $newState = -not $global:enableV2rayChain
    if ($newState -and [string]::IsNullOrWhiteSpace($global:v2rayChainJson)) {
        if (-not (Show-V2rayDialog)) { $newState = $false }
    }
    $global:enableV2rayChain = $newState
    Set-ToggleState $btnV2rayTog $global:enableV2rayChain
    Save-Config
    if ($global:isConnected) { Restart-Xray $global:lastXrayMode }
})
$btnV2rayConfig.Add_Click({ Show-V2rayDialog })

# Launch on Boot
$btnBootTog.Add_Click({
    $script:launchOnBoot = -not $script:launchOnBoot
    Set-ToggleState $btnBootTog $script:launchOnBoot
    Update-BootShortcut
    Save-Config
})
$btnBootLbl.Add_Click({ $btnBootTog.PerformClick() })

# Debug Mode
$btnDebugTog.Add_Click({
    $script:debugMode = -not $script:debugMode
    Set-ToggleState $btnDebugTog $script:debugMode
})
$btnDebugLbl.Add_Click({ $btnDebugTog.PerformClick() })


# --- EVENT BINDINGS (BUTTONS & ACTIONS) ---
$btnDesktop.Add_Click({
    $deskFolder = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $deskFolder "TorMultiplexer.lnk"
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = Join-Path $global:baseDir "Launch Multiplexer.vbs"
        $Shortcut.WorkingDirectory = $global:baseDir
        $Shortcut.Save()
        [System.Windows.Forms.MessageBox]::Show("Desktop shortcut created successfully!", "Success", 0, 64)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to create Desktop shortcut.`n" + $_.Exception.Message, "Error", 0, 16)
    }
})

function Update-Application {
    $btnUpdate.Text = "Checking..."; $btnUpdate.Refresh()
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteCode = Invoke-RestMethod -Uri $repoRawUrl -UseBasicParsing
        
        if ($remoteCode -match '\$global:currentVersion\s*=\s*"([^"]+)"') {
            $remoteVer = $matches[1]
            if ([version]$remoteVer -gt [version]$global:currentVersion) {
                # MANUAL REDIRECT POPUP
                [System.Windows.Forms.MessageBox]::Show("Version $remoteVer is available!`n`nThis update contains critical new system components (Sing-box) and MUST be downloaded manually from GitHub to work correctly.`n`nClick OK to open the GitHub release page.", "Manual Update Required", 0, 64)
                Start-Process "https://github.com/RichTiTAN/Tor-Multiplexer"
            } else { [System.Windows.Forms.MessageBox]::Show("You are already on the latest version!`n(Local: $global:currentVersion, Remote: $remoteVer)", "Up to Date", 0, 64) }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Could not read the version number from GitHub.", "Update Error", 0, 16)
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Update check failed: $_", "Error", 0, 16)
    }
    $btnUpdate.Text = "Check for Updates"
}
$btnUpdate.Add_Click({ Update-Application })

$paintCombo = {
    param($sender, $e); if ($e.Index -lt 0) { return }; $g = $e.Graphics; $rect = $e.Bounds; $text = $sender.Items[$e.Index].ToString()
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#1A202C")); $hvrBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#4A5568")); $txtBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#E2E8F0"))
    if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected) { $g.FillRectangle($hvrBrush, $rect) } else { $g.FillRectangle($bgBrush, $rect) }
    $g.DrawString($text, $sender.Font, $txtBrush, $rect.X + 2, $rect.Y + 3); $bgBrush.Dispose(); $hvrBrush.Dispose(); $txtBrush.Dispose()
}
$comboBridge.Add_DrawItem($paintCombo); $comboConfig.Add_DrawItem($paintCombo); $comboCount.Add_DrawItem($paintCombo)

$toggleAction = {
    param($mode); if ($global:lastXrayMode -ne $mode) {
        $global:lastXrayMode = $mode; Update-RoutingToggle
        $selConfig = if ($comboConfig.SelectedItem.ToString() -match "Stable") { "Stable" } else { "Fast" }; $selCount = [int]($comboCount.SelectedItem.ToString().Replace(" (default)", ""))
        @{ AutoStart = [bool]$autoStart; LaunchOnBoot = [bool]$launchOnBoot; LastConfig = $selConfig; SelectedBridge = $comboBridge.SelectedItem; InstanceCount = $selCount; XrayMode = $mode; ManualSplit = $global:lastManualSplit; CustomBridgeLine = $global:customBridgeLine; EnableV2rayChain = $global:enableV2rayChain; V2rayChainJson = $global:v2rayChainJson; EnableOutboundProxy = $global:enableOutboundProxy; OutboundProxyAddress = $global:outboundProxyAddress; OutboundProxyPort = $global:outboundProxyPort; OutboundProxyType = $global:outboundProxyType; OutboundProxyUser = $global:outboundProxyUser; OutboundProxyPass = $global:outboundProxyPass; EnableOutboundAuth = $global:enableOutboundAuth } | ConvertTo-Json -Depth 10 | Set-Content $cfgFile
        if ($global:isConnected) { Restart-Xray $mode }
    }
}
$btnProxyMode.Add_Click({ &$toggleAction "Proxy Mode" }); $btnClearProxy.Add_Click({ &$toggleAction "Clear Proxy" })

$btnVpnMode.Add_Click({ 
    if (-not $global:hasVpnComponents) { return }
    &$toggleAction "VPN Mode" 
})

# --- CORE FUNCTIONS ---
function Write-XrayConfig {
    $rules = @( 
        @{ type="field"; ip=@("127.0.0.0/8", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"); outboundTag="direct" }
    )
    $domains = @(); $ips = @()
    if ($global:enableDirect -and $global:lastManualSplit -ne "") {
        $list = $global:lastManualSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($item in $list) { if ($item -match "[a-zA-Z]") { $domains += $item } else { $ips += $item } }
        if ($domains.Count -gt 0) { $rules += @{ type="field"; domain=$domains; outboundTag="direct" } }
        if ($ips.Count -gt 0) { $rules += @{ type="field"; ip=$ips; outboundTag="direct" } }
    }
    
    $rules += @{ type="field"; network="tcp,udp"; outboundTag="proxy" }
    
    $inboundArr = @( @{ listen="0.0.0.0"; port=10818; protocol="mixed"; settings=@{ udp=$true }; sniffing=@{ enabled=$true; destOverride=@("http","tls","quic","fakedns") } } )
    
    $outbounds = @()
    if ($global:enableV2rayChain -and -not [string]::IsNullOrWhiteSpace($global:v2rayChainJson)) {
        try {
            $v2rayParsed = $global:v2rayChainJson | ConvertFrom-Json
            $v2rayOutbound = $null
            
            if ($null -ne $v2rayParsed.outbounds) {
                $v2rayOutbound = $v2rayParsed.outbounds | Where-Object { $_.protocol -notin @("freedom", "blackhole") } | Select-Object -First 1
            } else { $v2rayOutbound = $v2rayParsed }

            if ($null -eq $v2rayOutbound -or $null -eq $v2rayOutbound.protocol) { throw "No valid protocol found" }

            $v2rayOutbound.tag = "proxy"
            
            if ($null -ne $v2rayOutbound.streamSettings -and $null -ne $v2rayOutbound.streamSettings.tlsSettings) {
                if (-not $v2rayOutbound.streamSettings.tlsSettings.psobject.properties.match('allowInsecure').Count) {
                    $v2rayOutbound.streamSettings.tlsSettings | Add-Member -MemberType NoteProperty -Name "allowInsecure" -Value $true
                } else { $v2rayOutbound.streamSettings.tlsSettings.allowInsecure = $true }
            }
            
            if (-not $v2rayOutbound.psobject.properties.match('proxySettings').Count) {
                $v2rayOutbound | Add-Member -MemberType NoteProperty -Name "proxySettings" -Value @{ tag="torProxy" }
            } else { $v2rayOutbound.proxySettings = @{ tag="torProxy" } }
            
            $outbounds += $v2rayOutbound
            $outbounds += @{ tag="torProxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } }
        } catch {
            $outbounds += @{ tag="proxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } }
        }
    } else {
        $outbounds += @{ tag="proxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } }
    }
    
    $outbounds += @{ tag="direct"; protocol="freedom"; settings=@{} }
    $config = @{ log = @{ logLevel="warning" }; inbounds = $inboundArr; outbounds = $outbounds; routing = @{ domainStrategy="AsIs"; rules=$rules } }
    $config | ConvertTo-Json -Depth 10 | Set-Content "$xrayDir\config.json"
}

function Write-SingboxConfig {
    $sbDir = "$global:baseDir\Data\sing_box"
    $sbConfig = @{
        log = @{ level = "warn" }
        dns = @{ servers = @( @{ tag = "dns_proxy"; server = "1.1.1.1"; type = "tcp"; detour = "proxy" } ); final = "dns_proxy" }
        inbounds = @( @{ type = "tun"; tag = "tun-in"; interface_name = "singbox_tun"; address = @("172.18.0.1/30", "fdfe:dcba:9876::1/126"); mtu = 9000; auto_route = $true; strict_route = $true; stack = "gvisor" } )
        outbounds = @( @{ type = "socks"; tag = "proxy"; server = "127.0.0.1"; server_port = 10818 }, @{ type = "direct"; tag = "direct" } )
        route = @{ default_domain_resolver = "dns_proxy"; auto_detect_interface = $true; rules = @( @{ action = "sniff" }, @{ port = @(53); action = "hijack-dns" }, @{ protocol = "dns"; action = "hijack-dns" }, @{ process_name = @("tor.exe", "haproxy.exe", "lyrebird.exe", "obfs4proxy.exe", "snowflake-client.exe", "xray.exe", "sing-box.exe"); outbound = "direct" }, @{ ip_is_private = $true; outbound = "direct" } ); final = "proxy" }
    }
    $sbConfig | ConvertTo-Json -Depth 10 | Set-Content "$sbDir\config.json"
}

function Set-SystemProxy($enable) {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($enable) { Set-ItemProperty $path -Name "ProxyEnable" -Value 1; Set-ItemProperty $path -Name "ProxyServer" -Value "127.0.0.1:10818" } 
    else { Set-ItemProperty $path -Name "ProxyEnable" -Value 0 }
    
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Restart-Xray($targetMode) {
    Get-Process sing-box, xray -ErrorAction SilentlyContinue | ForEach-Object { try { if ($null -ne $_.Path -and ($_.Path -eq "$xrayDir\xray.exe" -or $_.Path -eq "$global:baseDir\Data\sing_box\sing-box.exe")) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } } catch {} }
    if ($null -ne $global:cmdDebugPid) { Stop-Process -Id $global:cmdDebugPid -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid = $null }
    if ($null -ne $global:cmdDebugPid2) { Stop-Process -Id $global:cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid2 = $null }
    Start-Sleep -Milliseconds 500
    
    Write-XrayConfig
    if ($script:debugMode) { 
        $p = Start-Process "cmd.exe" -ArgumentList "/c `"title XrayDebug & .\xray.exe run -c config.json || pause`"" -WorkingDirectory $xrayDir -WindowStyle Normal -PassThru; $global:cmdDebugPid = $p.Id 
    } else { 
        Start-Process -FilePath "$xrayDir\xray.exe" -ArgumentList "run -c config.json" -WorkingDirectory $xrayDir -WindowStyle Hidden 
    }

    if ($targetMode -eq "VPN Mode") {
        Write-SingboxConfig
        $sbDir = "$global:baseDir\Data\sing_box"
        if ($script:debugMode) {
            $p2 = Start-Process "cmd.exe" -ArgumentList "/c `"title SingBoxDebug & .\sing-box.exe run -c config.json || pause`"" -WorkingDirectory $sbDir -WindowStyle Normal -PassThru; $global:cmdDebugPid2 = $p2.Id
        } else {
            Start-Process -FilePath "$sbDir\sing-box.exe" -ArgumentList "run -c config.json" -WorkingDirectory $sbDir -WindowStyle Hidden
        }
    } elseif ($targetMode -eq "Proxy Mode") { 
        Set-SystemProxy $true 
    }
    
    if ($targetMode -ne "Proxy Mode") { Set-SystemProxy $false }
}

function Reset-ButtonText { 
    $global:btnMainText = "CONNECT"
    $global:btnSubText = "(click to start)"
    $btnAction.Refresh() 
}

function Stop-AllEngines($isClosing = $false) {
    $global:abortBoot = $true; Set-SystemProxy $false; $statsTimer.Stop()
    Get-Process tor, haproxy, xray, sing-box -ErrorAction SilentlyContinue | ForEach-Object { try { $p = $_.Path; if ($null -ne $p -and ($p -eq "$xrayDir\xray.exe" -or $p -eq "$haPath\haproxy.exe" -or $p -eq "$global:baseDir\Data\sing_box\sing-box.exe" -or $p -match "Data\\Tors\\Tor")) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } } catch {} }
    if ($null -ne $global:cmdDebugPid) { Stop-Process -Id $global:cmdDebugPid -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid = $null }
    if ($null -ne $global:cmdDebugPid2) { Stop-Process -Id $global:cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid2 = $null }
    $global:isConnected = $false; $global:lastTotalBytes = 0; $global:sessionDataBytes = 0
    
    if (-not $isClosing) {
        Reset-ButtonText
        $btnAction.Enabled = $true
        $lblSocksTitle.Text = "Mixed Port:"
        $lblSocksDataIPs.Text = "Waiting for connection..."
        $lblSocksDataTags.Text = ""
        $lblStatsData.Text = "Speed: 0 KB/s`nTotal: 0 MB"
    }
}

function Wait-NonBlocking($s) { $end = (Get-Date).AddSeconds($s); while((Get-Date) -lt $end) { if($global:abortBoot){return}; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -ms 100 } }

function Format-HAProxyConfig($activeCount) {
    $haPathCfg = "$haPath\haproxy.cfg"
    if (Test-Path $haPathCfg) {
        $haData = Get-Content $haPathCfg; $newHaData = @(); $hasStats = $false
        foreach ($line in $haData) {
            if ($line -match "^listen stats") { $hasStats = $true }
            if ($line -match "^\s*#?\s*server\s+tor(\d+)") {
                if ([int]$matches[1] -le $activeCount) { $newHaData += ($line -replace "^\s*#+\s*", "    ") } else { if ($line -notmatch "^\s*#") { $newHaData += "    # $line" } else { $newHaData += $line } }
            } else { $newHaData += $line }
        }
        if (-not $hasStats) {
            $newHaData += ""
            $newHaData += "listen stats"
            $newHaData += "    bind 127.0.0.1:10888"
            $newHaData += "    mode http"
            $newHaData += "    stats enable"
            $newHaData += "    stats uri /stats"
        }
        $newHaData | Set-Content $haPathCfg
    }
}

function Start-Engines {
    if (Get-Process tor -ErrorAction SilentlyContinue) { $global:btnSubText = "Clearing old engines..."; $btnAction.Refresh(); [System.Windows.Forms.Application]::DoEvents(); Stop-AllEngines; Start-Sleep -Seconds 1 }
    $global:abortBoot = $false; $selBridge = $comboBridge.SelectedItem
    $selConfig = if ($comboConfig.SelectedItem.ToString() -match "Stable") { "Stable" } else { "Fast" }; $selCount = [int]($comboCount.SelectedItem.ToString().Replace(" (default)", ""))
    $mode = $global:lastXrayMode; $cfgFileTarget = if ($selConfig -eq "Stable") { "torrc" } else { "torrc2" }

    Save-Config
    $winStyle = if ($script:debugMode) { "Normal" } else { "Hidden" }; $global:btnMainText = "CONNECTING..."; Format-HAProxyConfig $selCount; $dynamicWait = 16 - $selCount
    
    for ($i=1; $i -le $selCount; $i++) {
        if ($global:abortBoot) { break } 
        $global:btnSubText = "Booting Tor $i of $selCount... (click to abort)"; $btnAction.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        $path = "$global:baseDir\Data\Tors\Tor$i"
        if (Test-Path "$path\$cfgFileTarget") {
            
            $c = @(Get-Content "$path\$cfgFileTarget")
            $cleanConfig = @()
            foreach ($line in $c) {
                if ($line -match "^# --- MANAGED BRIDGES ---") { break }
                if ($line -notmatch "^UseBridges" -and $line -notmatch "^ClientTransportPlugin" -and $line -notmatch "^Bridge" -and $line -notmatch "^HTTPSProxy" -and $line -notmatch "^Socks5Proxy" -and $line -notmatch "^Socks5ProxyUsername" -and $line -notmatch "^Socks5ProxyPassword" -and $line -notmatch "^HTTPSProxyAuthenticator") {
                    if ($line.Trim() -ne "") { $cleanConfig += $line.Trim() }
                }
            }
            
            $cleanConfig += "" 
            $cleanConfig += "# --- MANAGED BRIDGES ---"
            
            if ($global:enableOutboundProxy -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyAddress) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPort)) {
                if ($global:outboundProxyType -eq "SOCKS5") {
                    $cleanConfig += "Socks5Proxy $($global:outboundProxyAddress):$($global:outboundProxyPort)"
                    if ($global:enableOutboundAuth -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyUser) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPass)) {
                        $cleanConfig += "Socks5ProxyUsername $($global:outboundProxyUser)"
                        $cleanConfig += "Socks5ProxyPassword $($global:outboundProxyPass)"
                    }
                } elseif ($global:outboundProxyType -eq "HTTPS") {
                    $cleanConfig += "HTTPSProxy $($global:outboundProxyAddress):$($global:outboundProxyPort)"
                    if ($global:enableOutboundAuth -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyUser) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPass)) {
                        $cleanConfig += "HTTPSProxyAuthenticator $($global:outboundProxyUser):$($global:outboundProxyPass)"
                    }
                }
            }

            if ($selBridge -eq "Custom" -and $global:customBridgeLine -ne "") { 
                $cleanConfig += "UseBridges 1"
                $cleanConfig += "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel,snowflake exec ..\..\PluggableTransports\lyrebird.exe"
                
                $customLines = $global:customBridgeLine.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch "^ClientTransportPlugin" }
                foreach ($cl in $customLines) {
                    if ($cl -notmatch "^Bridge\s") { $cleanConfig += "Bridge $cl" } 
                    else { $cleanConfig += $cl }
                }
            } 
            elseif ($selBridge -ne "Direct (None)") { 
                $b = $bridgeData[$selBridge]
                $cleanConfig += "UseBridges 1"
                $cleanConfig += $b.plugin
                foreach ($line in $b.lines) { $cleanConfig += $line }
            } else { 
                $cleanConfig += "UseBridges 0" 
            }
            
            $cleanConfig | Set-Content "$path\$cfgFileTarget"
            
            Start-Process -FilePath "$path\tor.exe" -ArgumentList "-f $cfgFileTarget" -WorkingDirectory $path -WindowStyle $winStyle
            Wait-NonBlocking $dynamicWait
        }
    }
    
    if (-not $global:abortBoot) {
        $global:btnSubText = "Booting Core Engines... (click to abort)"; $btnAction.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        if (Test-Path "$haPath\haproxy.exe") { Start-Process -FilePath "$haPath\haproxy.exe" -ArgumentList "-f haproxy.cfg" -WorkingDirectory $haPath -WindowStyle $winStyle }
        Restart-Xray $mode
        
        $lblSocksTitle.Text = "Mixed Port:"
        $lblSocksDataIPs.Text = "127.0.0.1:10818`n$lanIp`:10818"
        $lblSocksDataTags.Text = "(Local)`n(LAN)"

        $global:isConnected = $true; $global:btnMainText = "CONNECTED"; $global:btnSubText = "(click to disconnect)"; $btnAction.Enabled = $true
        $lblStatsData.Text = "Speed: 0 KB/s`nTotal: 0 KB"
        $statsTimer.Start()
    } else { Reset-ButtonText; $btnAction.Enabled = $true }
    $btnAction.Refresh()
}

$form.Add_Shown({ 
    if (-not $global:hasVpnComponents) {
        $dlg = New-Object Windows.Forms.Form
        $dlg.Text = "Missing Components"
        $dlg.Size = New-Object Drawing.Size(420, 210)
        $dlg.StartPosition = "CenterParent"
        $dlg.BackColor = $colorBg
        $dlg.FormBorderStyle = "FixedDialog"
        $dlg.MaximizeBox = $false

        $lbl = New-Object Windows.Forms.Label
        $lbl.Text = "You have successfully updated to v4.6!`n`nHowever, your installation is missing a newly added core component (Sing-box). Because of this major upgrade, you must download the full package from GitHub to use VPN Mode."
        $lbl.ForeColor = $colorText
        $lbl.Location = "15,15"
        $lbl.Size = "375, 80"
        $lbl.Font = $smallFont
        
        $btnGit = New-Object Windows.Forms.Button
        $btnGit.Text = "Open GitHub"
        $btnGit.Location = "15, 115"
        $btnGit.Size = "130, 30"
        $btnGit.BackColor = $colorBtn
        $btnGit.ForeColor = $colorText
        $btnGit.FlatStyle = "Flat"
        Set-RoundedCorners $btnGit 4
        $btnGit.Add_Click({ Start-Process "https://github.com/RichTiTAN/Tor-Multiplexer"; $dlg.Close() })

        $btnClose = New-Object Windows.Forms.Button
        $btnClose.Text = "Continue without VPN"
        $btnClose.Location = "220, 115"
        $btnClose.Size = "170, 30"
        $btnClose.BackColor = $colorBtn
        $btnClose.ForeColor = $colorText
        $btnClose.FlatStyle = "Flat"
        Set-RoundedCorners $btnClose 4
        $btnClose.Add_Click({ $dlg.Close() })

        $dlg.Controls.AddRange(@($lbl, $btnGit, $btnClose))
        $dlg.ShowDialog() | Out-Null
        $dlg.Dispose()
    }

    Toggle-AdvancedView
    if ($autoStart -and -not $isFirstLaunch) { Wait-NonBlocking 1; if (-not $global:abortBoot) { Start-Engines } } else { Stop-AllEngines } 
})

$form.Controls.AddRange(@($lblBridge, $comboBridge, $lblConfig, $comboConfig, $lblCount, $comboCount, $btnProxyMode, $btnVpnMode, $btnClearProxy, $btnAction, $btnUpdate, $btnAutoStartLbl, $btnAutoStartTog, $btnAdvLbl, $btnAdvTog, $lblAdvSepTitle, $lblAdvSepLine, $btnDirectConfig, $btnDirectTog, $btnV2rayConfig, $btnV2rayTog, $btnOutboundConfig, $btnOutboundTog, $btnBootLbl, $btnBootTog, $btnDebugLbl, $btnDebugTog, $btnDesktop, $pnlSocks, $pnlStats))
$form.ShowDialog()