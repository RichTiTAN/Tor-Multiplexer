# --- ADMIN ELEVATION (SILENT) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    [Environment]::Exit(0)
}

# --- ASSEMBLIES ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- LOCK SCOPE FOR EVENT HANDLERS ---
$global:baseDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($global:baseDir)) { $global:baseDir = (Get-Location).Path }
$global:scriptPath = $PSCommandPath
if ([string]::IsNullOrEmpty($global:scriptPath)) { $global:scriptPath = Join-Path $global:baseDir "multiplexer.ps1" }

# --- SYSTEM PROXY REFRESH API ---
if (-not ("Win32.WinInet" -as [type])) {
    $MethodDefinition = @'
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
'@
    Add-Type -MemberDefinition $MethodDefinition -Name 'WinInet' -Namespace 'Win32' -PassThru | Out-Null
}

# --- VERSION CONTROL & GLOBALS ---
$global:currentVersion = "4.7.5" 
$repoRawUrl = "https://raw.githubusercontent.com/RichTiTAN/Tor-Multiplexer/main/multiplexer.ps1"
$global:forceManualUpdate = $false
$global:abortBoot = $false
$global:isConnected = $false
$global:isEngineRunning = $false
$global:cmdDebugPid = $null 
$global:cmdDebugPid2 = $null 
$global:lastTotalBytes = 0
$global:sessionDataBytes = 0
$global:appInitialized = $false

# Stats Smoothing Buffer
$global:speedSamples = @(0,0,0,0,0)

# --- CONFIGURATION & PATHS ---
$cfgFile = "$global:baseDir\multiplexer_settings.json"
$xrayDir = "$global:baseDir\Data\Xray"
$haPath  = "$global:baseDir\Data\HAproxy"
$sbDir   = "$global:baseDir\Data\sing_box"

$autoStart = $true; $launchOnBoot = $false; $lastConfig = "Stable"; $lastBridge = "meek_lite"; $lastCount = "6"; $global:lastXrayMode = "Proxy Mode"; $global:lastManualSplit = ""; $global:enableDirect = $false; $global:customBridgeLine = ""; $global:v2rayChainJson = ""; $global:enableV2rayChain = $false
$global:outboundProxyAddress = ""; $global:outboundProxyPort = ""; $global:outboundProxyType = "SOCKS5"; $global:enableOutboundProxy = $false
$global:outboundProxyUser = ""; $global:outboundProxyPass = ""; $global:enableOutboundAuth = $false
$isFirstLaunch = $true 

