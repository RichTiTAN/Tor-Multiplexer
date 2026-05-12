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
$global:currentVersion = "4.1.2" 
$repoRawUrl = "https://raw.githubusercontent.com/RichTiTAN/Tor-Multiplexer/main/multiplexer.ps1"

# --- GLOBAL BOOT FLAG & STATE ---
$global:abortBoot = $false
$global:isConnected = $false
$global:cmdDebugPid = $null 

# --- DYNAMIC BUTTON TEXT STATES ---
$global:btnMainText = "CONNECT"
$global:btnSubText  = "(click to start)"

# --- CONFIGURATION & PATHS ---
$cfgFile = "$global:baseDir\multiplexer_settings.json"
$xrayDir = "$global:baseDir\Data\Xray"
$haPath  = "$global:baseDir\Data\HAproxy"

$autoStart = $true; $launchOnBoot = $false; $lastConfig = "Stable (default)"; $lastBridge = "meek_lite"; $lastCount = "6 (default)"; $global:lastXrayMode = "Proxy Mode"; $lastManualSplit = ""; $global:customBridgeLine = ""; $global:v2rayChainJson = ""; $global:enableV2rayChain = $false
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
        if ($null -ne $s.ManualSplit) { $lastManualSplit = [string]$s.ManualSplit }
        if ($null -ne $s.CustomBridgeLine) { $global:customBridgeLine = [string]$s.CustomBridgeLine }
        if ($null -ne $s.V2rayChainJson) { $global:v2rayChainJson = [string]$s.V2rayChainJson }
        if ($null -ne $s.EnableV2rayChain) { $global:enableV2rayChain = [bool]$s.EnableV2rayChain }
        if ($null -ne $s.XrayMode) { 
            if ($s.XrayMode -eq "Clear Proxy" -or $s.XrayMode -eq "None") { $global:lastXrayMode = "Clear Proxy" }
            else { $global:lastXrayMode = "Proxy Mode" }
        }
    } catch {}
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
$colorBg = [System.Drawing.ColorTranslator]::FromHtml("#1A1A1B"); $colorBtn = [System.Drawing.ColorTranslator]::FromHtml("#3A3F44"); $colorText = [System.Drawing.ColorTranslator]::FromHtml("#E2E8F0"); $colorIP = [System.Drawing.ColorTranslator]::FromHtml("#A0AEC0") 

# --- SAFE RELATIVE BRIDGE DATABASE ---
$bridgeData = @{
    "meek_lite" = @{ "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN") }
    "obfs4" = @{ "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0", "Bridge obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0", "Bridge obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0", "Bridge obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0", "Bridge obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=1", "Bridge obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1", "Bridge obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1") }
    "snowflake" = @{ "plugin" = "ClientTransportPlugin snowflake exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn", "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn") }
}

function Set-RoundedCorners($control, $radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $radius, $radius, 180, 90)
    $path.AddArc($control.Width - $radius, 0, $radius, $radius, 270, 90)
    $path.AddArc($control.Width - $radius, $control.Height - $radius, $radius, $radius, 0, 90)
    $path.AddArc(0, $control.Height - $radius, $radius, $radius, 90, 90)
    $path.CloseAllFigures()
    $control.Region = New-Object System.Drawing.Region($path)
}

# --- SETUP THE WINDOW ---
$form = New-Object Windows.Forms.Form
$form.Text = "Tor Multiplexer - v$global:currentVersion"
$form.ClientSize = New-Object Drawing.Size(600, 234)
$form.StartPosition = "CenterScreen"
$form.BackColor = $colorBg

# --- MODAL DIALOGS ---
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


# --- UI LAYOUT: BASE ELEMENTS ---
$lblBridge = New-Object Windows.Forms.Label; $lblBridge.Location = "20, 15"; $lblBridge.Size = "170, 20"; $lblBridge.Text = "Bridge Type:"; $lblBridge.ForeColor = "#A0AEC0"; $lblBridge.Font = $smallFont
$comboBridge = New-Object Windows.Forms.ComboBox; $comboBridge.Location = "20, 35"; $comboBridge.Size = "170, 25"; $comboBridge.DropDownStyle = "DropDownList"; $comboBridge.FlatStyle = "Flat"; $comboBridge.BackColor = "#2D3748"; $comboBridge.ForeColor = "#E2E8F0"; $comboBridge.Font = $smallFont; $comboBridge.DrawMode = "OwnerDrawFixed"; $comboBridge.ItemHeight = 20
$null = $comboBridge.Items.AddRange(@("Direct (None)", "meek_lite", "obfs4", "snowflake", "Custom")); $comboBridge.SelectedItem = $lastBridge

