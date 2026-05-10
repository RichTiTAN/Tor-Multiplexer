Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- GLOBAL BOOT FLAG & STATE ---
$global:abortBoot = $false
$global:currentConfig = $null

# --- DYNAMIC BUTTON TEXT STATES ---
$global:stableMain = "CONNECT"
$global:stableSub  = "(stable config)"
$global:fastMain   = "CONNECT"
$global:fastSub    = "(fast config)"

# --- CONFIGURATION & MEMORY MANAGER ---
$cfgFile = "$PSScriptRoot\multiplexer_settings.json"
$autoStartEnabled = $false
$lastConfig = "torrc"
$lastBridge = "meek_lite"

if (Test-Path $cfgFile) {
    try {
        $settings = Get-Content $cfgFile -Raw | ConvertFrom-Json
        $autoStartEnabled = [bool]$settings.AutoStart
        $lastConfig = [string]$settings.LastConfig
        
        if ($null -ne $settings.SelectedBridge) {
            $lastBridge = [string]$settings.SelectedBridge
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

$colorBg     = [System.Drawing.ColorTranslator]::FromHtml("#1A1A1B")
$colorBtn    = [System.Drawing.ColorTranslator]::FromHtml("#3A3F44") 
$colorV2     = [System.Drawing.ColorTranslator]::FromHtml("#4F7C9B") 
$colorStop   = [System.Drawing.ColorTranslator]::FromHtml("#A8544F") 
$colorText   = [System.Drawing.ColorTranslator]::FromHtml("#E2E8F0") 
$colorIP     = [System.Drawing.ColorTranslator]::FromHtml("#A0AEC0") 

# --- BRIDGE DATABASE ---
$ptPath = "$PSScriptRoot\Data\PluggableTransports"

$bridgeData = @{
    "meek_lite" = @{
        "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec $ptPath\lyrebird.exe"
        "lines"  = @("Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN")
    }
    "obfs4" = @{
        "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec $ptPath\lyrebird.exe"
        "lines"  = @(
            "Bridge obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0",
            "Bridge obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0",
            "Bridge obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0",
            "Bridge obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0",
            "Bridge obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0",
            "Bridge obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1",
            "Bridge obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1"
        )
    }
    "snowflake" = @{
        "plugin" = "ClientTransportPlugin snowflake exec $ptPath\lyrebird.exe"
        "lines"  = @(
            "Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn",
            "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn"
        )
    }
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
$form.Text = "Tor Multiplexer"
$form.ClientSize = New-Object Drawing.Size(400, 500) # Slightly shorter since we removed the status label
$form.StartPosition = "CenterScreen"
$form.BackColor = $colorBg

$centerX = ($form.ClientSize.Width - 300) / 2

# --- UI CONTROLS ---
$chkDebug = New-Object Windows.Forms.CheckBox
$chkDebug.Location = New-Object Drawing.Point($centerX, 15); $chkDebug.Size = New-Object Drawing.Size(300, 20)
$chkDebug.Text = "Debug Mode"; $chkDebug.ForeColor = "#A0AEC0"; $chkDebug.Font = $smallFont

$lblBridge = New-Object Windows.Forms.Label
$lblBridge.Location = New-Object Drawing.Point($centerX, 45); $lblBridge.Size = New-Object Drawing.Size(300, 20)
$lblBridge.Text = "Bridge Type:"; $lblBridge.ForeColor = "#A0AEC0"; $lblBridge.Font = $smallFont

# The Custom Drawn Dropdown
$comboBridge = New-Object Windows.Forms.ComboBox
$comboBridge.Location = New-Object Drawing.Point($centerX, 65)
$comboBridge.Size = New-Object Drawing.Size(300, 25)
$comboBridge.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
$comboBridge.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$comboBridge.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#2D3748")
$comboBridge.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#E2E8F0")
$comboBridge.Font = $smallFont
$comboBridge.Cursor = [System.Windows.Forms.Cursors]::Hand
$comboBridge.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$comboBridge.ItemHeight = 20

$comboBridge.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }

    $graphics = $e.Graphics
    $rect = $e.Bounds
    $text = $sender.Items[$e.Index].ToString()
    
    $baseBgColor  = [System.Drawing.ColorTranslator]::FromHtml("#2D3748")
    $hoverBgColor = [System.Drawing.ColorTranslator]::FromHtml("#4A5568")
    $textColor    = [System.Drawing.ColorTranslator]::FromHtml("#E2E8F0")

    $bgBrush   = New-Object System.Drawing.SolidBrush($baseBgColor)
    $hvrBrush  = New-Object System.Drawing.SolidBrush($hoverBgColor)
    $txtBrush  = New-Object System.Drawing.SolidBrush($textColor)

    if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected) {
        $graphics.FillRectangle($hvrBrush, $rect)
    } else {
        $graphics.FillRectangle($bgBrush, $rect)
    }

    $graphics.DrawString($text, $sender.Font, $txtBrush, $rect.X + 2, $rect.Y + 2)
    $bgBrush.Dispose(); $hvrBrush.Dispose(); $txtBrush.Dispose()
})