if (Test-Path $cfgFile) {
    $isFirstLaunch = $false
    try {
        $s = Get-Content $cfgFile -Raw | ConvertFrom-Json
        if ($null -ne $s.AutoStart) { $autoStart = [bool]$s.AutoStart }
        if ($null -ne $s.LaunchOnBoot) { $launchOnBoot = [bool]$s.LaunchOnBoot }
        if ($null -ne $s.LastConfig) { $lastConfig = if ($s.LastConfig -match "Fast") { "Fast" } else { "Stable" } }
        if ($null -ne $s.SelectedBridge) { $lastBridge = [string]$s.SelectedBridge }
        if ($null -ne $s.InstanceCount) { 
            $c = [int]$s.InstanceCount
            $lastCount = [string]$c
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

$global:hasVpnComponents = $true
if (-not (Test-Path "$sbDir\sing-box.exe")) {
    $global:hasVpnComponents = $false
    if ($global:lastXrayMode -eq "VPN Mode") { $global:lastXrayMode = "Proxy Mode" } 
}

$lanIp = "UNKNOWN"
$ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { 
    $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notmatch '^127\.' -and $_.ToString() -notmatch '^169\.254\.' 
}
if ($ips) { $lanIp = $ips[0].ToString() }

# --- THEME BRUSHES FOR WPF & WINFORMS MODALS ---
$colorBgHex = "#1A1A1B"
$colorBtnHex = "#3A3F44"
$colorTextHex = "#E2E8F0"
$bc = New-Object System.Windows.Media.BrushConverter
$brushTogOn  = $bc.ConvertFromString("#4E7A5E")
$brushTogOff = $bc.ConvertFromString("#8B4A4A")
$brushBtnBg  = $bc.ConvertFromString($colorBtnHex)
$brushActiveRouting = $bc.ConvertFromString("#4F7C9B")
$brushInactiveRouting = $bc.ConvertFromString("#2D3748")
$brushDisabledVpn = $bc.ConvertFromString("#1A202C")

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

# --- WPF XAML UI ---
[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Tor Multiplexer - v$global:currentVersion" Height="295" Width="605" 
    WindowStartupLocation="CenterScreen" Background="#1A1A1B" Foreground="#E2E8F0"
    ResizeMode="CanMinimize" FontFamily="Segoe UI">
    
    <Window.Resources>
        <Style TargetType="ComboBox" x:Key="DarkComboBox">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="Background" Value="#1A202C"/>
            <Setter Property="BorderBrush" Value="#2D3748"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton Name="ToggleButton" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Focusable="False" IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="0,4,4,0">
                                            <ContentPresenter HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,5,0"/>
                                        </Border>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                                <Path Fill="#A0AEC0" Data="M0,0 L4,4 L8,0 Z" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,5,0"/>
                            </ToggleButton>
                            <ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="8,0,23,2" VerticalAlignment="Center" HorizontalAlignment="Left">
                                <ContentPresenter.Resources>
                                    <Style TargetType="TextBlock">
                                        <Setter Property="Foreground" Value="#E2E8F0"/>
                                    </Style>
                                </ContentPresenter.Resources>
                            </ContentPresenter>
                            <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Border Name="DropDownBorder" Background="#1A202C" BorderThickness="1" BorderBrush="#3A3F44" MinWidth="{TemplateBinding ActualWidth}">
                                    <ScrollViewer Margin="0,2" SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained" />
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="Padding" Value="4,2"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#4A5568"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="Button" x:Key="DarkButton">
            <Setter Property="Background" Value="#3A3F44"/>
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#4A5568"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        
        <Style TargetType="Button" x:Key="ActionButton" BasedOn="{StaticResource DarkButton}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Canvas>
        <Border Background="#2D3748" Canvas.Left="20" Canvas.Top="20" Width="85" Height="26" CornerRadius="4,0,0,4">
            <TextBlock Text="Bridge Type" FontSize="11" Foreground="#E2E8F0" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
        </Border>
        <ComboBox Name="comboBridge" Canvas.Left="105" Canvas.Top="20" Width="85" Height="26" FontSize="11" Style="{StaticResource DarkComboBox}"/>
        
        <Border Background="#2D3748" Canvas.Left="210" Canvas.Top="20" Width="85" Height="26" CornerRadius="4,0,0,4">
            <TextBlock Text="Routing" FontSize="11" Foreground="#E2E8F0" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
        </Border>
        <ComboBox Name="comboConfig" Canvas.Left="295" Canvas.Top="20" Width="85" Height="26" FontSize="11" Style="{StaticResource DarkComboBox}"/>

        <Border Background="#2D3748" Canvas.Left="400" Canvas.Top="20" Width="85" Height="26" CornerRadius="4,0,0,4">
            <TextBlock Text="Tor Engines" FontSize="11" Foreground="#E2E8F0" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
        </Border>
        <ComboBox Name="comboCount" Canvas.Left="485" Canvas.Top="20" Width="85" Height="26" FontSize="11" Style="{StaticResource DarkComboBox}"/>

        <Button Name="btnUpdate" Canvas.Left="20" Canvas.Top="66" Width="205" Height="25" Content="Check for Updates" Style="{StaticResource DarkButton}" FontSize="11"/>
        
        <Button Name="btnAutoStartLbl" Canvas.Left="20" Canvas.Top="98" Width="130" Height="25" Content="Auto-connect" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
        <Button Name="btnAutoStartTog" Canvas.Left="155" Canvas.Top="98" Width="70" Height="25" Content="Enabled" Style="{StaticResource DarkButton}" Background="#4E7A5E" FontSize="11"/>

        <Button Name="btnAdvLbl" Canvas.Left="20" Canvas.Top="130" Width="130" Height="25" Content="Advanced Settings" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
        <Button Name="btnAdvTog" Canvas.Left="155" Canvas.Top="130" Width="70" Height="25" Content="Show" Style="{StaticResource DarkButton}" FontSize="11"/>

        <Button Name="btnProxyMode" Canvas.Left="270" Canvas.Top="65" Width="98" Height="30" Content="Proxy Mode" Style="{StaticResource DarkButton}" Background="#4F7C9B" FontSize="11"/>
        
        <Button Name="btnVpnMode" Canvas.Left="371" Canvas.Top="65" Width="98" Height="30" Content="VPN Mode" Style="{StaticResource DarkButton}" FontSize="11">
            <Button.ToolTip>
                <ToolTip Name="vpnToolTip" Visibility="Collapsed" Content="You need to download the full version from GitHub to use VPN Mode."/>
            </Button.ToolTip>
        </Button>
        
        <Button Name="btnClearProxy" Canvas.Left="472" Canvas.Top="65" Width="98" Height="30" Content="Clear Proxy" Style="{StaticResource DarkButton}" FontSize="11"/>

        <Button Name="btnAction" Canvas.Left="270" Canvas.Top="100" Width="300" Height="55" Style="{StaticResource ActionButton}">
            <StackPanel>
                <TextBlock Name="btnActionMainText" Text="CONNECT" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center"/>
                <TextBlock Name="btnActionSubText" Text="(click to start)" FontSize="11" HorizontalAlignment="Center" Margin="0,2,0,0"/>
            </StackPanel>
        </Button>

        <Border Name="SocksPanel" Canvas.Left="20" Canvas.Top="180" Width="260" Height="65" Background="#2D3748" CornerRadius="4">
            <Canvas>
                <TextBlock Name="lblSocksTitle" Text="Mixed Port:" Canvas.Left="10" Canvas.Top="8" FontSize="11" Foreground="#A0AEC0"/>
                <TextBlock Name="lblSocksDataIPs" Text="Waiting for connection..." Canvas.Left="10" Canvas.Top="26" FontSize="11" Foreground="#E2E8F0"/>
                <TextBlock Name="lblSocksDataTags" Text="" Canvas.Right="10" Canvas.Top="26" FontSize="11" Foreground="#A0AEC0" TextAlignment="Right" Width="60"/>
            </Canvas>
        </Border>
        
        <Border Name="StatsPanel" Canvas.Left="300" Canvas.Top="180" Width="270" Height="65" Background="#2D3748" CornerRadius="4">
            <Canvas>
                <TextBlock Name="lblStatsTitle" Text="Stats:" Canvas.Left="10" Canvas.Top="8" FontSize="11" Foreground="#A0AEC0"/>
                <TextBlock Name="lblStatsData" Text="Speed: 0 KB/s&#x0a;Total: 0 MB" Canvas.Left="10" Canvas.Top="26" FontSize="12" FontFamily="Consolas" Foreground="#68D391" FontWeight="Bold"/>
            </Canvas>
        </Border>

        <Canvas Name="AdvancedCanvas" Canvas.Left="0" Canvas.Top="180" Opacity="0" Visibility="Hidden">
            <TextBlock Text="Advanced Options" Canvas.Left="20" Canvas.Top="0" Foreground="#A0AEC0" FontSize="11"/>
            <Rectangle Canvas.Left="150" Canvas.Top="8" Width="420" Height="1" Fill="#3A3F44"/>

            <Button Name="btnDirectConfig" Canvas.Left="20" Canvas.Top="30" Width="170" Height="25" Content="Split Tunneling" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
            <Button Name="btnDirectTog" Canvas.Left="195" Canvas.Top="30" Width="85" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>
            
            <Button Name="btnV2rayConfig" Canvas.Left="300" Canvas.Top="30" Width="180" Height="25" Content="Custom v2ray Exit-Node" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
            <Button Name="btnV2rayTog" Canvas.Left="485" Canvas.Top="30" Width="85" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>
            
            <Button Name="btnOutboundConfig" Canvas.Left="20" Canvas.Top="65" Width="170" Height="25" Content="Outbound Proxy" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
            <Button Name="btnOutboundTog" Canvas.Left="195" Canvas.Top="65" Width="85" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>

            <Button Name="btnBootLbl" Canvas.Left="300" Canvas.Top="65" Width="180" Height="25" Content="Launch on Start-up" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
            <Button Name="btnBootTog" Canvas.Left="485" Canvas.Top="65" Width="85" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>

            <Button Name="btnDebugLbl" Canvas.Left="20" Canvas.Top="100" Width="170" Height="25" Content="Debug Mode" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
            <Button Name="btnDebugTog" Canvas.Left="195" Canvas.Top="100" Width="85" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>

            <Button Name="btnLogsLbl" Canvas.Left="300" Canvas.Top="100" Width="180" Height="25" Content="Live Logs" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
            <Button Name="btnLogsTog" Canvas.Left="485" Canvas.Top="100" Width="85" Height="25" Content="Show" Style="{StaticResource DarkButton}" FontSize="11"/>

            <Button Name="btnDesktop" Canvas.Left="20" Canvas.Top="135" Width="260" Height="25" Content="Create Desktop Shortcut" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
            
            <!-- Contact Box Group (Symmetrical & Scaled) -->
            <Border Canvas.Left="300" Canvas.Top="135" Width="270" Height="26" Background="#1A202C" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4">
                <Canvas>
                    <Border Background="#2D3748" Width="90" Height="24" CornerRadius="3,0,0,3">
                        <TextBlock Text="Find Me On" Foreground="#A0AEC0" FontSize="11" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                    </Border>
                    <Button Name="btnGithub" Canvas.Left="90" Width="89" Height="24" Content="GitHub" Style="{StaticResource DarkButton}" Background="#1A202C" FontSize="11"/>
                    <Rectangle Canvas.Left="179" Width="1" Height="24" Fill="#2D3748"/>
                    <Button Name="btnTelegram" Canvas.Left="180" Width="88" Height="24" Content="Telegram" Style="{StaticResource DarkButton}" Background="#1A202C" FontSize="11"/>
                </Canvas>
            </Border>
        </Canvas>

        <!-- LIVE LOGS PANEL -->
        <Canvas Name="LogsCanvas" Canvas.Left="585" Canvas.Top="20" Width="300" Height="225" Visibility="Hidden" Opacity="0">
            <Border Name="logBorder" Background="#121417" Width="300" Height="225" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="TOR BOOTSTRAP STATUS" Canvas.Left="15" Canvas.Top="10" Foreground="#A0AEC0" FontSize="10" FontWeight="Bold"/>
                    
                    <!-- Left Column -->
                    <TextBlock Name="lblTor1" Text="Tor 01: Offline" Canvas.Left="15" Canvas.Top="30" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor2" Text="Tor 02: Offline" Canvas.Left="15" Canvas.Top="48" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor3" Text="Tor 03: Offline" Canvas.Left="15" Canvas.Top="66" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor4" Text="Tor 04: Offline" Canvas.Left="15" Canvas.Top="84" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    
                    <!-- Right Column -->
                    <TextBlock Name="lblTor5" Text="Tor 05: Offline" Canvas.Left="155" Canvas.Top="30" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor6" Text="Tor 06: Offline" Canvas.Left="155" Canvas.Top="48" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor7" Text="Tor 07: Offline" Canvas.Left="155" Canvas.Top="66" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor8" Text="Tor 08: Offline" Canvas.Left="155" Canvas.Top="84" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    
                    <Rectangle Canvas.Left="15" Canvas.Top="110" Width="270" Height="1" Fill="#2D3748" />
                    <TextBlock Text="CONNECTIONS" Canvas.Left="15" Canvas.Top="120" Foreground="#A0AEC0" FontSize="10" FontWeight="Bold" />
                    
                    <TextBox Name="txtXrayLogs" Canvas.Left="15" Canvas.Top="138" Width="270" Height="75" 
                             Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             FontSize="10" TextWrapping="Wrap" VerticalScrollBarVisibility="Hidden" HorizontalScrollBarVisibility="Hidden" IsReadOnly="True" FontFamily="Consolas" />
                </Canvas>
            </Border>
        </Canvas>
    </Canvas>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$form = [Windows.Markup.XamlReader]::Load($reader)

# --- MAP WPF ELEMENTS TO POWERSHELL ---
$comboBridge = $form.FindName("comboBridge")
$comboConfig = $form.FindName("comboConfig")
$comboCount = $form.FindName("comboCount")
$btnAction = $form.FindName("btnAction")
$btnActionMainText = $form.FindName("btnActionMainText")
$btnActionSubText = $form.FindName("btnActionSubText")
$btnProxyMode = $form.FindName("btnProxyMode")
$btnVpnMode = $form.FindName("btnVpnMode")
$vpnToolTip = $form.FindName("vpnToolTip")
$btnClearProxy = $form.FindName("btnClearProxy")
$btnUpdate = $form.FindName("btnUpdate")
$btnAutoStartLbl = $form.FindName("btnAutoStartLbl")
$btnAutoStartTog = $form.FindName("btnAutoStartTog")
$btnAdvLbl = $form.FindName("btnAdvLbl")
$btnAdvTog = $form.FindName("btnAdvTog")
$btnDirectConfig = $form.FindName("btnDirectConfig")
$btnDirectTog = $form.FindName("btnDirectTog")
$btnV2rayConfig = $form.FindName("btnV2rayConfig")
$btnV2rayTog = $form.FindName("btnV2rayTog")
$btnOutboundConfig = $form.FindName("btnOutboundConfig")
$btnOutboundTog = $form.FindName("btnOutboundTog")
$btnBootLbl = $form.FindName("btnBootLbl")
$btnBootTog = $form.FindName("btnBootTog")
$btnDebugLbl = $form.FindName("btnDebugLbl")
$btnDebugTog = $form.FindName("btnDebugTog")
$btnLogsLbl = $form.FindName("btnLogsLbl")
$btnLogsTog = $form.FindName("btnLogsTog")
$btnDesktop = $form.FindName("btnDesktop")
$btnGithub = $form.FindName("btnGithub")
$btnTelegram = $form.FindName("btnTelegram")
$AdvancedCanvas = $form.FindName("AdvancedCanvas")
$LogsCanvas = $form.FindName("LogsCanvas")
$logBorder = $form.FindName("logBorder")
$txtXrayLogs = $form.FindName("txtXrayLogs")
$SocksPanel = $form.FindName("SocksPanel")
$StatsPanel = $form.FindName("StatsPanel")
$lblSocksTitle = $form.FindName("lblSocksTitle")
$lblSocksDataIPs = $form.FindName("lblSocksDataIPs")
$lblSocksDataTags = $form.FindName("lblSocksDataTags")
$lblStatsTitle = $form.FindName("lblStatsTitle")
$lblStatsData = $form.FindName("lblStatsData")

function Add-ComboItem($combo, $text, $tag) {
    $cbi = New-Object System.Windows.Controls.ComboBoxItem
    $cbi.Content = $text; $cbi.Tag = $tag
    $combo.Items.Add($cbi) | Out-Null
}

Add-ComboItem $comboBridge "Direct (None)" "Direct (None)"
Add-ComboItem $comboBridge "meek_lite" "meek_lite"
Add-ComboItem $comboBridge "obfs4" "obfs4"
Add-ComboItem $comboBridge "snowflake" "snowflake"
Add-ComboItem $comboBridge "Custom" "Custom"

Add-ComboItem $comboConfig "Stable" "Stable"
Add-ComboItem $comboConfig "Fast" "Fast"

Add-ComboItem $comboCount "1" "1"
Add-ComboItem $comboCount "2" "2"
Add-ComboItem $comboCount "3" "3"
Add-ComboItem $comboCount "4" "4"
Add-ComboItem $comboCount "5" "5"
Add-ComboItem $comboCount "6" "6"
Add-ComboItem $comboCount "7" "7"
Add-ComboItem $comboCount "8" "8"

function Set-ComboSelectedTag($combo, $tag) {
    foreach ($item in $combo.Items) {
        if ($item.Tag -eq $tag -or $item.Content -match $tag) { $combo.SelectedItem = $item; break }
    }
}

Set-ComboSelectedTag $comboBridge $lastBridge
Set-ComboSelectedTag $comboConfig $lastConfig
Set-ComboSelectedTag $comboCount $lastCount
if ($null -ne $comboBridge.SelectedItem) { $global:previousBridge = $comboBridge.SelectedItem.Tag } else { $global:previousBridge = "meek_lite" }

# --- WPF HELPER FUNCTIONS ---
function DoEvents {
    try {
        $form.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]{})
        [System.Windows.Forms.Application]::DoEvents()
    } catch {}
}
function Wait-NonBlocking($s) { $end = (Get-Date).AddSeconds($s); while((Get-Date) -lt $end) { if($global:abortBoot){return}; DoEvents; Start-Sleep -Milliseconds 50 } }
function Set-WpfToggleState($btn, $state, $onText="Enabled", $offText="Disabled") {
    if ($state) { $btn.Content = $onText; $btn.Background = $brushTogOn } else { $btn.Content = $offText; $btn.Background = $brushTogOff }
}

# Apply Initial States
Set-WpfToggleState $btnAutoStartTog $autoStart
Set-WpfToggleState $btnDirectTog $global:enableDirect
Set-WpfToggleState $btnV2rayTog $global:enableV2rayChain
Set-WpfToggleState $btnOutboundTog $global:enableOutboundProxy
Set-WpfToggleState $btnBootTog $launchOnBoot
$script:debugMode = $false
Set-WpfToggleState $btnDebugTog $script:debugMode

function Update-RoutingToggle {
    $btnProxyMode.Background = $brushInactiveRouting; $btnProxyMode.Foreground = "#A0AEC0"
    $btnClearProxy.Background = $brushInactiveRouting; $btnClearProxy.Foreground = "#A0AEC0"
    if (-not $global:hasVpnComponents) { 
        $btnVpnMode.Background = $brushDisabledVpn; $btnVpnMode.Foreground = "#4A5568"
        $btnVpnMode.Cursor = [System.Windows.Input.Cursors]::No
        $vpnToolTip.Visibility = "Visible"
    } else { 
        $btnVpnMode.Background = $brushInactiveRouting; $btnVpnMode.Foreground = "#A0AEC0"
        $btnVpnMode.Cursor = [System.Windows.Input.Cursors]::Hand
        $vpnToolTip.Visibility = "Collapsed"
    }
    if ($global:lastXrayMode -eq "Proxy Mode") { $btnProxyMode.Background = $brushActiveRouting; $btnProxyMode.Foreground = "#FFFFFF" } elseif ($global:lastXrayMode -eq "VPN Mode" -and $global:hasVpnComponents) { $btnVpnMode.Background = $brushActiveRouting; $btnVpnMode.Foreground = "#FFFFFF" } elseif ($global:lastXrayMode -eq "Clear Proxy") { $btnClearProxy.Background = $brushActiveRouting; $btnClearProxy.Foreground = "#FFFFFF" }

    if ($global:lastXrayMode -eq "VPN Mode" -and $global:hasVpnComponents) {
        $global:enableDirect = $false
        Set-WpfToggleState $btnDirectTog $false
        $btnDirectConfig.IsEnabled = $false; $btnDirectConfig.Opacity = 0.5
        $btnDirectTog.IsEnabled = $false; $btnDirectTog.Opacity = 0.5
    } else {
        $btnDirectConfig.IsEnabled = $true; $btnDirectConfig.Opacity = 1.0
        $btnDirectTog.IsEnabled = $true; $btnDirectTog.Opacity = 1.0
    }
}
Update-RoutingToggle

# --- SAFE RELATIVE BRIDGE DATABASE ---
$bridgeData = @{
    "meek_lite" = @{ "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN") }
    "obfs4" = @{ "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0", "Bridge obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0", "Bridge obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0", "Bridge obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0", "Bridge obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=1", "Bridge obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1", "Bridge obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1") }
    "snowflake" = @{ "plugin" = "ClientTransportPlugin snowflake exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn", "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn") }
}