$global:previousBridge = $comboBridge.SelectedItem
$comboBridge.Add_SelectedIndexChanged({
    if ($comboBridge.SelectedItem -eq "Custom") {
        if (-not (Show-CustomBridgeDialog)) { $comboBridge.SelectedItem = $global:previousBridge } else { $global:previousBridge = "Custom" }
    } else { $global:previousBridge = $comboBridge.SelectedItem }
})

$lblConfig = New-Object Windows.Forms.Label; $lblConfig.Location = "210, 15"; $lblConfig.Size = "170, 20"; $lblConfig.Text = "Routing Config:"; $lblConfig.ForeColor = "#A0AEC0"; $lblConfig.Font = $smallFont
$comboConfig = New-Object Windows.Forms.ComboBox; $comboConfig.Location = "210, 35"; $comboConfig.Size = "170, 25"; $comboConfig.DropDownStyle = "DropDownList"; $comboConfig.FlatStyle = "Flat"; $comboConfig.BackColor = "#2D3748"; $comboConfig.ForeColor = "#E2E8F0"; $comboConfig.Font = $smallFont; $comboConfig.DrawMode = "OwnerDrawFixed"; $comboConfig.ItemHeight = 20
$null = $comboConfig.Items.AddRange(@("Stable (default)", "Fast")); $comboConfig.SelectedItem = $lastConfig

$lblCount = New-Object Windows.Forms.Label; $lblCount.Location = "400, 15"; $lblCount.Size = "170, 20"; $lblCount.Text = "Tor Engines (1-8):"; $lblCount.ForeColor = "#A0AEC0"; $lblCount.Font = $smallFont
$comboCount = New-Object Windows.Forms.ComboBox; $comboCount.Location = "400, 35"; $comboCount.Size = "170, 25"; $comboCount.DropDownStyle = "DropDownList"; $comboCount.FlatStyle = "Flat"; $comboCount.BackColor = "#2D3748"; $comboCount.ForeColor = "#E2E8F0"; $comboCount.Font = $smallFont; $comboCount.DrawMode = "OwnerDrawFixed"; $comboCount.ItemHeight = 20
$null = $comboCount.Items.AddRange(@("1","2","3","4","5","6 (default)","7","8")); $comboCount.SelectedItem = $lastCount

# Toggles positioned cleanly on the left
$chkAutoStart = New-Object Windows.Forms.CheckBox; $chkAutoStart.Location = "20, 80"; $chkAutoStart.Size = "250, 20"; $chkAutoStart.Text = "Auto-connect after launch"; $chkAutoStart.ForeColor = "#F6AD55"; $chkAutoStart.Font = $smallFont; $chkAutoStart.Checked = $autoStart; $chkAutoStart.FlatStyle = "Flat" 
$chkShowAdvanced = New-Object Windows.Forms.CheckBox; $chkShowAdvanced.Location = "20, 105"; $chkShowAdvanced.Size = "250, 20"; $chkShowAdvanced.Text = "Show Advanced Options"; $chkShowAdvanced.ForeColor = "#A0AEC0"; $chkShowAdvanced.Font = $smallFont; $chkShowAdvanced.FlatStyle = "Flat" 

# Right-side Action & Proxy Buttons
$btnProxyMode = New-Object Windows.Forms.Button; $btnProxyMode.Location = "270, 75"; $btnProxyMode.Size = "148, 30"; $btnProxyMode.FlatStyle = "Flat"; $btnProxyMode.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnProxyMode 8; $btnProxyMode.Text = "Proxy Mode"; $btnProxyMode.Font = $smallFont; $btnProxyMode.Cursor = "Hand"
$btnClearProxy = New-Object Windows.Forms.Button; $btnClearProxy.Location = "422, 75"; $btnClearProxy.Size = "148, 30"; $btnClearProxy.FlatStyle = "Flat"; $btnClearProxy.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnClearProxy 8; $btnClearProxy.Text = "Clear Proxy"; $btnClearProxy.Font = $smallFont; $btnClearProxy.Cursor = "Hand"