$null = $comboBridge.Items.AddRange(@("Direct (None)", "meek_lite", "obfs4", "snowflake"))
$comboBridge.SelectedItem = $lastBridge

# --- DYNAMIC CUSTOM PAINT BUTTON: STABLE ---
$btnStable = New-Object Windows.Forms.Button
$btnStable.Location = New-Object Drawing.Point($centerX, 105)
$btnStable.Size = New-Object Drawing.Size(300, 55)
$btnStable.BackColor = $colorBtn; $btnStable.ForeColor = $colorText; $btnStable.FlatStyle = "Flat"
$btnStable.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnStable 15
$btnStable.Text = "" 
$btnStable.Cursor = [System.Windows.Forms.Cursors]::Hand

$btnStable.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $fontSub  = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
    
    # If the text is CONNECTED, turn it green! Otherwise, use standard color or grey if disabled.
    if ($global:stableMain -eq "CONNECTED") {
        $tColor = [System.Drawing.ColorTranslator]::FromHtml("#68D391")
    } else {
        $tColor = if ($sender.Enabled) { $sender.ForeColor } else { [System.Drawing.ColorTranslator]::FromHtml("#718096") }
    }
    
    $brush = New-Object System.Drawing.SolidBrush($tColor)

    # Read from the dynamic variables instead of hardcoded text
    $szMain = $g.MeasureString($global:stableMain, $fontMain)
    $szSub  = $g.MeasureString($global:stableSub, $fontSub)

    $startY = ($sender.Height - ($szMain.Height + $szSub.Height - 5)) / 2

    $g.DrawString($global:stableMain, $fontMain, $brush, ($sender.Width - $szMain.Width) / 2, $startY)
    $g.DrawString($global:stableSub, $fontSub, $brush, ($sender.Width - $szSub.Width) / 2, $startY + $szMain.Height - 5)

    $fontMain.Dispose(); $fontSub.Dispose(); $brush.Dispose()
})
$btnStable.Add_Click({ Start-Engines "torrc" })


# --- DYNAMIC CUSTOM PAINT BUTTON: FAST ---
$btnFast = New-Object Windows.Forms.Button
$btnFast.Location = New-Object Drawing.Point($centerX, 175)
$btnFast.Size = New-Object Drawing.Size(300, 55)
$btnFast.BackColor = $colorBtn; $btnFast.ForeColor = $colorText; $btnFast.FlatStyle = "Flat"
$btnFast.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnFast 15
$btnFast.Text = ""
$btnFast.Cursor = [System.Windows.Forms.Cursors]::Hand

$btnFast.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    
    $fontMain = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $fontSub  = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
    
    if ($global:fastMain -eq "CONNECTED") {
        $tColor = [System.Drawing.ColorTranslator]::FromHtml("#68D391")
    } else {
        $tColor = if ($sender.Enabled) { $sender.ForeColor } else { [System.Drawing.ColorTranslator]::FromHtml("#718096") }
    }
    $brush = New-Object System.Drawing.SolidBrush($tColor)

    $szMain = $g.MeasureString($global:fastMain, $fontMain)
    $szSub  = $g.MeasureString($global:fastSub, $fontSub)

    $startY = ($sender.Height - ($szMain.Height + $szSub.Height - 5)) / 2

    $g.DrawString($global:fastMain, $fontMain, $brush, ($sender.Width - $szMain.Width) / 2, $startY)
    $g.DrawString($global:fastSub, $fontSub, $brush, ($sender.Width - $szSub.Width) / 2, $startY + $szMain.Height - 5)

    $fontMain.Dispose(); $fontSub.Dispose(); $brush.Dispose()
})
$btnFast.Add_Click({ Start-Engines "torrc2" })