# --- OLD WINFORMS MODALS ---
function Show-DirectRulesDialog {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = "Split Tunneling Rules"; $dlg.Size = New-Object Drawing.Size(420, 230); $dlg.StartPosition = "CenterParent"; $dlg.BackColor = $colorBgHex; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = "Enter Domains or IPs to bypass Tor (comma separated):"; $lbl.ForeColor = $colorTextHex; $lbl.Location = "15,15"; $lbl.AutoSize = $true
    
    $txt = New-Object Windows.Forms.TextBox; $txt.Location = "15,40"; $txt.Size = "375, 80"; $txt.Multiline = $true; $txt.ScrollBars = "Vertical"; $txt.BackColor = "#2D3748"; $txt.ForeColor = "White"; $txt.Text = $global:lastManualSplit; $txt.BorderStyle = "None"; $txt.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    
    $btnOk = New-Object Windows.Forms.Button; $btnOk.Text = "Save"; $btnOk.Location = "300, 140"; $btnOk.Size = "90,30"; $btnOk.DialogResult = "OK"; $btnOk.BackColor = $colorBtnHex; $btnOk.ForeColor = $colorTextHex; $btnOk.FlatStyle = "Flat"; $btnOk.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnOk 4; $btnOk.TabStop = $false
    $dlg.Controls.AddRange(@($lbl, $txt, $btnOk)); $dlg.AcceptButton = $btnOk
    
    $dlg.Add_Shown({ $dlg.ActiveControl = $lbl }) 
    if ($dlg.ShowDialog() -eq "OK") { $global:lastManualSplit = $txt.Text.Trim(); return $true }
    $dlg.Dispose(); return $false
}
function Show-CustomBridgeDialog {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = "Custom Bridge Configuration"; $dlg.Size = New-Object Drawing.Size(420, 230); $dlg.StartPosition = "CenterParent"; $dlg.BackColor = $colorBgHex; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = "Paste your custom bridge configurations here:"; $lbl.ForeColor = $colorTextHex; $lbl.Location = "15,15"; $lbl.AutoSize = $true
    
    $txt = New-Object Windows.Forms.TextBox; $txt.Location = "15,40"; $txt.Size = "375, 80"; $txt.Multiline = $true; $txt.ScrollBars = "Vertical"; $txt.BackColor = "#2D3748"; $txt.ForeColor = "White"; $txt.Text = $global:customBridgeLine; $txt.BorderStyle = "None"; $txt.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    
    $btnOk = New-Object Windows.Forms.Button; $btnOk.Text = "Save"; $btnOk.Location = "210, 140"; $btnOk.Size = "80,30"; $btnOk.DialogResult = "OK"; $btnOk.BackColor = $colorBtnHex; $btnOk.ForeColor = $colorTextHex; $btnOk.FlatStyle = "Flat"; $btnOk.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnOk 4; $btnOk.TabStop = $false
    $btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = "300, 140"; $btnCancel.Size = "90,30"; $btnCancel.DialogResult = "Cancel"; $btnCancel.BackColor = $colorBtnHex; $btnCancel.ForeColor = $colorTextHex; $btnCancel.FlatStyle = "Flat"; $btnCancel.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnCancel 4; $btnCancel.TabStop = $false
    $dlg.Controls.AddRange(@($lbl, $txt, $btnOk, $btnCancel)); $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel
    
    $dlg.Add_Shown({ $dlg.ActiveControl = $lbl }) 
    if ($dlg.ShowDialog() -eq "OK") { $global:customBridgeLine = $txt.Text.Trim(); return $true }
    $dlg.Dispose(); return $false
}
function Show-V2rayDialog {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = "V2Ray Outbound Chain Configuration"; $dlg.Size = New-Object Drawing.Size(520, 360); $dlg.StartPosition = "CenterParent"; $dlg.BackColor = $colorBgHex; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = "Paste the full v2rayN JSON or raw Xray Outbound below:"; $lbl.ForeColor = $colorTextHex; $lbl.Location = "15,15"; $lbl.AutoSize = $true
    
    $txt = New-Object Windows.Forms.TextBox; $txt.Location = "15,40"; $txt.Size = "475, 210"; $txt.Multiline = $true; $txt.ScrollBars = "Vertical"; $txt.BackColor = "#2D3748"; $txt.ForeColor = "White"; $txt.Text = $global:v2rayChainJson; $txt.BorderStyle = "None"; $txt.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    
    $btnImport = New-Object Windows.Forms.Button; $btnImport.Text = "Import .json File"; $btnImport.Location = "15, 265"; $btnImport.Size="120, 30"; $btnImport.BackColor = $colorBtnHex; $btnImport.ForeColor = $colorTextHex; $btnImport.FlatStyle = "Flat"; $btnImport.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnImport 4; $btnImport.TabStop = $false
    $btnImport.Add_Click({
        $fd = New-Object System.Windows.Forms.OpenFileDialog; $fd.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
        if ($fd.ShowDialog() -eq "OK") { $txt.Text = Get-Content $fd.FileName -Raw }
    })
    $btnOk = New-Object Windows.Forms.Button; $btnOk.Text = "Validate & Save"; $btnOk.Location = "270, 265"; $btnOk.Size="110, 30"; $btnOk.DialogResult = "OK"; $btnOk.BackColor = "#4F7C9B"; $btnOk.ForeColor = "White"; $btnOk.FlatStyle = "Flat"; $btnOk.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnOk 4; $btnOk.TabStop = $false
    $btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = "390, 265"; $btnCancel.Size="100, 30"; $btnCancel.DialogResult = "Cancel"; $btnCancel.BackColor = $colorBtnHex; $btnCancel.ForeColor = $colorTextHex; $btnCancel.FlatStyle = "Flat"; $btnCancel.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnCancel 4; $btnCancel.TabStop = $false
    $dlg.Controls.AddRange(@($lbl, $txt, $btnImport, $btnOk, $btnCancel)); $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel
    
    $dlg.Add_Shown({ $dlg.ActiveControl = $lbl }) 
    if ($dlg.ShowDialog() -eq "OK") {
        if ([string]::IsNullOrWhiteSpace($txt.Text)) { $global:v2rayChainJson = ""; return $true }
        try { 
            $parsed = $txt.Text | ConvertFrom-Json 
            $testNode = if ($null -ne $parsed.outbounds) { $parsed.outbounds[0] } else { $parsed }
            if (-not $testNode.protocol) { throw "Missing Protocol" }
            $global:v2rayChainJson = $txt.Text.Trim(); return $true 
        } catch { [System.Windows.Forms.MessageBox]::Show("Invalid Xray JSON!", "Error", 0, 16); return $false }
    }
    $dlg.Dispose(); return $false
}
function Show-OutboundProxyDialog {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = "Outbound Proxy Configuration"; $dlg.Size = New-Object Drawing.Size(335, 260); $dlg.StartPosition = "CenterParent"; $dlg.BackColor = $colorBgHex; $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false
    
    $tempType = $global:outboundProxyType
    if ([string]::IsNullOrEmpty($tempType)) { $tempType = "SOCKS5" }
    
    $pnlProxyType = New-Object Windows.Forms.Panel; $pnlProxyType.Size = "290,26"; $pnlProxyType.Location = "15,15"
    Set-RoundedCorners $pnlProxyType 4
    
    $lblType = New-Object Windows.Forms.Label; $lblType.Text = "Proxy Type"; $lblType.Location = "0,0"; $lblType.Size = "100,26"; $lblType.BackColor = "#2D3748"; $lblType.ForeColor = $colorTextHex; $lblType.TextAlign = "MiddleCenter"; $lblType.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnHttps = New-Object Windows.Forms.Button; $btnHttps.Text = "HTTPS"; $btnHttps.Location = "100, 0"; $btnHttps.Size = "95, 26"; $btnHttps.FlatStyle = "Flat"; $btnHttps.FlatAppearance.BorderSize = 0; $btnHttps.ForeColor = "White"; $btnHttps.Cursor = "Hand"; $btnHttps.TabStop = $false; $btnHttps.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnSocks = New-Object Windows.Forms.Button; $btnSocks.Text = "SOCKS5"; $btnSocks.Location = "195, 0"; $btnSocks.Size = "95, 26"; $btnSocks.FlatStyle = "Flat"; $btnSocks.FlatAppearance.BorderSize = 0; $btnSocks.ForeColor = "White"; $btnSocks.Cursor = "Hand"; $btnSocks.TabStop = $false; $btnSocks.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $pnlProxyType.Controls.AddRange(@($lblType, $btnHttps, $btnSocks))
    
    function Update-TypeButtons {
        if ($tempType -eq "HTTPS") { $btnHttps.BackColor = "#4E7A5E"; $btnSocks.BackColor = "#1A202C" } else { $btnSocks.BackColor = "#4E7A5E"; $btnHttps.BackColor = "#1A202C" }
    }
    Update-TypeButtons
    $btnHttps.Add_Click({ $tempType = "HTTPS"; Update-TypeButtons })
    $btnSocks.Add_Click({ $tempType = "SOCKS5"; Update-TypeButtons })
    
    $lblAddr = New-Object Windows.Forms.Label; $lblAddr.Text = "Address/IP:"; $lblAddr.ForeColor = $colorTextHex; $lblAddr.Location = "15,60"; $lblAddr.AutoSize = $true
    $txtAddr = New-Object Windows.Forms.TextBox; $txtAddr.Location = "15,80"; $txtAddr.Size = "195, 25"; $txtAddr.BackColor = "#2D3748"; $txtAddr.ForeColor = "White"; $txtAddr.Text = $global:outboundProxyAddress; $txtAddr.BorderStyle = "None"; $txtAddr.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    
    $lblPort = New-Object Windows.Forms.Label; $lblPort.Text = "Port:"; $lblPort.ForeColor = $colorTextHex; $lblPort.Location = "225,60"; $lblPort.AutoSize = $true
    $txtPort = New-Object Windows.Forms.TextBox; $txtPort.Location = "225,80"; $txtPort.Size = "80, 25"; $txtPort.BackColor = "#2D3748"; $txtPort.ForeColor = "White"; $txtPort.Text = $global:outboundProxyPort; $txtPort.BorderStyle = "None"; $txtPort.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    
    $btnAuthLbl = New-Object Windows.Forms.Button; $btnAuthLbl.Location = "15, 125"; $btnAuthLbl.Size = "195, 25"; $btnAuthLbl.Text = "Authentication"; $btnAuthLbl.BackColor = "#2D3748"; $btnAuthLbl.ForeColor = $colorTextHex; $btnAuthLbl.FlatStyle = "Flat"; $btnAuthLbl.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAuthLbl 4; $btnAuthLbl.TabStop = $false
    $btnAuthTog = New-Object Windows.Forms.Button; $btnAuthTog.Location = "220, 125"; $btnAuthTog.Size = "85, 25"; $btnAuthTog.FlatStyle = "Flat"; $btnAuthTog.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnAuthTog 4; $btnAuthTog.ForeColor = $colorTextHex; $btnAuthTog.Cursor = "Hand"; $btnAuthTog.TabStop = $false
    if ($global:enableOutboundAuth) { $btnAuthTog.Text = "Enabled"; $btnAuthTog.BackColor = "#4E7A5E" } else { $btnAuthTog.Text = "Disabled"; $btnAuthTog.BackColor = "#8B4A4A" }
    
    $lblUser = New-Object Windows.Forms.Label; $lblUser.Text = "Username:"; $lblUser.ForeColor = $colorTextHex; $lblUser.Location = "15,165"; $lblUser.AutoSize = $true
    $txtUser = New-Object Windows.Forms.TextBox; $txtUser.Location = "15,185"; $txtUser.Size = "135, 25"; $txtUser.BackColor = "#2D3748"; $txtUser.ForeColor = "White"; $txtUser.Text = $global:outboundProxyUser; $txtUser.BorderStyle = "None"; $txtUser.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    
    $lblPass = New-Object Windows.Forms.Label; $lblPass.Text = "Password:"; $lblPass.ForeColor = $colorTextHex; $lblPass.Location = "170,165"; $lblPass.AutoSize = $true
    $txtPass = New-Object Windows.Forms.TextBox; $txtPass.Location = "170,185"; $txtPass.Size = "135, 25"; $txtPass.BackColor = "#2D3748"; $txtPass.ForeColor = "White"; $txtPass.Text = $global:outboundProxyPass; $txtPass.BorderStyle = "None"; $txtPass.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    
    $btnOk = New-Object Windows.Forms.Button; $btnOk.Text = "Save"; $btnOk.Size = "80,30"; $btnOk.DialogResult = "OK"; $btnOk.BackColor = $colorBtnHex; $btnOk.ForeColor = $colorTextHex; $btnOk.FlatStyle = "Flat"; $btnOk.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnOk 4; $btnOk.TabStop = $false
    $btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = "300, 140"; $btnCancel.Size = "80,30"; $btnCancel.DialogResult = "Cancel"; $btnCancel.BackColor = $colorBtnHex; $btnCancel.ForeColor = $colorTextHex; $btnCancel.FlatStyle = "Flat"; $btnCancel.FlatAppearance.BorderSize = 0; Set-RoundedCorners $btnCancel 4; $btnCancel.TabStop = $false
    
    function Evaluate-AuthView {
        $isAuthOn = ($btnAuthTog.Text -eq "Enabled")
        $lblUser.Visible = $isAuthOn; $txtUser.Visible = $isAuthOn; $lblPass.Visible = $isAuthOn; $txtPass.Visible = $isAuthOn
        if ($isAuthOn) { $dlg.ClientSize = New-Object Drawing.Size(335, 280); $btnOk.Location = "125, 230"; $btnCancel.Location = "225, 230" } else { $dlg.ClientSize = New-Object Drawing.Size(335, 210); $btnOk.Location = "125, 165"; $btnCancel.Location = "225, 165" }
    }
    Evaluate-AuthView
    
    $btnAuthTog.Add_Click({ 
        if ($btnAuthTog.Text -eq "Disabled") { $btnAuthTog.Text = "Enabled"; $btnAuthTog.BackColor = "#4E7A5E" } else { $btnAuthTog.Text = "Disabled"; $btnAuthTog.BackColor = "#8B4A4A" }
        Evaluate-AuthView 
    })
    $btnAuthLbl.Add_Click({ $btnAuthTog.PerformClick() })
    $dlg.Controls.AddRange(@($pnlProxyType, $lblAddr, $txtAddr, $lblPort, $txtPort, $btnAuthLbl, $btnAuthTog, $lblUser, $txtUser, $lblPass, $txtPass, $btnOk, $btnCancel))
    $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel
    
    $dlg.Add_Shown({ $dlg.ActiveControl = $lblAddr }) 
    if ($dlg.ShowDialog() -eq "OK") { 
        $global:outboundProxyAddress = $txtAddr.Text.Trim(); $global:outboundProxyPort = $txtPort.Text.Trim(); $global:outboundProxyType = $tempType
        $global:enableOutboundAuth = ($btnAuthTog.Text -eq "Enabled"); $global:outboundProxyUser = $txtUser.Text.Trim(); $global:outboundProxyPass = $txtPass.Text.Trim(); return $true 
    }
    $dlg.Dispose(); return $false
}