function Update-RoutingToggle {
    if ($global:lastXrayMode -eq "Proxy Mode") { $btnProxyMode.BackColor = "#4F7C9B"; $btnProxyMode.ForeColor = "#FFFFFF"; $btnClearProxy.BackColor = "#2D3748"; $btnClearProxy.ForeColor = "#A0AEC0" } 
    else { $btnClearProxy.BackColor = "#4A5568"; $btnClearProxy.ForeColor = "#FFFFFF"; $btnProxyMode.BackColor = "#2D3748"; $btnProxyMode.ForeColor = "#A0AEC0" }
}
Update-RoutingToggle 

# Connect Button precisely 4 pixels below the proxy mode buttons
$btnAction = New-Object Windows.Forms.Button; $btnAction.Location = "270, 109"; $btnAction.Size = "300, 60"; $btnAction.BackColor = $colorBtn; $btnAction.ForeColor = $colorText; $btnAction.FlatStyle = "Flat"; $btnAction.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAction 15; $btnAction.Text = ""; $btnAction.Cursor = [System.Windows.Forms.Cursors]::Hand

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


# --- UI LAYOUT: ADVANCED OPTIONS (GRID ALIGNED, EXACTLY 30px HEIGHT) ---
$lblSplit = New-Object Windows.Forms.Label; $lblSplit.Text = "Direct Websites/IPs (comma separated):"; $lblSplit.Location = "20, 184"; $lblSplit.Size = "260, 20"; $lblSplit.ForeColor = "#A0AEC0"; $lblSplit.Font = $smallFont; $lblSplit.Visible = $false
$chkV2rayChain = New-Object Windows.Forms.CheckBox; $chkV2rayChain.Text = "Chain a custom V2Ray config"; $chkV2rayChain.Location = "300, 184"; $chkV2rayChain.Size = "200, 20"; $chkV2rayChain.ForeColor = "#A0AEC0"; $chkV2rayChain.Font = $smallFont; $chkV2rayChain.FlatStyle = "Flat"; $chkV2rayChain.Visible = $false; $chkV2rayChain.Checked = $global:enableV2rayChain

$txtSplit = New-Object Windows.Forms.TextBox; $txtSplit.Location = "20, 204"; $txtSplit.Size = "260, 30"; $txtSplit.BackColor = "#2D3748"; $txtSplit.ForeColor = "White"; $txtSplit.BorderStyle = "None"; $txtSplit.Multiline = $true; Set-RoundedCorners $txtSplit 5; $txtSplit.Visible = $false; $txtSplit.Text = $lastManualSplit
$btnSetupV2ray = New-Object Windows.Forms.Button; $btnSetupV2ray.Text = "Configure Node"; $btnSetupV2ray.Location = "300, 204"; $btnSetupV2ray.Size="270, 30"; $btnSetupV2ray.BackColor = $colorBtn; $btnSetupV2ray.ForeColor = $colorText; $btnSetupV2ray.FlatStyle = "Flat"; $btnSetupV2ray.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnSetupV2ray 5; $btnSetupV2ray.Visible = $false

$btnDesktop = New-Object Windows.Forms.Button; $btnDesktop.Location = "20, 244"; $btnDesktop.Size = "260, 30"; $btnDesktop.Text = "Create Desktop Shortcut"; $btnDesktop.BackColor = $colorBtn; $btnDesktop.ForeColor = $colorText; $btnDesktop.FlatStyle = "Flat"; $btnDesktop.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnDesktop 5; $btnDesktop.Font = $smallFont; $btnDesktop.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnDesktop.Visible = $false
$btnUpdate = New-Object Windows.Forms.Button; $btnUpdate.Location = "300, 244"; $btnUpdate.Size = "270, 30"; $btnUpdate.Text = "Check for Updates"; $btnUpdate.BackColor = $colorBtn; $btnUpdate.ForeColor = $colorText; $btnUpdate.FlatStyle = "Flat"; $btnUpdate.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnUpdate 5; $btnUpdate.Font = $smallFont; $btnUpdate.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnUpdate.Visible = $false