# --- REMAINING CONTROLS ---
$chkAutoStart = New-Object Windows.Forms.CheckBox
$chkAutoStart.Location = New-Object Drawing.Point($centerX, 245); $chkAutoStart.Size = New-Object Drawing.Size(300, 20)
$chkAutoStart.Text = "Remember my choice"; $chkAutoStart.ForeColor = "#F6AD55"; $chkAutoStart.Font = $smallFont
$chkAutoStart.Checked = $autoStartEnabled

$btnV2 = New-Object Windows.Forms.Button
$btnV2.Location = New-Object Drawing.Point($centerX, 280); $btnV2.Size = New-Object Drawing.Size(300, 45)
$btnV2.Text = "Launch v2rayN"
$btnV2.BackColor = $colorV2; $btnV2.ForeColor = $colorText; $btnV2.Font = $classyFont; $btnV2.FlatStyle = "Flat"
$btnV2.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnV2 15
$btnV2.Add_Click({ Start-Process "$PSScriptRoot\Data\v2rayN\v2rayN.exe" })

$btnStop = New-Object Windows.Forms.Button
$btnStop.Location = New-Object Drawing.Point($centerX, 340); $btnStop.Size = New-Object Drawing.Size(300, 45)
$btnStop.Text = "STOP ALL PROCESSES"
$btnStop.BackColor = $colorStop; $btnStop.ForeColor = $colorText; $btnStop.Font = $classyFont; $btnStop.FlatStyle = "Flat"
$btnStop.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnStop 15
$btnStop.Add_Click({ Stop-AllEngines })

# --- IP LABELS (PULLED UP TO FILL EMPTY SPACE) ---
$lblHttp = New-Object Windows.Forms.Label
$lblHttp.Location = New-Object Drawing.Point($centerX, 405); $lblHttp.Size = New-Object Drawing.Size(300, 20)
$lblHttp.ForeColor = $colorIP; $lblHttp.Font = $classyFont; $lblHttp.Text = "Socks proxy open on:"
$lblHttp.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblHttp.Visible = $false

$lblLocal = New-Object Windows.Forms.Label
$lblLocal.Location = New-Object Drawing.Point($centerX, 425); $lblLocal.Size = New-Object Drawing.Size(300, 20)
$lblLocal.ForeColor = $colorIP; $lblLocal.Font = $classyFont; $lblLocal.Text = "Local: 127.0.0.1:10800"
$lblLocal.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblLocal.Visible = $false

$lblLan = New-Object Windows.Forms.Label
$lblLan.Location = New-Object Drawing.Point($centerX, 445); $lblLan.Size = New-Object Drawing.Size(300, 20)
$lblLan.ForeColor = $colorIP; $lblLan.Font = $classyFont; $lblLan.Text = "Lan: $lanIp`:10800"
$lblLan.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblLan.Visible = $false

# --- FUNCTIONS ---
function Reset-ButtonText {
    $global:stableMain = "CONNECT"; $global:stableSub = "(stable config)"
    $global:fastMain = "CONNECT"; $global:fastSub = "(fast config)"
    $btnStable.Refresh(); $btnFast.Refresh()
}

function Stop-AllEngines {
    $global:abortBoot = $true 
    Get-Process tor -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process haproxy -ErrorAction SilentlyContinue | Stop-Process -Force
    $global:currentConfig = $null
    
    Reset-ButtonText
    $btnStable.Enabled = $true; $btnFast.Enabled = $true
    $lblHttp.Visible = $false; $lblLocal.Visible = $false; $lblLan.Visible = $false
}

function Wait-NonBlocking($seconds) {
    $endTime = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $endTime) {
        if ($global:abortBoot) { return } 
        [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 
    }
}