# --- CORE LOGIC ---
function Save-Config {
    $selConfig = if ($comboConfig.SelectedItem.Tag -match "Stable") { "Stable" } else { "Fast" }
    $selCount = [int]($comboCount.SelectedItem.Tag)
    @{ AutoStart = [bool]$autoStart; LaunchOnBoot = [bool]$launchOnBoot; LastConfig = $selConfig; SelectedBridge = $comboBridge.SelectedItem.Tag; InstanceCount = $selCount; XrayMode = $global:lastXrayMode; ManualSplit = $global:lastManualSplit; EnableDirect = $global:enableDirect; CustomBridgeLine = $global:customBridgeLine; EnableV2rayChain = $global:enableV2rayChain; V2rayChainJson = $global:v2rayChainJson; EnableOutboundProxy = $global:enableOutboundProxy; OutboundProxyAddress = $global:outboundProxyAddress; OutboundProxyPort = $global:outboundProxyPort; OutboundProxyType = $global:outboundProxyType; OutboundProxyUser = $global:outboundProxyUser; OutboundProxyPass = $global:outboundProxyPass; EnableOutboundAuth = $global:enableOutboundAuth } | ConvertTo-Json -Depth 10 | Set-Content $cfgFile
}

function Write-XrayConfig {
    $rules = @( @{ type="field"; ip=@("127.0.0.0/8", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"); outboundTag="direct" } )
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
            $v2rayOutbound = if ($null -ne $v2rayParsed.outbounds) { $v2rayParsed.outbounds | Where-Object { $_.protocol -notin @("freedom", "blackhole") } | Select-Object -First 1 } else { $v2rayParsed }
            $v2rayOutbound.tag = "proxy"
            if ($null -ne $v2rayOutbound.streamSettings -and $null -ne $v2rayOutbound.streamSettings.tlsSettings) {
                if (-not $v2rayOutbound.streamSettings.tlsSettings.psobject.properties.match('allowInsecure').Count) { $v2rayOutbound.streamSettings.tlsSettings | Add-Member -MemberType NoteProperty -Name "allowInsecure" -Value $true } else { $v2rayOutbound.streamSettings.tlsSettings.allowInsecure = $true }
            }
            if (-not $v2rayOutbound.psobject.properties.match('proxySettings').Count) { $v2rayOutbound | Add-Member -MemberType NoteProperty -Name "proxySettings" -Value @{ tag="torProxy" } } else { $v2rayOutbound.proxySettings = @{ tag="torProxy" } }
            
            $outbounds += $v2rayOutbound
            $outbounds += @{ tag="torProxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } }
        } catch { $outbounds += @{ tag="proxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } } }
    } else { $outbounds += @{ tag="proxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } } }
    
    $outbounds += @{ tag="direct"; protocol="freedom"; settings=@{} }
    $config = @{ log = @{ logLevel="info"; access="access.log"; error="error.log" }; inbounds = $inboundArr; outbounds = $outbounds; routing = @{ domainStrategy="AsIs"; rules=$rules } }
    $config | ConvertTo-Json -Depth 10 | Set-Content "$xrayDir\config.json"
}

function Write-SingboxConfig {
    $domains = @(); $ips = @()
    if ($global:enableDirect -and $global:lastManualSplit -ne "") {
        $list = $global:lastManualSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($item in $list) { if ($item -match "[a-zA-Z]") { $domains += $item } else { $ips += $item } }
    }

    $sbRules = @(
        @{ action = "sniff" }
        @{ port = @(53); action = "hijack-dns" }
        @{ protocol = "dns"; action = "hijack-dns" }
        @{ process_name = @("tor.exe", "haproxy.exe", "lyrebird.exe", "obfs4proxy.exe", "snowflake-client.exe", "xray.exe", "sing-box.exe"); outbound = "direct" }
        @{ ip_is_private = $true; outbound = "direct" }
    )

    if ($domains.Count -gt 0) { $sbRules += @{ domain_suffix = $domains; outbound = "direct" } }
    if ($ips.Count -gt 0) { 
        $cidrIps = $ips | ForEach-Object { if ($_ -notmatch "/") { "$_/32" } else { $_ } }
        $sbRules += @{ ip_cidr = $cidrIps; outbound = "direct" } 
    }

    $sbConfig = @{
        log = @{ level = "warn" }
        dns = @{ servers = @( @{ tag = "dns_proxy"; server = "1.1.1.1"; type = "tcp"; detour = "proxy" } ); final = "dns_proxy" }
        inbounds = @( @{ type = "tun"; tag = "tun-in"; interface_name = "singbox_tun"; address = @("172.18.0.1/30"); mtu = 9000; auto_route = $true; strict_route = $true; stack = "gvisor" } )
        outbounds = @( @{ type = "socks"; tag = "proxy"; server = "127.0.0.1"; server_port = 10818 }, @{ type = "direct"; tag = "direct" } )
        route = @{ default_domain_resolver = "dns_proxy"; auto_detect_interface = $true; rules = $sbRules; final = "proxy" }
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
    if ($script:debugMode) { $p = Start-Process "cmd.exe" -ArgumentList "/c `"title XrayDebug & .\xray.exe run -c config.json || pause`"" -WorkingDirectory $xrayDir -WindowStyle Normal -PassThru; $global:cmdDebugPid = $p.Id } else { Start-Process -FilePath "$xrayDir\xray.exe" -ArgumentList "run -c config.json" -WorkingDirectory $xrayDir -WindowStyle Hidden }
    if ($targetMode -eq "VPN Mode") {
        Write-SingboxConfig
        if ($script:debugMode) { $p2 = Start-Process "cmd.exe" -ArgumentList "/c `"title SingBoxDebug & .\sing-box.exe run -c config.json || pause`"" -WorkingDirectory $sbDir -WindowStyle Normal -PassThru; $global:cmdDebugPid2 = $p2.Id } else { Start-Process -FilePath "$sbDir\sing-box.exe" -ArgumentList "run -c config.json" -WorkingDirectory $sbDir -WindowStyle Hidden }
    } elseif ($targetMode -eq "Proxy Mode") { Set-SystemProxy $true }
    if ($targetMode -ne "Proxy Mode") { Set-SystemProxy $false }
}

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
        if (-not $hasStats) { $newHaData += ""; $newHaData += "listen stats"; $newHaData += "    bind 127.0.0.1:10888"; $newHaData += "    mode http"; $newHaData += "    stats enable"; $newHaData += "    stats uri /stats" }
        $newHaData | Set-Content $haPathCfg
    }
}

function Reset-ButtonText { 
    $btnActionMainText.Text = "CONNECT"
    $btnActionSubText.Text = "(click to start)"
    if ($global:isConnected) { $btnActionMainText.Foreground = "#68D391"; $btnActionSubText.Foreground = "#68D391" } else { $btnActionMainText.Foreground = "#E2E8F0"; $btnActionSubText.Foreground = "#E2E8F0" }
}

function Stop-AllEngines($isClosing = $false) {
    $global:abortBoot = $true; Set-SystemProxy $false
    $global:isEngineRunning = $false
    
    Get-Process tor, haproxy, xray, sing-box -ErrorAction SilentlyContinue | ForEach-Object { try { $p = $_.Path; if ($null -ne $p -and ($p -eq "$xrayDir\xray.exe" -or $p -eq "$haPath\haproxy.exe" -or $p -eq "$global:baseDir\Data\sing_box\sing-box.exe" -or $p -match "Data\\Tors\\Tor")) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } } catch {} }
    if ($null -ne $global:cmdDebugPid) { Stop-Process -Id $global:cmdDebugPid -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid = $null }
    if ($null -ne $global:cmdDebugPid2) { Stop-Process -Id $global:cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid2 = $null }
    $global:isConnected = $false; $global:lastTotalBytes = 0; $global:sessionDataBytes = 0
    
    if (-not $isClosing) {
        Reset-ButtonText
        $btnAction.IsEnabled = $true
        $lblSocksTitle.Text = "Mixed Port:"
        $lblSocksDataIPs.Text = "Waiting for connection..."
        $lblSocksDataTags.Text = ""
        $lblStatsData.Text = "Speed: 0 KB/s`nTotal: 0 MB"
    }
}

function Start-Engines {
    try {
        if (Get-Process tor -ErrorAction SilentlyContinue) { $btnActionSubText.Text = "Clearing old engines..."; DoEvents; Stop-AllEngines; Start-Sleep -Seconds 1 }
        $global:abortBoot = $false; $selBridge = $comboBridge.SelectedItem.Tag
        $selConfig = if ($comboConfig.SelectedItem.Tag -match "Stable") { "Stable" } else { "Fast" }; $selCount = [int]($comboCount.SelectedItem.Tag)
        $mode = $global:lastXrayMode; $cfgFileTarget = if ($selConfig -eq "Stable") { "torrc" } else { "torrc2" }

        # Pre-clean logs so the UI displays correctly during boot
        for ($i=1; $i -le 8; $i++) {
            Remove-Item "$global:baseDir\Data\Tors\Tor$i\tor.log" -ErrorAction SilentlyContinue
            $lbl = $form.FindName("lblTor$i")
            if ($null -ne $lbl -and $i -le $selCount) { $lbl.Text = "Tor 0$($i): Waiting..."; $lbl.Foreground = "#A0AEC0" }
            elseif ($null -ne $lbl) { $lbl.Text = "Tor 0$($i): Disabled"; $lbl.Foreground = "#4A5568" }
        }
        Remove-Item "$xrayDir\access.log" -ErrorAction SilentlyContinue
        Remove-Item "$xrayDir\access.log.tmp" -ErrorAction SilentlyContinue
        if ($null -ne $txtXrayLogs) { $txtXrayLogs.Text = "" }

        $global:isEngineRunning = $true
        Save-Config
        $winStyle = if ($script:debugMode) { "Normal" } else { "Hidden" }
        
        $btnActionMainText.Text = "CONNECTING..."
        $btnActionMainText.Foreground = "#F6AD55"; $btnActionSubText.Foreground = "#F6AD55"
        Format-HAProxyConfig $selCount; $dynamicWait = 16 - $selCount
        
        for ($i=1; $i -le $selCount; $i++) {
            if ($global:abortBoot) { break } 
            $btnActionSubText.Text = "Booting Tor $i of $selCount... (click to abort)"
            DoEvents
            
            $path = "$global:baseDir\Data\Tors\Tor$i"
            if (Test-Path "$path\$cfgFileTarget") {
                $c = @(Get-Content "$path\$cfgFileTarget"); $cleanConfig = @()
                foreach ($line in $c) {
                    if ($line -match "^# --- MANAGED BRIDGES ---") { break }
                    if ($line -notmatch "^UseBridges" -and $line -notmatch "^ClientTransportPlugin" -and $line -notmatch "^Bridge" -and $line -notmatch "^HTTPSProxy" -and $line -notmatch "^Socks5Proxy" -and $line -notmatch "^Socks5ProxyUsername" -and $line -notmatch "^Socks5ProxyPassword" -and $line -notmatch "^HTTPSProxyAuthenticator" -and $line -notmatch "^Log notice file") {
                        if ($line.Trim() -ne "") { $cleanConfig += $line.Trim() }
                    }
                }
                $cleanConfig += ""; $cleanConfig += "# --- MANAGED BRIDGES ---"
                $cleanConfig += "Log notice file tor.log"
                
                if ($global:enableOutboundProxy -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyAddress) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPort)) {
                    if ($global:outboundProxyType -eq "SOCKS5") {
                        $cleanConfig += "Socks5Proxy $($global:outboundProxyAddress):$($global:outboundProxyPort)"
                        if ($global:enableOutboundAuth -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyUser) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPass)) { $cleanConfig += "Socks5ProxyUsername $($global:outboundProxyUser)"; $cleanConfig += "Socks5ProxyPassword $($global:outboundProxyPass)" }
                    } elseif ($global:outboundProxyType -eq "HTTPS") {
                        $cleanConfig += "HTTPSProxy $($global:outboundProxyAddress):$global:outboundProxyPort"
                        if ($global:enableOutboundAuth -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyUser) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPass)) { $cleanConfig += "HTTPSProxyAuthenticator $($global:outboundProxyUser):$($global:outboundProxyPass)" }
                    }
                }

                if ($selBridge -eq "Custom" -and $global:customBridgeLine -ne "") { 
                    $cleanConfig += "UseBridges 1"; $cleanConfig += "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel,snowflake exec ..\..\PluggableTransports\lyrebird.exe"
                    $customLines = $global:customBridgeLine.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch "^ClientTransportPlugin" }
                    foreach ($cl in $customLines) { if ($cl -notmatch "^Bridge\s") { $cleanConfig += "Bridge $cl" } else { $cleanConfig += $cl } }
                } 
                elseif ($selBridge -ne "Direct (None)") { 
                    $b = $bridgeData[$selBridge]; $cleanConfig += "UseBridges 1"; $cleanConfig += $b.plugin
                    foreach ($line in $b.lines) { $cleanConfig += $line }
                } else { $cleanConfig += "UseBridges 0" }
                
                $cleanConfig | Set-Content "$path\$cfgFileTarget"
                Start-Process -FilePath "$path\tor.exe" -ArgumentList "-f $cfgFileTarget" -WorkingDirectory $path -WindowStyle $winStyle
                Wait-NonBlocking $dynamicWait
            }
        }
        
        if (-not $global:abortBoot) {
            $btnActionSubText.Text = "Booting Core Engines... (click to abort)"; DoEvents
            
            Remove-Item "$xrayDir\access.log" -ErrorAction SilentlyContinue
            Remove-Item "$xrayDir\error.log" -ErrorAction SilentlyContinue

            if (Test-Path "$haPath\haproxy.exe") { Start-Process -FilePath "$haPath\haproxy.exe" -ArgumentList "-f haproxy.cfg" -WorkingDirectory $haPath -WindowStyle $winStyle }
            Restart-Xray $mode
            
            $lblSocksTitle.Text = "Mixed Port:"
            $lblSocksDataIPs.Text = "127.0.0.1:10818`n$lanIp`:10818"
            $lblSocksDataTags.Text = "(Local)`n(LAN)"

            $global:isConnected = $true
            $btnActionMainText.Text = "CONNECTED"
            $btnActionSubText.Text = "(click to disconnect)"
            $btnActionMainText.Foreground = "#68D391"
            $btnActionSubText.Foreground = "#68D391"
        } else { Reset-ButtonText }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("A startup error occurred:`n" + $_.Exception.Message, "Error", 0, 16)
        Reset-ButtonText
    }
}