$chkLaunchBoot = New-Object Windows.Forms.CheckBox; $chkLaunchBoot.Location = "20, 284"; $chkLaunchBoot.Size = "250, 20"; $chkLaunchBoot.Text = "Launch on Windows Boot"; $chkLaunchBoot.ForeColor = "#A0AEC0"; $chkLaunchBoot.Font = $smallFont; $chkLaunchBoot.Checked = $launchOnBoot; $chkLaunchBoot.FlatStyle = "Flat"; $chkLaunchBoot.Visible = $false
$chkDebug = New-Object Windows.Forms.CheckBox; $chkDebug.Location = "300, 284"; $chkDebug.Size = "250, 20"; $chkDebug.Text = "Debug Mode"; $chkDebug.ForeColor = "#A0AEC0"; $chkDebug.Font = $smallFont; $chkDebug.FlatStyle = "Flat"; $chkDebug.Visible = $false

$lblProxy = New-Object Windows.Forms.Label; $lblProxy.Location = "10, 179"; $lblProxy.Size = "580, 40"; $lblProxy.ForeColor = $colorIP; $lblProxy.Font = $smallFont; $lblProxy.Text = "Local Socks: 127.0.0.1:10800`nLan Socks: $lanIp`:10800"; $lblProxy.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $lblProxy.Visible = $false

# --- DYNAMIC RESIZING EVENT ---
$chkShowAdvanced.Add_CheckedChanged({ 
    $show = $chkShowAdvanced.Checked
    $chkLaunchBoot.Visible = $show; $chkDebug.Visible = $show; $btnDesktop.Visible = $show; $btnUpdate.Visible = $show
    $lblSplit.Visible = $show; $txtSplit.Visible = $show; $chkV2rayChain.Visible = $show; $btnSetupV2ray.Visible = $show
    if ($show) { $form.ClientSize = New-Object Drawing.Size(600, 354); $lblProxy.Location = "10, 309" } 
    else { $form.ClientSize = New-Object Drawing.Size(600, 234); $lblProxy.Location = "10, 179" }
})

# --- EVENT BINDINGS ---
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
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $remoteCode = Invoke-RestMethod -Uri $repoRawUrl -UseBasicParsing
        if ($remoteCode -match '`$global:currentVersion\s*=\s*"([^"]+)"') {
            if ([version]$matches[1] -gt [version]$global:currentVersion) {
                if ([System.Windows.Forms.MessageBox]::Show("Version $($matches[1]) is available! Update?", "Update", 4, 64) -eq "Yes") {
                    Stop-AllEngines; $remoteCode | Set-Content "$global:baseDir\multiplexer_update.ps1"
                    
                    # Safe bat creation utilizing global pathing logic
                    $batContent = "@echo off`ntimeout /t 2 > nul`nmove /y `"$global:baseDir\multiplexer_update.ps1`" `"$global:scriptPath`"`nstart wscript.exe `"$global:baseDir\Launch Multiplexer.vbs`"`ndel `"%~f0`""
                    $batContent | Set-Content "$global:baseDir\update.bat"
                    
                    Start-Process "$global:baseDir\update.bat" -WindowStyle Hidden; [Environment]::Exit(0)
                }
            } else { [System.Windows.Forms.MessageBox]::Show("You are already on the latest version!", "Up to Date") }
        }
    } catch {}
    $btnUpdate.Text = "Check for Updates"
}
$btnUpdate.Add_Click({ Update-Application })

$chkV2rayChain.Add_CheckedChanged({
    if ($chkV2rayChain.Checked -and [string]::IsNullOrWhiteSpace($global:v2rayChainJson)) {
        if (-not (Show-V2rayDialog)) { $chkV2rayChain.Checked = $false }
    }
    $global:enableV2rayChain = $chkV2rayChain.Checked
})
$btnSetupV2ray.Add_Click({ Show-V2rayDialog })