function Update-TorConfig($filePath, $bridgeKey) {
    $content = Get-Content $filePath | Where-Object { $_ -notmatch "^UseBridges|^Bridge|^ClientTransportPlugin" }
    
    if ($bridgeKey -ne "Direct (None)") {
        $bridge = $bridgeData[$bridgeKey]
        $content += "UseBridges 1"
        $content += $bridge.plugin
        foreach ($line in $bridge.lines) { $content += $line }
    } else {
        $content += "UseBridges 0"
    }
    $content | Set-Content $filePath
}

function Start-Engines($cfg) {
    if (Get-Process tor -ErrorAction SilentlyContinue) {
        if ($cfg -eq "torrc") { $global:stableSub = "Switching configs..." } else { $global:fastSub = "Switching configs..." }
        $btnStable.Refresh(); $btnFast.Refresh(); [System.Windows.Forms.Application]::DoEvents()

        Get-Process tor -ErrorAction SilentlyContinue | Stop-Process -Force
        Get-Process haproxy -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
    }

    $global:abortBoot = $false
    $btnStable.Enabled = $false; $btnFast.Enabled = $false
    $lblHttp.Visible = $false; $lblLocal.Visible = $false; $lblLan.Visible = $false
    
    $selBridge = $comboBridge.SelectedItem
    $settingsObj = @{ AutoStart = [bool]$chkAutoStart.Checked; LastConfig = $cfg; SelectedBridge = $selBridge }
    $settingsObj | ConvertTo-Json | Set-Content $cfgFile
    
    $winStyle = if ($chkDebug.Checked) { "Normal" } else { "Hidden" }
    
    # 1. Update the Main Text to CONNECTING...
    if ($cfg -eq "torrc") { $global:stableMain = "CONNECTING..." } else { $global:fastMain = "CONNECTING..." }
    
    for ($i=1; $i -le 8; $i++) {
        if ($global:abortBoot) { break } 
        
        # 2. Push the Status dynamically into the subtitle
        $statusMsg = "Booting Engine $i of 8..."
        if ($cfg -eq "torrc") { $global:stableSub = $statusMsg } else { $global:fastSub = $statusMsg }
        $btnStable.Refresh(); $btnFast.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        
        $path = "$PSScriptRoot\Data\Tors\Tor$i"
        if (Test-Path "$path\$cfg") {
            Update-TorConfig "$path\$cfg" $selBridge
            Start-Process -FilePath "$path\tor.exe" -ArgumentList "-f $cfg" -WorkingDirectory $path -WindowStyle $winStyle
            Wait-NonBlocking 8
        }
    }
    
    if (-not $global:abortBoot) {
        $statusMsg = "Booting HAProxy..."
        if ($cfg -eq "torrc") { $global:stableSub = $statusMsg } else { $global:fastSub = $statusMsg }
        $btnStable.Refresh(); $btnFast.Refresh(); [System.Windows.Forms.Application]::DoEvents()

        $haPath = "$PSScriptRoot\Data\HAproxy"
        if (Test-Path "$haPath\haproxy.exe") {
            Start-Process -FilePath "$haPath\haproxy.exe" -ArgumentList "-f haproxy.cfg" -WorkingDirectory $haPath -WindowStyle $winStyle
        }
        
        # 3. Final State: Change main to CONNECTED and restore the config name
        if ($cfg -eq "torrc") { 
            $global:stableMain = "CONNECTED"
            $global:stableSub  = "(stable config)"
            $btnStable.Enabled = $false; $btnFast.Enabled = $true 
        } else { 
            $global:fastMain   = "CONNECTED"
            $global:fastSub    = "(fast config)"
            $btnStable.Enabled = $true; $btnFast.Enabled = $false 
        }

        $lblHttp.Visible = $true; $lblLocal.Visible = $true; $lblLan.Visible = $true
    } else {
        Reset-ButtonText
        $btnStable.Enabled = $true; $btnFast.Enabled = $true
    }
    
    $btnStable.Refresh(); $btnFast.Refresh()
}

$form.Add_Shown({
    if ($chkAutoStart.Checked -and $lastConfig) {
        Wait-NonBlocking 1
        if (-not $global:abortBoot) { Start-Engines $lastConfig }
    }
})

$form.Controls.AddRange(@($btnStable, $btnFast, $chkDebug, $lblBridge, $comboBridge, $chkAutoStart, $btnV2, $btnStop, $lblHttp, $lblLocal, $lblLan))
$form.ShowDialog()