function Update-Application {
    $btnUpdate.Content = "Checking..."
    DoEvents
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $remoteCode = Invoke-RestMethod -Uri $repoRawUrl -UseBasicParsing
        
        if ($remoteCode -match '\$global:currentVersion\s*=\s*"([^"]+)"') {
            $remoteVer = $matches[1]
            if ([version]$remoteVer -gt [version]$global:currentVersion) {
                
                $isManualRequired = $remoteCode -match '\$global:forceManualUpdate\s*=\s*\$true'
                if ($isManualRequired) {
                    [System.Windows.Forms.MessageBox]::Show("A major update ($remoteVer) is available!`n`nThis version contains critical component changes and MUST be downloaded manually from GitHub.`n`nClick OK to open the release page.", "Manual Update Required", 0, 64)
                    Start-Process "https://github.com/RichTiTAN/Tor-Multiplexer"
                    $btnUpdate.Content = "Check for Updates"
                    $btnUpdate.Background = $brushBtnBg
                    return
                }

                $msg = [System.Windows.Forms.MessageBox]::Show("Version $remoteVer is available! Would you like to update now?", "Update Available", 4, 64)
                if ($msg -eq "Yes") {
                    $btnUpdate.Content = "Updating..."
                    DoEvents
                    Invoke-WebRequest -Uri $repoRawUrl -OutFile $global:scriptPath
                    Start-Process powershell.exe -ArgumentList "-STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$global:scriptPath`""
                    [Environment]::Exit(0)
                }
            } else { [System.Windows.Forms.MessageBox]::Show("You are already on the latest version!`n(Local: $global:currentVersion, Remote: $remoteVer)", "Up to Date", 0, 64) }
        }
    } catch { [System.Windows.Forms.MessageBox]::Show("Update check failed: $_", "Error", 0, 16) }
    $btnUpdate.Content = "Check for Updates"
    $btnUpdate.Background = $brushBtnBg
}