$paintCombo = {
    param($sender, $e); if ($e.Index -lt 0) { return }; $g = $e.Graphics; $rect = $e.Bounds; $text = $sender.Items[$e.Index].ToString()
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#2D3748")); $hvrBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#4A5568")); $txtBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#E2E8F0"))
    if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected) { $g.FillRectangle($hvrBrush, $rect) } else { $g.FillRectangle($bgBrush, $rect) }
    $g.DrawString($text, $sender.Font, $txtBrush, $rect.X + 2, $rect.Y + 2); $bgBrush.Dispose(); $hvrBrush.Dispose(); $txtBrush.Dispose()
}
$comboBridge.Add_DrawItem($paintCombo); $comboConfig.Add_DrawItem($paintCombo); $comboCount.Add_DrawItem($paintCombo)

$toggleAction = {
    param($mode); if ($global:lastXrayMode -ne $mode) {
        $global:lastXrayMode = $mode; Update-RoutingToggle
        $selConfig = if ($comboConfig.SelectedItem.ToString() -match "Stable") { "Stable" } else { "Fast" }; $selCount = [int]($comboCount.SelectedItem.ToString().Replace(" (default)", ""))
        @{ AutoStart = [bool]$chkAutoStart.Checked; LaunchOnBoot = [bool]$chkLaunchBoot.Checked; LastConfig = $selConfig; SelectedBridge = $comboBridge.SelectedItem; InstanceCount = $selCount; XrayMode = $mode; ManualSplit = $txtSplit.Text; CustomBridgeLine = $global:customBridgeLine; EnableV2rayChain = $global:enableV2rayChain; V2rayChainJson = $global:v2rayChainJson } | ConvertTo-Json -Depth 10 | Set-Content $cfgFile
        if ($global:isConnected) { Restart-Xray $mode }
    }
}
$btnProxyMode.Add_Click({ &$toggleAction "Proxy Mode" }); $btnClearProxy.Add_Click({ &$toggleAction "Clear Proxy" })

$chkLaunchBoot.Add_CheckedChanged({
    $startupFolder = [Environment]::GetFolderPath('Startup'); $shortcutPath = Join-Path $startupFolder "TorMultiplexer.lnk"
    if ($chkLaunchBoot.Checked) {
        try { $WshShell = New-Object -ComObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut($shortcutPath); $Shortcut.TargetPath = Join-Path $global:baseDir "Launch Multiplexer.vbs"; $Shortcut.WorkingDirectory = $global:baseDir; $Shortcut.Save() } 
        catch { [System.Windows.Forms.MessageBox]::Show("Failed to create Startup shortcut.", "Error", 0, 16); $chkLaunchBoot.Checked = $false }
    } else { if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue } }
    $selConfig = if ($comboConfig.SelectedItem.ToString() -match "Stable") { "Stable" } else { "Fast" }; $selCount = [int]($comboCount.SelectedItem.ToString().Replace(" (default)", ""))
    @{ AutoStart = [bool]$chkAutoStart.Checked; LaunchOnBoot = [bool]$chkLaunchBoot.Checked; LastConfig = $selConfig; SelectedBridge = $comboBridge.SelectedItem; InstanceCount = $selCount; XrayMode = $global:lastXrayMode; ManualSplit = $txtSplit.Text; CustomBridgeLine = $global:customBridgeLine; EnableV2rayChain = $global:enableV2rayChain; V2rayChainJson = $global:v2rayChainJson } | ConvertTo-Json -Depth 10 | Set-Content $cfgFile
})