function Check-UpdateSilent {
    $updateWebClient = New-Object System.Net.WebClient
    $updateWebClient.Add_DownloadStringCompleted({
        param($sender, $e)
        if (-not $e.Cancelled -and $e.Error -eq $null) {
            try {
                $remoteCode = $e.Result
                if ($remoteCode -match '\$global:currentVersion\s*=\s*"([^"]+)"') {
                    $remoteVer = $matches[1]
                    if ([version]$remoteVer -gt [version]$global:currentVersion) {
                        $form.Dispatcher.Invoke([System.Action]{ 
                            $btnUpdate.Content = "NEW UPDATE AVAILABLE"
                            $btnUpdate.Background = $brushActiveRouting 
                        })
                    }
                }
            } catch {}
        }
        $sender.Dispose()
    })
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { $updateWebClient.DownloadStringAsync([uri]$repoRawUrl) } catch {}
}

function Update-BootShortcut {
    $taskName = "TorMultiplexer_AutoStart"
    if ($script:launchOnBoot) {
        try { 
            $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$global:baseDir\Launch Multiplexer.vbs`"" -WorkingDirectory $global:baseDir
            $trigger = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        } catch { 
            [System.Windows.Forms.MessageBox]::Show("Failed to create Auto-Start task.`n$($_.Exception.Message)", "Error", 0, 16)
            $script:launchOnBoot = $false; Set-WpfToggleState $btnBootTog $false
        }
    } else { try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {} }
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $oldShortcut = Join-Path $startupFolder "TorMultiplexer.lnk"
    if (Test-Path $oldShortcut) { Remove-Item $oldShortcut -Force -ErrorAction SilentlyContinue }
}

# --- SMOOTH STATS ENGINE ---
$global:statsWebClient = New-Object System.Net.WebClient
$global:isFetchingStats = $false

$global:statsWebClient.Add_DownloadStringCompleted({
    param($sender, $e)
    if (-not $e.Cancelled -and $e.Error -eq $null) {
        try {
            $res = $e.Result
            $rows = $res -split "`n"
            $torServers = $rows | Where-Object { $_ -match ",tor\d+," }
            $currentBytes = 0
            foreach ($server in $torServers) { 
                $cols = $server -split ","
                if ($cols.Count -ge 10) { $currentBytes += [long]$cols[8] + [long]$cols[9] } 
            }
            if ($global:lastTotalBytes -gt 0) {
                $diff = [Math]::Max(0, ($currentBytes - $global:lastTotalBytes))
                $global:sessionDataBytes += $diff
                $global:speedSamples = @($diff) + $global:speedSamples[0..3]
                $avgDiff = ($global:speedSamples | Measure-Object -Average).Average
                $speedStr = if ($avgDiff -ge 1048576) { "$([Math]::Round($avgDiff/1048576, 2)) MB/s" } elseif ($avgDiff -ge 1024) { "$([Math]::Round($avgDiff/1024, 1)) KB/s" } else { "$([int]$avgDiff) B/s" }
                $totStr = if ($global:sessionDataBytes -ge 1073741824) { "$([Math]::Round($global:sessionDataBytes/1073741824, 2)) GB" } elseif ($global:sessionDataBytes -ge 1048576) { "$([Math]::Round($global:sessionDataBytes/1048576, 1)) MB" } else { "$([Math]::Round($global:sessionDataBytes/1024, 1)) KB" }
                $form.Dispatcher.Invoke([System.Action]{ $lblStatsData.Text = "Speed: $speedStr`nTotal: $totStr" })
            }
            if ($currentBytes -gt 0) { $global:lastTotalBytes = $currentBytes }
        } catch {}
    }
    $global:isFetchingStats = $false
})

$statsTimer = New-Object System.Windows.Threading.DispatcherTimer
$statsTimer.Interval = [TimeSpan]::FromSeconds(1)
$statsTimer.add_Tick({
    if ($global:isConnected -and -not $global:isFetchingStats) {
        $global:isFetchingStats = $true
        try { $global:statsWebClient.DownloadStringAsync([uri]"http://127.0.0.1:10888/stats;csv") } catch { $global:isFetchingStats = $false }
    }
})
$statsTimer.Start()

# --- WINDOW SIZING & ANIMATION STATE MACHINE ---
function Update-WindowSize {
    $targetW = if ($script:isLogsOpen) { 905.0 } else { 605.0 }
    $targetH = if ($script:isAdvancedOpen) { 480.0 } else { 295.0 }
    
    $advOpac = if ($script:isAdvancedOpen) { 1.0 } else { 0.0 }
    $logOpac = if ($script:isLogsOpen) { 1.0 } else { 0.0 }
    $panelTop = if ($script:isAdvancedOpen) { 365.0 } else { 180.0 }
    $logsH = if ($script:isAdvancedOpen) { 410.0 } else { 225.0 }
    $xrayH = if ($script:isAdvancedOpen) { 260.0 } else { 75.0 }

    if ($script:isAdvancedOpen) { $AdvancedCanvas.Visibility = "Visible" }
    if ($script:isLogsOpen) { 
        $LogsCanvas.Visibility = "Visible"
        $logTimer.Start() 
    } else {
        $logTimer.Stop()
    }

    $wAnim = New-Object System.Windows.Media.Animation.DoubleAnimation($targetW, (New-Object TimeSpan 0,0,0,0,300))
    $hAnim = New-Object System.Windows.Media.Animation.DoubleAnimation($targetH, (New-Object TimeSpan 0,0,0,0,300))
    $form.BeginAnimation([System.Windows.Window]::WidthProperty, $wAnim)
    $form.BeginAnimation([System.Windows.Window]::HeightProperty, $hAnim)

    $advFade = New-Object System.Windows.Media.Animation.DoubleAnimation($advOpac, (New-Object TimeSpan 0,0,0,0,300))
    $logFade = New-Object System.Windows.Media.Animation.DoubleAnimation($logOpac, (New-Object TimeSpan 0,0,0,0,300))
    $AdvancedCanvas.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $advFade)
    $LogsCanvas.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $logFade)

    $slideAnim = New-Object System.Windows.Media.Animation.DoubleAnimation($panelTop, (New-Object TimeSpan 0,0,0,0,300))
    $SocksPanel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $slideAnim)
    $StatsPanel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $slideAnim)

    $logsHeightAnim = New-Object System.Windows.Media.Animation.DoubleAnimation($logsH, (New-Object TimeSpan 0,0,0,0,300))
    $logBorder.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, $logsHeightAnim)
    $LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, $logsHeightAnim)

    $xrayHeightAnim = New-Object System.Windows.Media.Animation.DoubleAnimation($xrayH, (New-Object TimeSpan 0,0,0,0,300))
    $txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, $xrayHeightAnim)

    if (-not $script:isAdvancedOpen) {
        $script:hideAdvTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:hideAdvTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $script:hideAdvTimer.add_Tick({ $script:hideAdvTimer.Stop(); $AdvancedCanvas.Visibility = "Hidden" })
        $script:hideAdvTimer.Start()
    }
    if (-not $script:isLogsOpen) {
        $script:hideLogTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:hideLogTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $script:hideLogTimer.add_Tick({ $script:hideLogTimer.Stop(); $LogsCanvas.Visibility = "Hidden" })
        $script:hideLogTimer.Start()
    }
}