# --- CORE FUNCTIONS ---
function Write-XrayConfig($manualList) {
    $rules = @( @{ type="field"; ip=@("127.0.0.0/8", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"); outboundTag="direct" } )
    $domains = @(); $ips = @()
    if ($manualList -ne "") {
        $list = $manualList.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($item in $list) { if ($item -match "[a-zA-Z]") { $domains += $item } else { $ips += $item } }
        if ($domains.Count -gt 0) { $rules += @{ type="field"; domain=$domains; outboundTag="direct" } }
        if ($ips.Count -gt 0) { $rules += @{ type="field"; ip=$ips; outboundTag="direct" } }
    }
    
    $inbound = @{ listen="0.0.0.0"; port=10818; protocol="mixed"; settings=@{ udp=$true }; sniffing=@{ enabled=$true; destOverride=@("http","tls","quic","fakedns") } }
    
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
    $config = @{ log = @{ logLevel="warning" }; inbounds = @($inbound); outbounds = $outbounds; routing = @{ domainStrategy="AsIs"; rules=$rules } }
    $config | ConvertTo-Json -Depth 10 | Set-Content "$xrayDir\config.json"
}

function Set-SystemProxy($enable) {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($enable) { Set-ItemProperty $path -Name "ProxyEnable" -Value 1; Set-ItemProperty $path -Name "ProxyServer" -Value "127.0.0.1:10818" } 
    else { Set-ItemProperty $path -Name "ProxyEnable" -Value 0 }
    $WinInet::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null; $WinInet::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Restart-Xray($targetMode) {
    Get-Process xray -ErrorAction SilentlyContinue | ForEach-Object { try { if ($null -ne $_.Path -and $_.Path -eq "$xrayDir\xray.exe") { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } } catch {} }
    if ($null -ne $global:cmdDebugPid) { Stop-Process -Id $global:cmdDebugPid -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid = $null }
    Start-Sleep -Milliseconds 500
    Write-XrayConfig $txtSplit.Text
    if ($chkDebug.Checked) { $p = Start-Process "cmd.exe" -ArgumentList "/c `"title XrayDebug & .\xray.exe run -c config.json || pause`"" -WorkingDirectory $xrayDir -WindowStyle Normal -PassThru; $global:cmdDebugPid = $p.Id } 
    else { Start-Process -FilePath "$xrayDir\xray.exe" -ArgumentList "run -c config.json" -WorkingDirectory $xrayDir -WindowStyle Hidden }
    if ($targetMode -eq "Proxy Mode") { Set-SystemProxy $true } else { Set-SystemProxy $false }
}

$txtSplit.Add_KeyDown({ param($sender, $e)
    if ($e.KeyCode -eq 'Enter') {
        $e.SuppressKeyPress = $true; $selConfig = if ($comboConfig.SelectedItem.ToString() -match "Stable") { "Stable" } else { "Fast" }; $selCount = [int]($comboCount.SelectedItem.ToString().Replace(" (default)", ""))
        @{ AutoStart = [bool]$chkAutoStart.Checked; LaunchOnBoot = [bool]$chkLaunchBoot.Checked; LastConfig = $selConfig; SelectedBridge = $comboBridge.SelectedItem; InstanceCount = $selCount; XrayMode = $global:lastXrayMode; ManualSplit = $txtSplit.Text; CustomBridgeLine = $global:customBridgeLine; EnableV2rayChain = $global:enableV2rayChain; V2rayChainJson = $global:v2rayChainJson } | ConvertTo-Json -Depth 10 | Set-Content $cfgFile
        if ($global:isConnected) { Restart-Xray $global:lastXrayMode }
    }
})

function Reset-ButtonText { 
    $global:btnMainText = "CONNECT"
    $global:btnSubText = "(click to start)"
    if ($global:enableV2rayChain -and -not [string]::IsNullOrWhiteSpace($global:v2rayChainJson)) {
        $lblProxy.Text = "Local Socks (chained): 127.0.0.1:10818`nLan Socks (chained): $lanIp`:10818"
    } else {
        $lblProxy.Text = "Local Socks: 127.0.0.1:10800`nLan Socks: $lanIp`:10800"
    }
    $btnAction.Refresh() 
}

function Stop-AllEngines {
    $global:abortBoot = $true; Set-SystemProxy $false
    Get-Process tor, haproxy, xray -ErrorAction SilentlyContinue | ForEach-Object { try { $p = $_.Path; if ($null -ne $p -and ($p -eq "$xrayDir\xray.exe" -or $p -eq "$haPath\haproxy.exe" -or $p -match "Data\\Tors\\Tor")) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } } catch {} }
    if ($null -ne $global:cmdDebugPid) { Stop-Process -Id $global:cmdDebugPid -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid = $null }
    $global:isConnected = $false; Reset-ButtonText; $btnAction.Enabled = $true; $lblProxy.Visible = $false
}

function Wait-NonBlocking($s) { $end = (Get-Date).AddSeconds($s); while((Get-Date) -lt $end) { if($global:abortBoot){return}; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -ms 100 } }

function Format-HAProxyConfig($activeCount) {
    $haPathCfg = "$haPath\haproxy.cfg"
    if (Test-Path $haPathCfg) {
        $haData = Get-Content $haPathCfg; $newHaData = @()
        foreach ($line in $haData) {
            if ($line -match "^\s*#?\s*server\s+tor(\d+)") {
                if ([int]$matches[1] -le $activeCount) { $newHaData += ($line -replace "^\s*#+\s*", "    ") } else { if ($line -notmatch "^\s*#") { $newHaData += "    # $line" } else { $newHaData += $line } }
            } else { $newHaData += $line }
        }
        $newHaData | Set-Content $haPathCfg
    }
}

function Start-Engines {
    if (Get-Process tor -ErrorAction SilentlyContinue) { $global:btnSubText = "Clearing old engines..."; $btnAction.Refresh(); [System.Windows.Forms.Application]::DoEvents(); Stop-AllEngines; Start-Sleep -Seconds 1 }
    $global:abortBoot = $false; $lblProxy.Visible = $false; $selBridge = $comboBridge.SelectedItem
    $selConfig = if ($comboConfig.SelectedItem.ToString() -match "Stable") { "Stable" } else { "Fast" }; $selCount = [int]($comboCount.SelectedItem.ToString().Replace(" (default)", ""))
    $mode = $global:lastXrayMode; $cfgFileTarget = if ($selConfig -eq "Stable") { "torrc" } else { "torrc2" }

    @{ AutoStart = [bool]$chkAutoStart.Checked; LaunchOnBoot = [bool]$chkLaunchBoot.Checked; LastConfig = $selConfig; SelectedBridge = $selBridge; InstanceCount = $selCount; XrayMode = $mode; ManualSplit = $txtSplit.Text; CustomBridgeLine = $global:customBridgeLine; EnableV2rayChain = $global:enableV2rayChain; V2rayChainJson = $global:v2rayChainJson } | ConvertTo-Json -Depth 10 | Set-Content $cfgFile
    
    $winStyle = if ($chkDebug.Checked) { "Normal" } else { "Hidden" }; $global:btnMainText = "CONNECTING..."; Format-HAProxyConfig $selCount; $dynamicWait = 16 - $selCount
    
    for ($i=1; $i -le $selCount; $i++) {
        if ($global:abortBoot) { break } 
        $global:btnSubText = "Booting Tor $i of $selCount... (click to abort)"; $btnAction.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        $path = "$global:baseDir\Data\Tors\Tor$i"
        if (Test-Path "$path\$cfgFileTarget") {
            
            $c = @(Get-Content "$path\$cfgFileTarget")
            $cleanConfig = @()
            foreach ($line in $c) {
                if ($line -match "^# --- MANAGED BRIDGES ---") { break }
                if ($line -notmatch "^UseBridges" -and $line -notmatch "^ClientTransportPlugin" -and $line -notmatch "^Bridge") {
                    if ($line.Trim() -ne "") { $cleanConfig += $line.Trim() }
                }
            }
            
            $cleanConfig += "" 
            $cleanConfig += "# --- MANAGED BRIDGES ---"
            
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
        
        if ($global:enableV2rayChain -and -not [string]::IsNullOrWhiteSpace($global:v2rayChainJson)) {
            $lblProxy.Text = "Local Socks (chained): 127.0.0.1:10818`nLan Socks (chained): $lanIp`:10818"
        } else {
            $lblProxy.Text = "Local Socks: 127.0.0.1:10800`nLan Socks: $lanIp`:10800"
        }

        $global:isConnected = $true; $global:btnMainText = "CONNECTED"; $global:btnSubText = "(click to disconnect)"; $btnAction.Enabled = $true; $lblProxy.Visible = $true
    } else { Reset-ButtonText; $btnAction.Enabled = $true }
    $btnAction.Refresh()
}

$form.Add_Shown({ if ($chkAutoStart.Checked -and -not $isFirstLaunch) { Wait-NonBlocking 1; if (-not $global:abortBoot) { Start-Engines } } })
$form.Controls.AddRange(@($lblBridge, $comboBridge, $lblConfig, $comboConfig, $lblCount, $comboCount, $btnProxyMode, $btnClearProxy, $btnAction, $chkShowAdvanced, $chkLaunchBoot, $chkDebug, $lblSplit, $txtSplit, $chkV2rayChain, $btnSetupV2ray, $btnDesktop, $btnUpdate, $chkAutoStart, $lblProxy))
$form.ShowDialog()