# --- LIVE LOGS PARSER ENGINE ---
$script:isLogsOpen = $false
$logTimer = New-Object System.Windows.Threading.DispatcherTimer
$logTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
$logTimer.add_Tick({
    try {
        if (-not $script:isLogsOpen) { return }
        if ($null -eq $comboCount.SelectedItem) { return }
        
        if (-not $global:isEngineRunning) {
            for ($i=1; $i -le 8; $i++) {
                $lbl = $form.FindName("lblTor$i")
                if ($null -ne $lbl) { $lbl.Text = "Tor 0$($i): Offline"; $lbl.Foreground = "#4A5568" }
            }
            if ($null -ne $txtXrayLogs) { $txtXrayLogs.Text = "" }
            return
        }

        $selCount = [int]($comboCount.SelectedItem.Tag)
        
        # 1. Parse Tor Bootstrap Logs safely
        for ($i=1; $i -le 8; $i++) {
            $lbl = $form.FindName("lblTor$i")
            if ($null -eq $lbl) { continue }
            if ($i -gt $selCount) { $lbl.Text = "Tor 0$($i): Disabled"; $lbl.Foreground = "#4A5568"; continue }
            
            $logPath = "$global:baseDir\Data\Tors\Tor$i\tor.log"
            if (Test-Path $logPath) {
                try {
                    $fs = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $sr = New-Object System.IO.StreamReader($fs)
                    $content = $sr.ReadToEnd()
                    $sr.Close(); $fs.Close()
                    
                    $matches = [regex]::Matches($content, 'Bootstrapped (\d+)%')
                    if ($matches.Count -gt 0) {
                        $pct = $matches[$matches.Count - 1].Groups[1].Value
                        $lbl.Text = "Tor 0$($i): $pct%"
                        if ($pct -eq "100") { $lbl.Foreground = "#68D391" } else { $lbl.Foreground = "#F6AD55" }
                    } else { $lbl.Text = "Tor 0$($i): Booting..."; $lbl.Foreground = "#A0AEC0" }
                } catch {}
            } else { $lbl.Text = "Tor 0$($i): Waiting..."; $lbl.Foreground = "#A0AEC0" }
        }
        
        # 2. Parse Xray Connection Logs safely
        $xrayLogPath = "$xrayDir\access.log"
        if (Test-Path $xrayLogPath) {
            try {
                $fs = New-Object System.IO.FileStream($xrayLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr = New-Object System.IO.StreamReader($fs)
                $content = $sr.ReadToEnd()
                $sr.Close(); $fs.Close()
                
                $lines = $content -split "`r?`n" | Where-Object { $_ -match "accepted" -or $_ -match "proxy" }
                $tail = $lines | Select-Object -Last 15
                $cleaned = $tail | ForEach-Object { $_ -replace "^.*?\s\d{2}:\d{2}:\d{2}\s+(127\.0\.0\.1:\d+\s+)?", "" }
                if ($null -ne $txtXrayLogs) {
                    $txtXrayLogs.Text = $cleaned -join "`n"
                    $txtXrayLogs.ScrollToEnd()
                }
            } catch {}
        }
    } catch {}
})

# --- EVENT BINDINGS ---
$comboBridge.add_SelectionChanged({
    if ($comboBridge.SelectedItem.Tag -eq "Custom") { if (-not (Show-CustomBridgeDialog)) { Set-ComboSelectedTag $comboBridge $global:previousBridge } else { $global:previousBridge = "Custom" } } else { $global:previousBridge = $comboBridge.SelectedItem.Tag }
    Save-Config
})
$comboConfig.add_SelectionChanged({ Save-Config })
$comboCount.add_SelectionChanged({ Save-Config })

$btnAction.add_Click({ if ($global:isConnected -or $btnActionMainText.Text -eq "CONNECTING...") { Stop-AllEngines } else { Start-Engines } })
$btnUpdate.add_Click({ Update-Application })

$btnDesktop.add_Click({
    $deskFolder = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $deskFolder "TorMultiplexer.lnk"
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = Join-Path $global:baseDir "Launch Multiplexer.vbs"
        $Shortcut.WorkingDirectory = $global:baseDir
        $Shortcut.Save()
        [System.Windows.Forms.MessageBox]::Show("Desktop shortcut created successfully!", "Success", 0, 64)
    } catch { [System.Windows.Forms.MessageBox]::Show("Failed to create Desktop shortcut.`n" + $_.Exception.Message, "Error", 0, 16) }
})

$btnGithub.add_Click({ Start-Process "https://github.com/RichTiTAN/Tor-Multiplexer" })
$btnTelegram.add_Click({ Start-Process "https://t.me/itsTitanVPN" })

$btnAutoStartTog.add_Click({ $script:autoStart = -not $script:autoStart; Set-WpfToggleState $btnAutoStartTog $script:autoStart; Save-Config })
$btnAutoStartLbl.add_Click({ $btnAutoStartTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

$btnDirectTog.add_Click({ $global:enableDirect = -not $global:enableDirect; Set-WpfToggleState $btnDirectTog $global:enableDirect; Save-Config; if ($global:isConnected) { Restart-Xray $global:lastXrayMode } })
$btnDirectConfig.add_Click({ Show-DirectRulesDialog | Out-Null })

$btnV2rayTog.add_Click({
    $newState = -not $global:enableV2rayChain
    if ($newState -and [string]::IsNullOrWhiteSpace($global:v2rayChainJson)) { if (-not (Show-V2rayDialog)) { $newState = $false } }
    $global:enableV2rayChain = $newState; Set-WpfToggleState $btnV2rayTog $global:enableV2rayChain; Save-Config; if ($global:isConnected) { Restart-Xray $global:lastXrayMode }
})
$btnV2rayConfig.add_Click({ Show-V2rayDialog | Out-Null })

$btnOutboundTog.add_Click({
    if ($global:isConnected) {
        [System.Windows.Forms.MessageBox]::Show("You cannot enable or disable the Outbound Proxy while connected. Please disconnect first.", "Action Denied", 0, 48)
        return
    }
    $global:enableOutboundProxy = -not $global:enableOutboundProxy
    Set-WpfToggleState $btnOutboundTog $global:enableOutboundProxy; Save-Config
})
$btnOutboundConfig.add_Click({ Show-OutboundProxyDialog | Out-Null })

$btnBootTog.add_Click({ $script:launchOnBoot = -not $script:launchOnBoot; Set-WpfToggleState $btnBootTog $script:launchOnBoot; Update-BootShortcut; Save-Config })
$btnBootLbl.add_Click({ $btnBootTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

$btnDebugTog.add_Click({ $script:debugMode = -not $script:debugMode; Set-WpfToggleState $btnDebugTog $script:debugMode })
$btnDebugLbl.add_Click({ $btnDebugTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

$script:isAdvancedOpen = $false
$btnAdvTog.add_Click({
    $script:isAdvancedOpen = -not $script:isAdvancedOpen
    $btnAdvTog.Content = if ($script:isAdvancedOpen) { "Hide" } else { "Show" }
    Update-WindowSize
})
$btnAdvLbl.add_Click({ $btnAdvTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

$btnLogsTog.add_Click({
    $script:isLogsOpen = -not $script:isLogsOpen
    $btnLogsTog.Content = if ($script:isLogsOpen) { "Hide" } else { "Show" }
    Update-WindowSize
})
$btnLogsLbl.add_Click({ $btnLogsTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

$toggleAction = {
    param($mode); if ($global:lastXrayMode -ne $mode) {
        $global:lastXrayMode = $mode; Update-RoutingToggle
        Save-Config
        if ($global:isConnected) { Restart-Xray $mode }
    }
}
$btnProxyMode.add_Click({ &$toggleAction "Proxy Mode" })
$btnClearProxy.add_Click({ &$toggleAction "Clear Proxy" })
$btnVpnMode.add_Click({ if ($global:hasVpnComponents) { &$toggleAction "VPN Mode" } })

$form.add_Closing({ Stop-AllEngines $true })
$form.add_Closed({ [Environment]::Exit(0) })

# Safe Auto-Boot Timer & Missing Components Dialog
$form.add_ContentRendered({ 
    if ($global:appInitialized) { return }
    $global:appInitialized = $true
    Check-UpdateSilent 

    if (-not $global:hasVpnComponents -and $isFirstLaunch) {
        $dlg = New-Object Windows.Forms.Form
        $dlg.Text = "Missing Components"
        $dlg.Size = New-Object Drawing.Size(420, 210)
        $dlg.StartPosition = "CenterParent"
        $dlg.BackColor = $colorBgHex
        $dlg.FormBorderStyle = "FixedDialog"
        $dlg.MaximizeBox = $false

        $lbl = New-Object Windows.Forms.Label
        $lbl.Text = "You have successfully updated to the latest version!`n`nHowever, your installation is missing a newly added core component (Sing-box). Because of this major upgrade, you must download the full package from GitHub to use VPN Mode."
        $lbl.ForeColor = $colorTextHex
        $lbl.Location = "15,15"
        $lbl.Size = "375, 80"
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        
        $btnGit = New-Object Windows.Forms.Button
        $btnGit.Text = "Open GitHub"
        $btnGit.Location = "15, 115"
        $btnGit.Size = "130, 30"
        $btnGit.BackColor = $colorBtnHex
        $btnGit.Foreground = $colorTextHex
        $btnGit.FlatStyle = "Flat"
        $btnGit.FlatAppearance.BorderSize = 0
        $btnGit.TabStop = $false
        Set-RoundedCorners $btnGit 4
        $btnGit.Add_Click({ Start-Process "https://github.com/RichTiTAN/Tor-Multiplexer"; $dlg.Close() })

        $btnClose = New-Object Windows.Forms.Button
        $btnClose.Text = "Continue without VPN"
        $btnClose.Location = "220, 115"
        $btnClose.Size = "170, 30"
        $btnClose.BackColor = $colorBtnHex
        $btnClose.Foreground = $colorTextHex
        $btnClose.FlatStyle = "Flat"
        $btnClose.FlatAppearance.BorderSize = 0
        $btnClose.TabStop = $false
        Set-RoundedCorners $btnClose 4
        $btnClose.Add_Click({ $dlg.Close() })

        $dlg.Controls.AddRange(@($lbl, $btnGit, $btnClose))
        $dlg.Add_Shown({ $dlg.ActiveControl = $lbl })
        $dlg.ShowDialog() | Out-Null
        $dlg.Dispose()
    }

    if ($autoStart -and -not $isFirstLaunch) { 
        $bootTimer = New-Object System.Windows.Threading.DispatcherTimer
        $bootTimer.Interval = [TimeSpan]::FromSeconds(1)
        $bootTimer.add_Tick({
            $bootTimer.Stop()
            if ($global:autoBootFired) { return }
            $global:autoBootFired = $true
            if (-not $global:abortBoot) { Start-Engines }
        })
        $bootTimer.Start()
    }
})

$form.ShowDialog() | Out-Null