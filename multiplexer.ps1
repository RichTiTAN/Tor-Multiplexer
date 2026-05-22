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
$global:currentVersion = "5.0.0" 
$repoRawUrl = "https://raw.githubusercontent.com/RichTiTAN/Tor-Multiplexer/main/multiplexer.ps1"
$global:forceManualUpdate = $true
$global:abortBoot = $false
$global:isConnected = $false
$global:isEngineRunning = $false
$global:cmdDebugPid = $null 
$global:cmdDebugPid2 = $null 
$global:xrayDohPid = $null
$global:lastTotalBytes = 0
$global:sessionDataBytes = 0
$global:appInitialized = $false

# Stats Smoothing Buffer
$global:speedSamples = @(0,0,0,0,0)

# Minimize to Tray Global Default
$global:minimizeToTray = $false

# Ad Blocker Global Default
$global:enableAdBlock = $false

# Split Tunneling Application & Blocklist Defaults
$global:lastAppSplit = ""
$global:lastBlockSplit = ""

# --- CONFIGURATION & PATHS ---
$cfgFile = "$global:baseDir\multiplexer_settings.json"
$xrayDir = "$global:baseDir\Data\Xray"
$haPath  = "$global:baseDir\Data\HAproxy"
$sbDir   = "$global:baseDir\Data\sing_box"

$autoStart = $true; $launchOnBoot = $false; $lastConfig = "Stable"; $lastBridge = "meek_lite"; $lastCount = "6"; $global:lastXrayMode = "Proxy Mode"; $global:lastManualSplit = ""; $global:enableDirect = $false; $global:customBridgeLine = ""; $global:v2rayChainJson = ""; $global:enableV2rayChain = $false
$global:outboundProxyAddress = ""; $global:outboundProxyPort = ""; $global:outboundProxyType = "SOCKS5"; $global:enableOutboundProxy = $false
$global:outboundProxyUser = ""; $global:outboundProxyPort = ""; $global:outboundProxyType = "SOCKS5"; $global:enableOutboundProxy = $false
$global:outboundProxyUser = ""; $global:outboundProxyPass = ""; $global:enableOutboundAuth = $false
$global:enableTorDoh = $false; $global:torDohUrl = "https://cloudflare-dns.com/dns-query"
$global:enableUpstreamDoh = $false; $global:upstreamDohUrl = "https://cloudflare-dns.com/dns-query"
$global:customExitCountry = "us"
$isFirstLaunch = $true 

if (Test-Path $cfgFile) {
    $isFirstLaunch = $false
    try {
        $s = Get-Content $cfgFile -Raw | ConvertFrom-Json
        if ($null -ne $s.AutoStart) { $autoStart = [bool]$s.AutoStart }
        if ($null -ne $s.LaunchOnBoot) { $launchOnBoot = [bool]$s.LaunchOnBoot }
        if ($null -ne $s.LastConfig) { $lastConfig = if ($s.LastConfig -match "Fast") { "Fast" } elseif ($s.LastConfig -match "Custom") { "Custom" } else { "Stable" } }
        if ($null -ne $s.SelectedBridge) { $lastBridge = [string]$s.SelectedBridge }
        if ($null -ne $s.InstanceCount) { 
            $c = [int]$s.InstanceCount
            $lastCount = [string]$c
        }
        if ($null -ne $s.ManualSplit) { $global:lastManualSplit = [string]$s.ManualSplit }
        if ($null -ne $s.AppSplit) { $global:lastAppSplit = [string]$s.AppSplit }
        if ($null -ne $s.BlockSplit) { $global:lastBlockSplit = [string]$s.BlockSplit }
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
        if ($null -ne $s.EnableTorDoh) { $global:enableTorDoh = [bool]$s.EnableTorDoh }
        if ($null -ne $s.TorDohUrl) { $global:torDohUrl = [string]$s.TorDohUrl }
        if ($null -ne $s.EnableUpstreamDoh) { $global:enableUpstreamDoh = [bool]$s.EnableUpstreamDoh }
        if ($null -ne $s.UpstreamDohUrl) { $global:upstreamDohUrl = [string]$s.UpstreamDohUrl }
        if ($null -ne $s.CustomExitCountry) { $global:customExitCountry = [string]$s.CustomExitCountry }
        if ($null -ne $s.MinimizeToTray) { $global:minimizeToTray = [bool]$s.MinimizeToTray }
        if ($null -ne $s.EnableAdBlock) { $global:enableAdBlock = [bool]$s.EnableAdBlock }
        if ($null -ne $s.XrayMode) {
            if ($s.XrayMode -eq "Clear Proxy" -or $s.XrayMode -eq "None") { $global:lastXrayMode = "Clear Proxy" }
            elseif ($s.XrayMode -eq "VPN Mode") { $global:lastXrayMode = "VPN Mode" }
            else { $global:lastXrayMode = "Proxy Mode" }
        }
    } catch {}
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
$xaml = @"
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

        <Button Name="btnProxyMode" Canvas.Left="270" Canvas.Top="65" Width="98" Height="30" Content="Proxy Mode" Style="{StaticResource DarkButton}" Background="#4F7C9B" FontSize="11">
            <Button.ToolTip><ToolTip Content="Enable a system-wide proxy that will route your apps through proxy." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
        </Button>
        
        <Button Name="btnVpnMode" Canvas.Left="371" Canvas.Top="65" Width="98" Height="30" Content="VPN Mode" Style="{StaticResource DarkButton}" FontSize="11">
            <Button.ToolTip>
                <ToolTip Name="vpnToolTip" Content="Route your entire system's network globally through the secure tunnel." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/>
            </Button.ToolTip>
        </Button>
        
        <Button Name="btnClearProxy" Canvas.Left="472" Canvas.Top="65" Width="98" Height="30" Content="Clear Proxy" Style="{StaticResource DarkButton}" FontSize="11">
            <Button.ToolTip><ToolTip Content="Restore your normal Internet connection while having a proxy open on port 10818." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
        </Button>

        <Grid Canvas.Left="270" Canvas.Top="100" Width="300" Height="55">
            <Grid.Clip>
                <RectangleGeometry Rect="0,0,300,55" RadiusX="4" RadiusY="4"/>
            </Grid.Clip>
            <Border Background="#2D3748" CornerRadius="4" Width="300" Height="55"/>
            <Canvas Width="300" Height="55" Background="Transparent" IsHitTestVisible="False">
                <Path Name="wavePath1" Data="M 0,26 C 75,-4 75,56 150,26 C 225,-4 225,56 300,26 C 375,-4 375,56 450,26 C 525,-4 525,56 600,26 L 600,80 L 0,80 Z" Fill="#25718096" Height="80" Width="600" Canvas.Top="0">
                    <Path.RenderTransform>
                        <TranslateTransform x:Name="waveTrans1" X="0" Y="0"/>
                    </Path.RenderTransform>
                </Path>
                <Path Name="wavePath2" Data="M 0,28 C 60,-2 90,58 150,28 C 210,-2 240,58 300,28 C 360,-2 390,58 450,28 C 510,-2 540,58 600,28 L 600,80 L 0,80 Z" Fill="#15718096" Height="80" Width="600" Canvas.Top="0">
                    <Path.RenderTransform>
                        <TranslateTransform x:Name="waveTrans2" X="-75" Y="0"/>
                    </Path.RenderTransform>
                </Path>
            </Canvas>
            <Button Name="btnAction" Width="300" Height="55" Style="{StaticResource ActionButton}" Background="Transparent">
                <Grid Width="300" Height="55">
                    <Grid.Effect>
                        <DropShadowEffect Color="#000000" BlurRadius="15" ShadowDepth="1.0" Direction="270" Opacity="0.65"/>
                    </Grid.Effect>
                    <Grid.LayoutTransform>
                        <TranslateTransform X="0" Y="0"/>
                    </Grid.LayoutTransform>
                    <TextBlock Name="btnActionMainText" Text="CONNECT" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-5,0,0"/>
                    <TextBlock Name="btnActionSubText" FontSize="10" FontFamily="Consolas" FontWeight="Bold" Foreground="#718096" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,3"/>
                </Grid>
            </Button>
        </Grid>

        <Border Name="UnifiedPanel" Canvas.Left="20" Canvas.Top="180" Width="550" Height="65" Background="#1A202C" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4">
            <Canvas>
                <TextBlock Name="lblSocksTitle" Text="Mixed Port:" Canvas.Left="10" Canvas.Top="8" FontSize="11" Foreground="#A0AEC0"/>
                <TextBlock Name="lblSocksDataIPs" Text="Waiting for connection..." Canvas.Left="10" Canvas.Top="26" FontSize="11" Foreground="#E2E8F0"/>
                <TextBlock Name="lblSocksDataTags" Text="" Canvas.Left="200" Canvas.Top="26" FontSize="11" Foreground="#A0AEC0" TextAlignment="Right" Width="60"/>

                <Rectangle Canvas.Left="275" Canvas.Top="0" Width="1" Height="63" Fill="#2D3748"/>

                <TextBlock Text="Stats:" Canvas.Left="285" Canvas.Top="8" FontSize="11" Foreground="#A0AEC0"/>
                <TextBlock Name="lblStatsData" Text="Speed: 0 KB/s&#x0a;Total: 0 MB" Canvas.Left="285" Canvas.Top="26" FontSize="12" FontFamily="Consolas" Foreground="#68D391" FontWeight="Bold"/>
                <TextBlock Name="lblGeoData" Text="Loc: --&#x0a;Ping: --" Canvas.Left="410" Canvas.Top="26" FontSize="12" FontFamily="Consolas" Foreground="#68D391" FontWeight="Bold"/>

                <Button Name="btnStatsPanel" Canvas.Left="276" Canvas.Top="0" Width="272" Height="63" Cursor="Hand" ToolTip="Click to refresh routing tracker">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="Transparent"/>
                            <Setter Property="BorderThickness" Value="0"/>
                            <Setter Property="Template">
                                <Setter.Value>
                                    <ControlTemplate TargetType="Button">
                                        <Border Background="{TemplateBinding Background}" CornerRadius="0,3,3,0"/>
                                    </ControlTemplate>
                                </Setter.Value>
                            </Setter>
                            <Style.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#1AFFFFFF"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </Button.Style>
                </Button>
            </Canvas>
        </Border>

        <Canvas Name="AdvancedCanvas" Canvas.Left="0" Canvas.Top="155" Opacity="0" Visibility="Hidden">
            <Border Background="#1A202C" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4" Canvas.Left="20" Canvas.Top="25" Width="550" Height="227">
                <Canvas>
                    <Border Width="548" Height="26" Canvas.Left="0" Canvas.Top="0" Background="#121417" CornerRadius="3,3,0,0" BorderBrush="#2D3748" BorderThickness="0,0,0,1"/>
                    
                    <TextBlock Text="ROUTING" Canvas.Left="0" Canvas.Top="6" Width="275" TextAlignment="Center" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    <TextBlock Text="SYSTEM" Canvas.Left="275" Canvas.Top="6" Width="275" TextAlignment="Center" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>

                    <Rectangle Canvas.Left="275" Canvas.Top="0" Width="1" Height="225" Fill="#2D3748"/>

                    <Button Name="btnDirectConfig" Canvas.Left="15" Canvas.Top="44" Width="165" Height="25" Content="Split Tunneling" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11">
                        <Button.ToolTip><ToolTip Content="Bypass the proxy for specific websites or local IP addresses." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                    </Button>
                    <Button Name="btnDirectTog" Canvas.Left="185" Canvas.Top="44" Width="75" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>
                    
                    <Button Name="btnBootLbl" Canvas.Left="290" Canvas.Top="44" Width="165" Height="25" Content="Launch on Start-up" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
                    <Button Name="btnBootTog" Canvas.Left="460" Canvas.Top="44" Width="75" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>

                    <Button Name="btnV2rayConfig" Canvas.Left="15" Canvas.Top="79" Width="165" Height="25" Content="Custom v2ray Exit-Node" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11">
                        <Button.ToolTip><ToolTip Content="Force your traffic to exit through a specific geographic country." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                    </Button>
                    <Button Name="btnV2rayTog" Canvas.Left="185" Canvas.Top="79" Width="75" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>
                    
                    <Button Name="btnDebugLbl" Canvas.Left="290" Canvas.Top="79" Width="165" Height="25" Content="Debug Mode" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11">
                        <Button.ToolTip><ToolTip Content="Launch the background engines in visible console windows for troubleshooting." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                    </Button>
                    <Button Name="btnDebugTog" Canvas.Left="460" Canvas.Top="79" Width="75" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>

                    <Button Name="btnOutboundConfig" Canvas.Left="15" Canvas.Top="114" Width="165" Height="25" Content="Outbound Proxy" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11">
                        <Button.ToolTip><ToolTip Content="Route your Tor engines through an upstream SOCKS5/HTTPS proxy." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                    </Button>
                    <Button Name="btnOutboundTog" Canvas.Left="185" Canvas.Top="114" Width="75" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>
                    
                    <Button Name="btnTrayLbl" Canvas.Left="290" Canvas.Top="114" Width="165" Height="25" Content="Minimize to Tray" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11">
                        <Button.ToolTip><ToolTip Content="Hide the application into the system tray when minimized." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                    </Button>
                    <Button Name="btnTrayTog" Canvas.Left="460" Canvas.Top="114" Width="75" Height="25" Content="Enabled" Style="{StaticResource DarkButton}" Background="#4E7A5E" FontSize="11"/>

                    <Button Name="btnDohConfig" Canvas.Left="15" Canvas.Top="149" Width="165" Height="25" Content="DNS Settings" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11">
                        <Button.ToolTip><ToolTip Content="Encrypt your initial DNS queries to hide your traffic from your ISP." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                    </Button>
                    <Button Name="btnDohTog" Canvas.Left="185" Canvas.Top="149" Width="75" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>
                    
                    <Button Name="btnLogsLbl" Canvas.Left="290" Canvas.Top="149" Width="165" Height="25" Content="Live Logs" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
                    <Button Name="btnLogsTog" Canvas.Left="460" Canvas.Top="149" Width="75" Height="25" Content="Show" Style="{StaticResource DarkButton}" FontSize="11"/>

                    <Button Name="btnAdBlockLbl" Canvas.Left="15" Canvas.Top="184" Width="165" Height="25" Content="Ad &amp; Tracker Blocker" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11">
                        <Button.ToolTip><ToolTip Content="Block system-wide ads, trackers, and telemetry loops inside Xray." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                    </Button>
                    <Button Name="btnAdBlockTog" Canvas.Left="185" Canvas.Top="184" Width="75" Height="25" Content="Disabled" Style="{StaticResource DarkButton}" Background="#8B4A4A" FontSize="11"/>

                    <Button Name="btnDesktop" Canvas.Left="290" Canvas.Top="184" Width="245" Height="25" Content="Create Desktop Shortcut" Style="{StaticResource DarkButton}" Background="#2D3748" FontSize="11"/>
                    
                    <StackPanel Visibility="Collapsed" IsEnabled="False">
                        <Button Name="btnGithub"/>
                        <Button Name="btnTelegram"/>
                    </StackPanel>
                </Canvas>
            </Border>
        </Canvas>

        <Canvas Name="LogsCanvas" Canvas.Left="585" Canvas.Top="20" Width="300" Height="225" Visibility="Hidden" Opacity="0">
            <Border Name="logBorder" Background="#121417" Width="300" Height="225" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="TOR BOOTSTRAP STATUS" Canvas.Left="15" Canvas.Top="10" Foreground="#A0AEC0" FontSize="10" FontWeight="Bold"/>
                    
                    <Button Name="btnCloseLogs" Canvas.Left="272" Canvas.Top="6" Width="22" Height="22" Content="✕" FontSize="10" FontWeight="Bold" Padding="0,-1,0,0">
                        <Button.Style>
                            <Style TargetType="Button">
                                <Setter Property="Background" Value="Transparent"/>
                                <Setter Property="Foreground" Value="#4A5568"/>
                                <Setter Property="BorderThickness" Value="0"/>
                                <Setter Property="Cursor" Value="Hand"/>
                                <Setter Property="Template">
                                    <Setter.Value>
                                        <ControlTemplate TargetType="Button">
                                            <Border Background="{TemplateBinding Background}" CornerRadius="3">
                                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                                            </Border>
                                        </ControlTemplate>
                                    </Setter.Value>
                                </Setter>
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#8B4A4A"/>
                                        <Setter Property="Foreground" Value="#E2E8F0"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <TextBlock Name="lblTor1" Text="Tor 01: Offline" Canvas.Left="15" Canvas.Top="30" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor2" Text="Tor 02: Offline" Canvas.Left="15" Canvas.Top="48" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor3" Text="Tor 03: Offline" Canvas.Left="15" Canvas.Top="66" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor4" Text="Tor 04: Offline" Canvas.Left="15" Canvas.Top="84" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    
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

# --- INTERFACE LAUNCH COMPILER ---
try {
    $form = [Windows.Markup.XamlReader]::Parse($xaml)
    
    if (Test-Path "$global:baseDir\icon.ico") { $form.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([uri]"$global:baseDir\icon.ico") }
    
} catch {
    $errMsg = $_.Exception.Message
    if ($_.Exception.InnerException) {
        $errMsg += "`n`nInner Details: " + $_.Exception.InnerException.Message
    }
    [System.Windows.Forms.MessageBox]::Show("App failed to compile the layout window.`n`nError: $errMsg", "Launch Crash Debugger", 0, 16)
    [Environment]::Exit(0)
}

# --- MAP WPF ELEMENTS TO POWERSHELL ---
$comboBridge = $form.FindName("comboBridge")
$comboConfig = $form.FindName("comboConfig")
$comboCount = $form.FindName("comboCount")
$btnAction = $form.FindName("btnAction")
$btnActionMainText = $form.FindName("btnActionMainText")
$btnActionSubText = $form.FindName("btnActionSubText")
$wavePath1 = $form.FindName("wavePath1")
$wavePath2 = $form.FindName("wavePath2")
$waveTrans1 = $form.FindName("waveTrans1")
$waveTrans2 = $form.FindName("waveTrans2")
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
$btnDohConfig = $form.FindName("btnDohConfig")
$btnDohTog = $form.FindName("btnDohTog")
$btnDesktop = $form.FindName("btnDesktop")
$btnGithub = $form.FindName("btnGithub")
$btnTelegram = $form.FindName("btnTelegram")
$AdvancedCanvas = $form.FindName("AdvancedCanvas")
$LogsCanvas = $form.FindName("LogsCanvas")
$logBorder = $form.FindName("logBorder")
$txtXrayLogs = $form.FindName("txtXrayLogs")
$btnCloseLogs = $form.FindName("btnCloseLogs")
$UnifiedPanel = $form.FindName("UnifiedPanel")
$lblSocksTitle = $form.FindName("lblSocksTitle")
$lblSocksDataIPs = $form.FindName("lblSocksDataIPs")
$lblSocksDataTags = $form.FindName("lblSocksDataTags")
$lblStatsTitle = $form.FindName("lblStatsTitle")
$lblStatsData = $form.FindName("lblStatsData")
$lblGeoData = $form.FindName("lblGeoData")
$btnStatsPanel = $form.FindName("btnStatsPanel")
$btnTrayLbl = $form.FindName("btnTrayLbl")
$btnTrayTog = $form.FindName("btnTrayTog")
$btnAdBlockLbl = $form.FindName("btnAdBlockLbl")
$btnAdBlockTog = $form.FindName("btnAdBlockTog")

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
Add-ComboItem $comboConfig "Custom" "Custom"

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
if ($null -ne $comboConfig.SelectedItem) { $global:previousConfig = $comboConfig.SelectedItem.Tag } else { $global:previousConfig = "Stable" }

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
Set-WpfToggleState $btnDohTog ($global:enableTorDoh -or $global:enableUpstreamDoh)
Set-WpfToggleState $btnBootTog $launchOnBoot
$script:debugMode = $false
Set-WpfToggleState $btnDebugTog $script:debugMode
Set-WpfToggleState $btnTrayTog $global:minimizeToTray
Set-WpfToggleState $btnAdBlockTog $global:enableAdBlock

function Update-RoutingToggle {
    $btnProxyMode.Background = $brushInactiveRouting; $btnProxyMode.Foreground = "#A0AEC0"
    $btnClearProxy.Background = $brushInactiveRouting; $btnClearProxy.Foreground = "#A0AEC0"
    
    $btnVpnMode.Background = $brushInactiveRouting; $btnVpnMode.Foreground = "#A0AEC0"
    $btnVpnMode.Cursor = [System.Windows.Input.Cursors]::Hand
    $vpnToolTip.Content = "Route your entire system's network globally through the secure tunnel."
    $vpnToolTip.Visibility = "Visible" 

    if ($global:lastXrayMode -eq "Proxy Mode") { $btnProxyMode.Background = $brushActiveRouting; $btnProxyMode.Foreground = "#FFFFFF" } elseif ($global:lastXrayMode -eq "VPN Mode") { $btnVpnMode.Background = $brushActiveRouting; $btnVpnMode.Foreground = "#FFFFFF" } elseif ($global:lastXrayMode -eq "Clear Proxy") { $btnClearProxy.Background = $brushActiveRouting; $btnClearProxy.Foreground = "#FFFFFF" }

    $btnDirectConfig.IsEnabled = $true; $btnDirectConfig.Opacity = 1.0
    $btnDirectTog.IsEnabled = $true; $btnDirectTog.Opacity = 1.0
}
Update-RoutingToggle

function Evaluate-ProxyExclusivity {
    if ($global:enableTorDoh) {
        $btnOutboundConfig.IsEnabled = $false; $btnOutboundConfig.Opacity = 0.5
        $btnOutboundTog.IsEnabled = $false; $btnOutboundTog.Opacity = 0.5
    } else {
        $btnOutboundConfig.IsEnabled = $true; $btnOutboundConfig.Opacity = 1.0
        $btnOutboundTog.IsEnabled = $true; $btnOutboundTog.Opacity = 1.0
    }
}
Evaluate-ProxyExclusivity

# --- SAFE RELATIVE BRIDGE DATABASE ---
$bridgeData = @{
    "meek_lite" = @{ "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN") }
    "obfs4" = @{ "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0", "Bridge obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0", "Bridge obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0", "Bridge obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0", "Bridge obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=1", "Bridge obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1", "Bridge obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1") }
    "snowflake" = @{ "plugin" = "ClientTransportPlugin snowflake exec ..\..\PluggableTransports\lyrebird.exe"; "lines" = @("Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn", "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn") }
}

# --- POP UP WINDOWS ---
function Show-DirectRulesDialog {
    $xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Split Tunneling &amp; Privacy Rules" Height="400" Width="480" 
        WindowStartupLocation="CenterOwner" Background="#1A1A1B" Foreground="#E2E8F0"
        ResizeMode="NoResize" FontFamily="Segoe UI" ShowInTaskbar="False">
        <Window.Resources>
            <Style TargetType="Button">
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
        </Window.Resources>
        <Canvas>
            <Border Canvas.Left="12" Canvas.Top="12" Width="440" Height="335" Background="#121417" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Name="lblTitle" Text="SPLIT TUNNELING &amp; PRIVACY ENGINE" Canvas.Left="15" Canvas.Top="12" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    
                    <TextBlock Name="lblDomains" Text="Domains or IPs to bypass Tor (Comma Separated | Proxy Mode):" Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="#E2E8F0"/>
                    <TextBox Name="txtDomains" Canvas.Left="15" Canvas.Top="55" Width="410" Height="45" 
                             Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             TextWrapping="Wrap" Padding="5" FontSize="11" FontFamily="Consolas"/>
                             
                    <TextBlock Name="lblApps" Text="Applications to bypass VPN Tunnel (e.g., spotify.exe | VPN Mode):" Canvas.Left="15" Canvas.Top="115" FontSize="11" Foreground="#E2E8F0"/>
                    <TextBox Name="txtApps" Canvas.Left="15" Canvas.Top="135" Width="410" Height="45" 
                             Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             TextWrapping="Wrap" Padding="5" FontSize="11" FontFamily="Consolas"/>

                    <TextBlock Name="lblBlock" Text="Custom Blacklisted Domains to Block Completely (e.g., tiktok.com):" Canvas.Left="15" Canvas.Top="195" FontSize="11" Foreground="#E2E8F0"/>
                    <TextBox Name="txtBlock" Canvas.Left="15" Canvas.Top="215" Width="410" Height="45" 
                             Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             TextWrapping="Wrap" Padding="5" FontSize="11" FontFamily="Consolas"/>
                             
                    <Button Name="btnOk" Content="Save Config" Canvas.Left="235" Canvas.Top="290" Width="90" Height="25" IsDefault="True">
                        <Button.Style>
                            <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                <Setter Property="Background" Value="#4E7A5E"/>
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#5F9774"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <Button Name="btnCancel" Content="Cancel" Canvas.Left="335" Canvas.Top="290" Width="90" Height="25" IsCancel="True"/>
                </Canvas>
            </Border>
        </Canvas>
    </Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    $dlg.Owner = $form

    $txtDomains = $dlg.FindName("txtDomains")
    $txtApps = $dlg.FindName("txtApps")
    $txtBlock = $dlg.FindName("txtBlock")
    $lblDomains = $dlg.FindName("lblDomains")
    $btnOk = $dlg.FindName("btnOk")
    
    $txtDomains.Text = $global:lastManualSplit
    $txtApps.Text = $global:lastAppSplit
    $txtBlock.Text = $global:lastBlockSplit

    if ($global:lastXrayMode -eq "VPN Mode") {
        $txtDomains.IsEnabled = $false
        $txtDomains.Background = [System.Windows.Media.Brushes]::Transparent
        $txtDomains.Opacity = 0.3
        $lblDomains.Text = "Domains & IPs (Disabled in VPN Mode - Use App Bypass below)"
        $lblDomains.Opacity = 0.5
    }

    $btnOk.Add_Click({
        $dlg.DialogResult = $true
        $dlg.Close()
    })
    
    $dlg.Add_Loaded({
        if ($global:lastXrayMode -eq "VPN Mode") { $txtApps.Focus() | Out-Null } else { $txtDomains.Focus() | Out-Null }
    })

    if ($dlg.ShowDialog() -eq $true) { 
        $global:lastManualSplit = $txtDomains.Text.Trim()
        $global:lastAppSplit = $txtApps.Text.Trim()
        $global:lastBlockSplit = $txtBlock.Text.Trim()
        return $true 
    }
    return $false
}

function Show-CustomBridgeDialog {
    $xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Custom Bridge Configuration" Height="240" Width="420"
        WindowStartupLocation="CenterOwner" Background="#1A1A1B" Foreground="#E2E8F0"
        ResizeMode="NoResize" FontFamily="Segoe UI" ShowInTaskbar="False">
        <Window.Resources>
            <Style TargetType="Button">
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
        </Window.Resources>
        <Canvas>
            <Border Canvas.Left="12" Canvas.Top="12" Width="380" Height="174" Background="#121417" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="CUSTOM BRIDGE CONFIGURATIONS" Canvas.Left="15" Canvas.Top="12" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    
                    <TextBox Name="txtInput" Canvas.Left="15" Canvas.Top="35" Width="350" Height="80" 
                             Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Padding="5" FontSize="11" FontFamily="Consolas"/>
                             
                    <Button Name="btnOk" Content="Save" Canvas.Left="175" Canvas.Top="132" Width="90" Height="25" IsDefault="True">
                        <Button.Style>
                            <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                <Setter Property="Background" Value="#4E7A5E"/>
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#5F9774"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <Button Name="btnCancel" Content="Cancel" Canvas.Left="275" Canvas.Top="132" Width="90" Height="25" IsCancel="True"/>
                </Canvas>
            </Border>
        </Canvas>
    </Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    
    $dlg.Owner = $form

    $txtInput = $dlg.FindName("txtInput")
    $btnOk = $dlg.FindName("btnOk")
    
    $txtInput.Text = $global:customBridgeLine

    $btnOk.Add_Click({
        $dlg.DialogResult = $true
        $dlg.Close()
    })
    
    $dlg.Add_Loaded({
        $txtInput.Focus() | Out-Null
        $txtInput.CaretIndex = $txtInput.Text.Length
    })

    if ($dlg.ShowDialog() -eq $true) { 
        $global:customBridgeLine = $txtInput.Text.Trim()
        return $true 
    }
    return $false
}
function Show-V2rayDialog {
    $xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="V2Ray Outbound Chain Configuration" Height="365" Width="520" 
        WindowStartupLocation="CenterOwner" Background="#1A1A1B" Foreground="#E2E8F0"
        ResizeMode="NoResize" FontFamily="Segoe UI" ShowInTaskbar="False">
        <Window.Resources>
            <Style TargetType="Button">
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
        </Window.Resources>
        <Canvas>
            <Border Canvas.Left="12" Canvas.Top="12" Width="480" Height="299" Background="#121417" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="V2RAY OUTBOUND CHAIN CONFIGURATION" Canvas.Left="15" Canvas.Top="12" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    <TextBlock Text="Paste the full v2rayN JSON or raw Xray Outbound below:" Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="#E2E8F0"/>
                    
                    <TextBox Name="txtInput" Canvas.Left="15" Canvas.Top="60" Width="448" Height="180" 
                             Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Padding="5" FontSize="11" FontFamily="Consolas"/>
                             
                    <Button Name="btnImport" Content="Import .json File" Canvas.Left="15" Canvas.Top="257" Width="120" Height="25"/>
                    
                    <Button Name="btnOk" Content="Validate &amp; Save" Canvas.Left="243" Canvas.Top="257" Width="110" Height="25" IsDefault="True">
                        <Button.Style>
                            <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                <Setter Property="Background" Value="#4E7A5E"/>
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#5F9774"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <Button Name="btnCancel" Content="Cancel" Canvas.Left="363" Canvas.Top="257" Width="100" Height="25" IsCancel="True"/>
                </Canvas>
            </Border>
        </Canvas>
    </Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    
    $dlg.Owner = $form

    $txtInput = $dlg.FindName("txtInput")
    $btnImport = $dlg.FindName("btnImport")
    $btnOk = $dlg.FindName("btnOk")
    
    $txtInput.Text = $global:v2rayChainJson

    $btnImport.Add_Click({
        $fd = New-Object System.Windows.Forms.OpenFileDialog
        $fd.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
        if ($fd.ShowDialog() -eq "OK") { $txtInput.Text = Get-Content $fd.FileName -Raw }
    })

    $btnOk.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtInput.Text)) { 
            $global:v2rayChainJson = ""
            $dlg.DialogResult = $true
            $dlg.Close()
            return 
        }
        try { 
            $parsed = $txtInput.Text | ConvertFrom-Json 
            $testNode = if ($null -ne $parsed.outbounds) { $parsed.outbounds[0] } else { $parsed }
            if (-not $testNode.protocol) { throw "Missing Protocol" }
            $dlg.DialogResult = $true
            $dlg.Close()
        } catch { 
            [System.Windows.Forms.MessageBox]::Show("Invalid Xray JSON syntax!", "Validation Error", 0, 16) 
        }
    })
    
    $dlg.Add_Loaded({
        $txtInput.Focus() | Out-Null
        $txtInput.CaretIndex = $txtInput.Text.Length
    })

    if ($dlg.ShowDialog() -eq $true) { 
        if (-not [string]::IsNullOrWhiteSpace($txtInput.Text)) { $global:v2rayChainJson = $txtInput.Text.Trim() }
        return $true 
    }
    return $false
}
function Show-OutboundProxyDialog {
    $xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Outbound Proxy Configuration" Height="280" Width="420" 
        WindowStartupLocation="CenterOwner" Background="#1A1A1B" Foreground="#E2E8F0"
        ResizeMode="NoResize" FontFamily="Segoe UI" ShowInTaskbar="False">
        <Window.Resources>
            <Style TargetType="Button">
                <Setter Property="Background" Value="#3A3F44"/>
                <Setter Property="Foreground" Value="#E2E8F0"/>
                <Setter Property="Cursor" Value="Hand"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="4">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
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
        </Window.Resources>
        <Canvas>
            <Border Name="borderMain" Canvas.Left="12" Canvas.Top="12" Width="380" Height="210" Background="#121417" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="OUTBOUND PROXY CONFIGURATION" Canvas.Left="15" Canvas.Top="12" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    
                    <Border Canvas.Left="15" Canvas.Top="35" Width="261" Height="25" Background="#1A202C" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4">
                        <Canvas>
                            <Border Background="#2D3748" Width="100" Height="23" CornerRadius="3,0,0,3">
                                <TextBlock Text="Proxy Type" Foreground="#A0AEC0" FontSize="11" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                            </Border>
                            <Button Name="btnHttps" Canvas.Left="100" Width="80" Height="23" Content="HTTPS" FontSize="11" Padding="0,0,0,2">
                                <Button.Style>
                                    <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                        <Setter Property="Template">
                                            <Setter.Value>
                                                <ControlTemplate TargetType="Button">
                                                    <Border Background="{TemplateBinding Background}">
                                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                                                    </Border>
                                                </ControlTemplate>
                                            </Setter.Value>
                                        </Setter>
                                    </Style>
                                </Button.Style>
                            </Button>
                            <Rectangle Canvas.Left="180" Width="1" Height="23" Fill="#2D3748"/>
                            <Button Name="btnSocks" Canvas.Left="181" Width="80" Height="23" Content="SOCKS5" FontSize="11" Padding="0,0,0,2">
                                <Button.Style>
                                    <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                        <Setter Property="Template">
                                            <Setter.Value>
                                                <ControlTemplate TargetType="Button">
                                                    <Border Background="{TemplateBinding Background}" CornerRadius="0,3,3,0">
                                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                                                    </Border>
                                                </ControlTemplate>
                                            </Setter.Value>
                                        </Setter>
                                    </Style>
                                </Button.Style>
                            </Button>
                        </Canvas>
                    </Border>
                    
                    <TextBlock Text="Address/IP:" Canvas.Left="15" Canvas.Top="70" FontSize="11" Foreground="#A0AEC0"/>
                    <TextBox Name="txtAddr" Canvas.Left="15" Canvas.Top="88" Width="240" Height="26" 
                             Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             Padding="4" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                             
                    <TextBlock Text="Port:" Canvas.Left="270" Canvas.Top="70" FontSize="11" Foreground="#A0AEC0"/>
                    <TextBox Name="txtPort" Canvas.Left="270" Canvas.Top="88" Width="95" Height="26" 
                             Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             Padding="4" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                             
                    <Border Canvas.Left="15" Canvas.Top="128" Width="180" Height="25" Background="#1A202C" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4">
                        <Canvas>
                            <Border Background="#2D3748" Width="100" Height="23" CornerRadius="3,0,0,3">
                                <TextBlock Text="Authentication" Foreground="#A0AEC0" FontSize="11" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                            </Border>
                            <Button Name="btnAuthTog" Canvas.Left="100" Width="80" Height="23" Content="Disabled" FontSize="11" Padding="0,0,0,2">
                                <Button.Style>
                                    <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                        <Setter Property="Template">
                                            <Setter.Value>
                                                <ControlTemplate TargetType="Button">
                                                    <Border Background="{TemplateBinding Background}" CornerRadius="0,3,3,0">
                                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                                                    </Border>
                                                </ControlTemplate>
                                            </Setter.Value>
                                        </Setter>
                                    </Style>
                                </Button.Style>
                            </Button>
                        </Canvas>
                    </Border>

                    <Canvas Name="panAuth" Canvas.Left="15" Canvas.Top="165" Visibility="Hidden" Opacity="0">
                        <TextBlock Text="Username:" Canvas.Left="0" Canvas.Top="0" FontSize="11" Foreground="#A0AEC0"/>
                        <TextBox Name="txtUser" Canvas.Left="0" Canvas.Top="18" Width="165" Height="26" 
                                 Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                                 Padding="4" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>

                        <TextBlock Text="Password:" Canvas.Left="185" Canvas.Top="0" FontSize="11" Foreground="#A0AEC0"/>
                        <TextBox Name="txtPass" Canvas.Left="185" Canvas.Top="18" Width="165" Height="26" 
                                 Background="#0A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                                 Padding="4" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                    </Canvas>

                    <Button Name="btnOk" Content="Save" Canvas.Left="175" Canvas.Top="168" Width="90" Height="25" IsDefault="True">
                        <Button.Style>
                            <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                <Setter Property="Background" Value="#4E7A5E"/>
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#5F9774"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <Button Name="btnCancel" Content="Cancel" Canvas.Left="275" Canvas.Top="168" Width="90" Height="25" IsCancel="True"/>
                </Canvas>
            </Border>
        </Canvas>
    </Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    
    $dlg.Owner = $form

    $borderMain = $dlg.FindName("borderMain")
    $btnHttps = $dlg.FindName("btnHttps")
    $btnSocks = $dlg.FindName("btnSocks")
    $txtAddr = $dlg.FindName("txtAddr")
    $txtPort = $dlg.FindName("txtPort")
    $btnAuthTog = $dlg.FindName("btnAuthTog")
    $panAuth = $dlg.FindName("panAuth")
    $txtUser = $dlg.FindName("txtUser")
    $txtPass = $dlg.FindName("txtPass")
    $btnOk = $dlg.FindName("btnOk")
    $btnCancel = $dlg.FindName("btnCancel")

    # Load Colors for Toggles
    $bc = New-Object System.Windows.Media.BrushConverter
    $brushOn = $bc.ConvertFromString("#4E7A5E")
    $brushOff = $bc.ConvertFromString("#8B4A4A")
    $brushInactive = $bc.ConvertFromString("#1A202C")

    # Initialize Values
    $tempType = $global:outboundProxyType
    if ([string]::IsNullOrEmpty($tempType)) { $tempType = "SOCKS5" }
    $txtAddr.Text = $global:outboundProxyAddress
    $txtPort.Text = $global:outboundProxyPort
    $txtUser.Text = $global:outboundProxyUser
    $txtPass.Text = $global:outboundProxyPass
    
    if ($global:enableOutboundAuth) { $btnAuthTog.Content = "Enabled"; $btnAuthTog.Background = $brushOn } else { $btnAuthTog.Content = "Disabled"; $btnAuthTog.Background = $brushOff }

    function Update-TypeButtons {
        if ($tempType -eq "HTTPS") { $btnHttps.Background = $brushOn; $btnSocks.Background = $brushInactive } else { $btnSocks.Background = $brushOn; $btnHttps.Background = $brushInactive }
    }
    
    $isFirstLoad = $true
    function Evaluate-AuthView {
        $targetH = if ($btnAuthTog.Content -eq "Enabled") { 340.0 } else { 280.0 }
        $targetBorderH = if ($btnAuthTog.Content -eq "Enabled") { 267.0 } else { 210.0 }
        $targetBtnTop = if ($btnAuthTog.Content -eq "Enabled") { 225.0 } else { 168.0 }
        $targetOpac = if ($btnAuthTog.Content -eq "Enabled") { 1.0 } else { 0.0 }

        if ($isFirstLoad) {
            $dlg.Height = $targetH; $borderMain.Height = $targetBorderH
            $btnOk.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$targetBtnTop)
            $btnCancel.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$targetBtnTop)
            $panAuth.Opacity = $targetOpac
            if ($btnAuthTog.Content -eq "Enabled") { $panAuth.Visibility = "Visible" } else { $panAuth.Visibility = "Hidden" }
        } else {
            if ($btnAuthTog.Content -eq "Enabled") { $panAuth.Visibility = "Visible" }
            $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(250))
            
            $dlg.BeginAnimation([System.Windows.Window]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetH, $dur)))
            $borderMain.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetBorderH, $dur)))
            $btnOk.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetBtnTop, $dur)))
            $btnCancel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetBtnTop, $dur)))
            $panAuth.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetOpac, $dur)))

            if ($btnAuthTog.Content -eq "Disabled") {
                $hideTimer = New-Object System.Windows.Threading.DispatcherTimer
                $hideTimer.Interval = [TimeSpan]::FromMilliseconds(250)
                $hideTimer.add_Tick({ 
                    $hideTimer.Stop()
                    if ($btnAuthTog.Content -eq "Disabled") { $panAuth.Visibility = "Hidden" } 
                })
                $hideTimer.Start()
            }
        }
    }

    $btnHttps.Add_Click({ $tempType = "HTTPS"; Update-TypeButtons })
    $btnSocks.Add_Click({ $tempType = "SOCKS5"; Update-TypeButtons })
    
    $btnAuthTog.Add_Click({ 
        if ($btnAuthTog.Content -eq "Disabled") { $btnAuthTog.Content = "Enabled"; $btnAuthTog.Background = $brushOn } else { $btnAuthTog.Content = "Disabled"; $btnAuthTog.Background = $brushOff }
        Evaluate-AuthView 
    })

    $btnOk.Add_Click({
        $global:outboundProxyAddress = $txtAddr.Text.Trim()
        $global:outboundProxyPort = $txtPort.Text.Trim()
        $global:outboundProxyType = $tempType
        $global:enableOutboundAuth = ($btnAuthTog.Content -eq "Enabled")
        $global:outboundProxyUser = $txtUser.Text.Trim()
        $global:outboundProxyPass = $txtPass.Text.Trim()
        $dlg.DialogResult = $true
        $dlg.Close()
    })

    $dlg.Add_Loaded({
        Update-TypeButtons
        Evaluate-AuthView
        $isFirstLoad = $false
        $txtAddr.Focus() | Out-Null
        $txtAddr.CaretIndex = $txtAddr.Text.Length
    })

    if ($dlg.ShowDialog() -eq $true) { return $true }
    return $false
}

function Show-DohDialog {
    $xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DNS Settings" Height="300" Width="420" 
        WindowStartupLocation="CenterOwner" Background="#1A1A1B" Foreground="#E2E8F0"
        ResizeMode="NoResize" FontFamily="Segoe UI" ShowInTaskbar="False">
        <Window.Resources>
            <Style TargetType="Button">
                <Setter Property="Background" Value="#3A3F44"/>
                <Setter Property="Foreground" Value="#E2E8F0"/>
                <Setter Property="Cursor" Value="Hand"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="4">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
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
        </Window.Resources>
        <Canvas>
            <Border Name="borderMain" Canvas.Left="12" Canvas.Top="12" Width="380" Height="234" Background="#121417" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="DNS SETTINGS" Canvas.Left="15" Canvas.Top="12" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    
                    <TextBlock Name="lblWarn" Text="⚠️ Tor DoH cannot be active while an Outbound Proxy is enabled." Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="#F6AD55" Visibility="Hidden"/>
                    
                    <TextBlock Name="lblTor" Text="Tor Outbound DoH (Initial Handshake):" Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="#A0AEC0"/>
                    <Border Name="borTor" Canvas.Left="15" Canvas.Top="55" Width="350" Height="26" Background="#0A0C0F" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4">
                        <Canvas>
                            <TextBox Name="txtTorDoh" Canvas.Left="2" Canvas.Top="0" Width="268" Height="24" 
         Background="#0A0C0F" Foreground="#68D391" CaretBrush="White" BorderThickness="0" 
         Padding="5,0,4,0" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                            
                            <Rectangle Canvas.Left="269" Canvas.Top="0" Width="1" Height="24" Fill="#2D3748"/>
                            
                            <Button Name="btnTorTog" Canvas.Left="270" Canvas.Top="0" Width="80" Height="24" Content="Disabled" FontSize="11" Padding="0,0,0,2">
                                <Button.Style>
                                    <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                        <Setter Property="Template">
                                            <Setter.Value>
                                                <ControlTemplate TargetType="Button">
                                                    <Border Background="{TemplateBinding Background}" CornerRadius="0,3,3,0">
                                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                                                    </Border>
                                                </ControlTemplate>
                                            </Setter.Value>
                                        </Setter>
                                    </Style>
                                </Button.Style>
                            </Button>
                        </Canvas>
                    </Border>

                    <TextBlock Name="lblUp" Text="Upstream DoH (Xray / Sing-box):" Canvas.Left="15" Canvas.Top="90" FontSize="11" Foreground="#A0AEC0"/>
                    <Border Name="borUp" Canvas.Left="15" Canvas.Top="110" Width="350" Height="26" Background="#0A0C0F" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4">
                        <Canvas>
                            <TextBox Name="txtUpDoh" Canvas.Left="2" Canvas.Top="0" Width="268" Height="24" 
         Background="#0A0C0F" Foreground="#68D391" CaretBrush="White" BorderThickness="0" 
         Padding="5,0,4,0" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                            
                            <Rectangle Canvas.Left="269" Canvas.Top="0" Width="1" Height="24" Fill="#2D3748"/>
                            
                            <Button Name="btnUpTog" Canvas.Left="270" Canvas.Top="0" Width="80" Height="24" Content="Disabled" FontSize="11" Padding="0,0,0,2">
                                <Button.Style>
                                    <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                        <Setter Property="Template">
                                            <Setter.Value>
                                                <ControlTemplate TargetType="Button">
                                                    <Border Background="{TemplateBinding Background}" CornerRadius="0,3,3,0">
                                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                                                    </Border>
                                                </ControlTemplate>
                                            </Setter.Value>
                                        </Setter>
                                    </Style>
                                </Button.Style>
                            </Button>
                        </Canvas>
                    </Border>

                    <TextBlock Name="lblHint" Canvas.Left="15" Canvas.Top="145" Width="350" TextWrapping="Wrap" FontSize="11" Foreground="#4A5568" 
                               Text="Hint: Enter a full DoH URL or a standard IPv4 DNS.&#x0a;(e.g., https://1.1.1.1/dns-query OR 10.202.10.10)"/>
                               
                    <Button Name="btnOk" Content="Save" Canvas.Left="175" Canvas.Top="192" Width="90" Height="25" IsDefault="True">
                        <Button.Style>
                            <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                <Setter Property="Background" Value="#4E7A5E"/>
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#5F9774"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <Button Name="btnCancel" Content="Cancel" Canvas.Left="275" Canvas.Top="192" Width="90" Height="25" IsCancel="True"/>
                </Canvas>
            </Border>
        </Canvas>
    </Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    
    $dlg.Owner = $form

    $borderMain = $dlg.FindName("borderMain")
    $lblWarn = $dlg.FindName("lblWarn")
    $lblTor = $dlg.FindName("lblTor")
    $borTor = $dlg.FindName("borTor")
    $btnTorTog = $dlg.FindName("btnTorTog")
    $txtTorDoh = $dlg.FindName("txtTorDoh")
    
    $lblUp = $dlg.FindName("lblUp")
    $borUp = $dlg.FindName("borUp")
    $btnUpTog = $dlg.FindName("btnUpTog")
    $txtUpDoh = $dlg.FindName("txtUpDoh")
    
    $lblHint = $dlg.FindName("lblHint")
    $btnOk = $dlg.FindName("btnOk")
    $btnCancel = $dlg.FindName("btnCancel")

    # Load Colors
    $bc = New-Object System.Windows.Media.BrushConverter
    $brushOn = $bc.ConvertFromString("#4E7A5E")
    $brushOff = $bc.ConvertFromString("#8B4A4A")
    $brushInactive = $bc.ConvertFromString("#1A202C")

    # Initialize Values
    $txtTorDoh.Text = $global:torDohUrl
    $txtUpDoh.Text = $global:upstreamDohUrl

    if ($global:enableUpstreamDoh) { $btnUpTog.Content = "Enabled"; $btnUpTog.Background = $brushOn } else { $btnUpTog.Content = "Disabled"; $btnUpTog.Background = $brushOff }

    # Dynamic Layout Check
    if ($global:enableOutboundProxy) {
        $dlg.Height = 320
        $borderMain.Height = 254
        
        $lblWarn.Visibility = "Visible"
        
        $lblTor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]55)
        $borTor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]75)
        $lblUp.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]110)
        $borUp.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]130)
        $lblHint.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]165)
        
        $btnOk.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]212)
        $btnCancel.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]212)

        $btnTorTog.Content = "Disabled"
        $btnTorTog.Background = $brushInactive
        $btnTorTog.IsEnabled = $false
        $txtTorDoh.IsEnabled = $false
        $borTor.Opacity = 0.3
        $lblTor.Opacity = 0.5
    } else {
        if ($global:enableTorDoh) { $btnTorTog.Content = "Enabled"; $btnTorTog.Background = $brushOn } else { $btnTorTog.Content = "Disabled"; $btnTorTog.Background = $brushOff }
        
        $btnTorTog.Add_Click({
            if ($btnTorTog.Content -eq "Disabled") { $btnTorTog.Content = "Enabled"; $btnTorTog.Background = $brushOn } else { $btnTorTog.Content = "Disabled"; $btnTorTog.Background = $brushOff }
        })
    }

    $btnUpTog.Add_Click({
        if ($btnUpTog.Content -eq "Disabled") { $btnUpTog.Content = "Enabled"; $btnUpTog.Background = $brushOn } else { $btnUpTog.Content = "Disabled"; $btnUpTog.Background = $brushOff }
    })

    $btnOk.Add_Click({
        $global:enableTorDoh = ($btnTorTog.Content -eq "Enabled")
        if (-not [string]::IsNullOrWhiteSpace($txtTorDoh.Text)) { $global:torDohUrl = $txtTorDoh.Text.Trim() }
        
        $global:enableUpstreamDoh = ($btnUpTog.Content -eq "Enabled")
        if (-not [string]::IsNullOrWhiteSpace($txtUpDoh.Text)) { $global:upstreamDohUrl = $txtUpDoh.Text.Trim() }
        
        $dlg.DialogResult = $true
        $dlg.Close()
    })

    $dlg.Add_Loaded({
        $txtTorDoh.Focus() | Out-Null
        $txtTorDoh.CaretIndex = $txtTorDoh.Text.Length
    })

    if ($dlg.ShowDialog() -eq $true) { return $true }
    return $false
}
function Show-ExitNodeDialog {
    $xaml = @"
    <Window 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Custom Exit-Node Selection" Height="210" Width="420" 
        WindowStartupLocation="CenterOwner" Background="#1A1A1B" Foreground="#E2E8F0"
        ResizeMode="NoResize" FontFamily="Segoe UI" ShowInTaskbar="False">
        <Window.Resources>
            <Style TargetType="Button">
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

            <Style TargetType="ComboBox" x:Key="DarkComboBox">
                <Setter Property="Foreground" Value="#E2E8F0"/>
                <Setter Property="Background" Value="#0A0C0F"/>
                <Setter Property="BorderBrush" Value="#2D3748"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="ComboBox">
                            <Grid>
                                <ToggleButton Name="ToggleButton" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Focusable="False" IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press">
                                    <ToggleButton.Template>
                                        <ControlTemplate TargetType="ToggleButton">
                                            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4">
                                                <ContentPresenter HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,5,0"/>
                                            </Border>
                                        </ControlTemplate>
                                    </ToggleButton.Template>
                                    <Path Fill="#A0AEC0" Data="M0,0 L4,4 L8,0 Z" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,5,0"/>
                                </ToggleButton>
                                <ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="8,0,23,2" VerticalAlignment="Center" HorizontalAlignment="Left">
                                    <ContentPresenter.Resources>
                                        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#68D391"/></Style>
                                    </ContentPresenter.Resources>
                                </ContentPresenter>
                                <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                    <Border Name="DropDownBorder" Background="#1A202C" BorderThickness="1" BorderBrush="#3A3F44" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="150">
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
                    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#4A5568"/></Trigger>
                </Style.Triggers>
            </Style>
        </Window.Resources>

        <Canvas>
            <Border Canvas.Left="12" Canvas.Top="12" Width="380" Height="144" Background="#121417" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="CUSTOM EXIT-NODE ROUTING" Canvas.Left="15" Canvas.Top="12" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    <TextBlock Text="Select your desired geographic exit location:" Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="#E2E8F0"/>
                    
                    <ComboBox Name="cmbCountries" Canvas.Left="15" Canvas.Top="57" Width="350" Height="28" FontSize="11" FontFamily="Consolas" Style="{StaticResource DarkComboBox}"/>
                             
                    <Button Name="btnOk" Content="Save" Canvas.Left="175" Canvas.Top="102" Width="90" Height="25" IsDefault="True">
                        <Button.Style>
                            <Style TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
                                <Setter Property="Background" Value="#4E7A5E"/>
                                <Style.Triggers>
                                    <Trigger Property="IsMouseOver" Value="True">
                                        <Setter Property="Background" Value="#5F9774"/>
                                    </Trigger>
                                </Style.Triggers>
                            </Style>
                        </Button.Style>
                    </Button>
                    
                    <Button Name="btnCancel" Content="Cancel" Canvas.Left="275" Canvas.Top="102" Width="90" Height="25" IsCancel="True"/>
                </Canvas>
            </Border>
        </Canvas>
    </Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    
    $dlg.Owner = $form

    $cmbCountries = $dlg.FindName("cmbCountries")
    $btnOk = $dlg.FindName("btnOk")
    
    $countries = [ordered]@{ 
        "Argentina" = "ar"; "Australia" = "au"; "Brazil" = "br"; "Canada" = "ca"; 
        "Finland" = "fi"; "France" = "fr"; "Germany" = "de"; "Hong Kong" = "hk"; 
        "Iceland" = "is"; "India" = "in"; "Italy" = "it"; "Japan" = "jp"; 
        "Mexico" = "mx"; "Netherlands" = "nl"; "New Zealand" = "nz"; "Romania" = "ro"; 
        "Singapore" = "sg"; "South Africa" = "za"; "South Korea" = "kr"; "Spain" = "es"; 
        "Sweden" = "se"; "Switzerland" = "ch"; "United Kingdom" = "uk"; "United States" = "us"
    }
    
    foreach ($c in $countries.Keys) { 
        $cbi = New-Object System.Windows.Controls.ComboBoxItem
        $cbi.Content = "$c ($($countries[$c].ToUpper()))"
        $cbi.Tag = $countries[$c]
        $cmbCountries.Items.Add($cbi) | Out-Null
    }
    
    # Pre-select based on the Tag
    foreach ($item in $cmbCountries.Items) {
        if ($item.Tag -eq $global:customExitCountry) { $cmbCountries.SelectedItem = $item; break }
    }
    if ($null -eq $cmbCountries.SelectedItem -and $cmbCountries.Items.Count -gt 0) { $cmbCountries.SelectedIndex = 0 }

    $btnOk.Add_Click({
        $dlg.DialogResult = $true
        $dlg.Close()
    })

    if ($dlg.ShowDialog() -eq $true) { 
        $global:customExitCountry = $cmbCountries.SelectedItem.Tag.ToLower()
        return $true 
    }
    return $false
}
# --- CORE LOGIC ---
function Save-Config {
    $selConfig = if ($comboConfig.SelectedItem.Tag -match "Fast") { "Fast" } elseif ($comboConfig.SelectedItem.Tag -match "Custom") { "Custom" } else { "Stable" }
    $selCount = [int]($comboCount.SelectedItem.Tag)
    @{ AutoStart = [bool]$autoStart; LaunchOnBoot = [bool]$launchOnBoot; LastConfig = $selConfig; SelectedBridge = $comboBridge.SelectedItem.Tag; InstanceCount = $selCount; XrayMode = $global:lastXrayMode; ManualSplit = $global:lastManualSplit; AppSplit = $global:lastAppSplit; BlockSplit = $global:lastBlockSplit; EnableDirect = $global:enableDirect; CustomBridgeLine = $global:customBridgeLine; EnableV2rayChain = $global:enableV2rayChain; V2rayChainJson = $global:v2rayChainJson; EnableOutboundProxy = $global:enableOutboundProxy; OutboundProxyAddress = $global:outboundProxyAddress; OutboundProxyPort = $global:outboundProxyPort; OutboundProxyType = $global:outboundProxyType; OutboundProxyUser = $global:outboundProxyUser; OutboundProxyPass = $global:outboundProxyPass; EnableOutboundAuth = $global:enableOutboundAuth; EnableTorDoh = [bool]$global:enableTorDoh; TorDohUrl = $global:torDohUrl; EnableUpstreamDoh = [bool]$global:enableUpstreamDoh; UpstreamDohUrl = $global:upstreamDohUrl; CustomExitCountry = $global:customExitCountry; MinimizeToTray = [bool]$global:minimizeToTray; EnableAdBlock = [bool]$global:enableAdBlock } | ConvertTo-Json -Depth 10 | Set-Content $cfgFile
}

function Write-XrayConfig {
    $rules = @( @{ type="field"; ip=@("127.0.0.0/8", "::1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"); outboundTag="direct" } )
    
    # 1. Rebuild Blackhole routing rules based on active AdBlock or Custom rules
    $blockDomains = @()
    if ($global:enableAdBlock) {
        $blockDomains += @("geosite:category-ads-all", "domain:analytics.google.com", "domain:google-analytics.com")
    }
    if ($global:enableDirect -and -not [string]::IsNullOrWhiteSpace($global:lastBlockSplit)) {
        $customBlocks = $global:lastBlockSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($bDomain in $customBlocks) { $blockDomains += "domain:$bDomain" }
    }
    if ($blockDomains.Count -gt 0) {
        $rules += @{ type="field"; domain=$blockDomains; outboundTag="block" }
    }
    
    # 2. Rebuild Domain Split Tunneling array (Proxy Mode only)
    $domains = @(); $ips = @()
    if ($global:enableDirect -and $global:lastXrayMode -ne "VPN Mode" -and $global:lastManualSplit -ne "") {
        $list = $global:lastManualSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($item in $list) { 
            if ($item -match "[a-zA-Z]") { $domains += "domain:$item" } else { $ips += $item } 
        }
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
    
    # Inject Blackhole sinkhole protocol if rules demand blocking filters
    if ($global:enableAdBlock -or ($global:enableDirect -and -not [string]::IsNullOrWhiteSpace($global:lastBlockSplit))) {
        $outbounds += @{ tag="block"; protocol="blackhole"; settings=@{} }
    }
    
    $outbounds += @{ tag="direct"; protocol="freedom"; settings=@{} }
    
    $config = @{ log = @{ logLevel="info"; access="access.log"; error="error.log" }; inbounds = $inboundArr; outbounds = $outbounds; routing = @{ domainStrategy="AsIs"; rules=$rules } }
    
    # Inject Upstream DoH
    if ($global:enableUpstreamDoh -and -not [string]::IsNullOrWhiteSpace($global:upstreamDohUrl)) {
        $config.Add("dns", @{ servers = @($global:upstreamDohUrl) })
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content "$xrayDir\config.json"
}

function Write-SingboxConfig {
    # Core system proxy engines bypassed from global WFP routing loops
    $bypassApps = @("tor.exe", "haproxy.exe", "lyrebird.exe", "obfs4proxy.exe", "snowflake-client.exe", "xray.exe", "sing-box.exe")
    
    if ($global:enableDirect -and -not [string]::IsNullOrWhiteSpace($global:lastAppSplit)) {
        $customApps = $global:lastAppSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($app in $customApps) {
            $normalizedApp = if ($app -notmatch "\.exe$") { "$app.exe" } else { $app }
            $bypassApps += $normalizedApp.ToLower()
        }
    }

    $sbRules = @(
        @{ process_name = $bypassApps; outbound = "direct" }
        @{ action = "sniff" }
        @{ port = @(53); action = "hijack-dns" }
        @{ protocol = "dns"; action = "hijack-dns" }
        @{ ip_is_private = $true; outbound = "direct" }
        
        @{ network = "udp"; port = @(443); outbound = "block" } 
    )

    if ($global:enableUpstreamDoh -and -not [string]::IsNullOrWhiteSpace($global:upstreamDohUrl)) {
        if ($global:upstreamDohUrl.StartsWith("https://")) {
            try {
                $sbUri = [uri]$global:upstreamDohUrl
                $sbHost = $sbUri.Host
                $sbPath = if ($sbUri.AbsolutePath -eq "/") { "/dns-query" } else { $sbUri.PathAndQuery }
                $dnsServer = @{ tag = "dns_proxy"; type = "https"; server = $sbHost; path = $sbPath; detour = "proxy" }
            } catch { $dnsServer = @{ tag = "dns_proxy"; type = "tcp"; server = "1.1.1.1"; detour = "proxy" } }
        } else {
            $dnsServer = @{ tag = "dns_proxy"; type = "tcp"; server = $global:upstreamDohUrl; detour = "proxy" }
        }
    } else {
        $dnsServer = @{ tag = "dns_proxy"; type = "https"; server = "cloudflare-dns.com"; path = "/dns-query"; detour = "proxy" }
    }

    $sbConfig = @{
        log = @{ level = "fatal" } 
        dns = @{ 
            servers = @( $dnsServer )
            final = "dns_proxy" 
            strategy = "ipv4_only" 
        }
        inbounds = @( @{ 
            type = "tun"
            tag = "tun-in"
            interface_name = "singbox_tun"
            address = @("172.18.0.1/30") 
            mtu = 9000
            auto_route = $true
            strict_route = $true
            stack = "gvisor" 
        } )
        outbounds = @( 
            @{ type = "socks"; tag = "proxy"; server = "127.0.0.1"; server_port = 10818 }, 
            @{ type = "direct"; tag = "direct" },
            @{ type = "block"; tag = "block" } 
        )
        route = @{ 
            auto_detect_interface = $true 
            rules = $sbRules 
            final = "proxy" 
        }
    }
    
    $sbConfig | ConvertTo-Json -Depth 10 | Set-Content "$sbDir\config.json"
}

function Set-SystemProxy($enable) {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($enable) { 
        Set-ItemProperty $path -Name "ProxyEnable" -Value 1
        Set-ItemProperty $path -Name "ProxyServer" -Value "127.0.0.1:10818"
        
        $bypassList = "<local>"
        if ($global:enableDirect -and -not [string]::IsNullOrWhiteSpace($global:lastManualSplit) -and $global:lastXrayMode -eq "Proxy Mode") {
            $clean = $global:lastManualSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            $bypassList = "$($clean -join ';');<local>"
        }
        Set-ItemProperty $path -Name "ProxyOverride" -Value $bypassList
    } 
    else { 
        Set-ItemProperty $path -Name "ProxyEnable" -Value 0 
    }
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Restart-Xray($targetMode) {
    Get-Process sing-box, xray -ErrorAction SilentlyContinue | ForEach-Object { try { if ($null -ne $_.Path -and ($_.Path -eq "$xrayDir\xray.exe" -or $_.Path -eq "$global:baseDir\Data\sing_box\sing-box.exe")) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } } catch {} }
    if ($null -ne $global:cmdDebugPid) { Stop-Process -Id $global:cmdDebugPid -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid = $null }
    if ($null -ne $global:cmdDebugPid2) { Stop-Process -Id $global:cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid2 = $null }
    if ($null -ne $global:xrayDohPid) { Stop-Process -Id $global:xrayDohPid -Force -ErrorAction SilentlyContinue; $global:xrayDohPid = $null }
    
    Start-Sleep -Milliseconds 500
    Write-XrayConfig
    if ($script:debugMode) { $p = Start-Process "cmd.exe" -ArgumentList "/c `"title XrayDebug & .\xray.exe run -c config.json || pause`"" -WorkingDirectory $xrayDir -WindowStyle Normal -PassThru; $global:cmdDebugPid = $p.Id } else { Start-Process -FilePath "$xrayDir\xray.exe" -ArgumentList "run -c config.json" -WorkingDirectory $xrayDir -WindowStyle Hidden }
    if ($targetMode -eq "VPN Mode") {
        Write-SingboxConfig
        if ($script:debugMode) { $p2 = Start-Process "cmd.exe" -ArgumentList "/c `"title SingBoxDebug & .\sing-box.exe run -c config.json || pause`"" -WorkingDirectory $sbDir -WindowStyle Normal -PassThru; $global:cmdDebugPid2 = $p2.Id } else { Start-Process -FilePath "$sbDir\sing-box.exe" -ArgumentList "run -c config.json" -WorkingDirectory $sbDir -WindowStyle Hidden }
    } elseif ($targetMode -eq "Proxy Mode") { Set-SystemProxy $true }
    if ($targetMode -ne "Proxy Mode") { Set-SystemProxy $false }

    if ($global:isConnected) {
        if ($null -ne $global:pingTimer) { $global:pingTimer.Stop() } 
        
        $global:pingTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:pingTimer.Interval = [TimeSpan]::FromSeconds(1.5)
        $global:pingTimer.add_Tick({
            $global:pingTimer.Stop() 
            Start-GeoPing
        })
        $global:pingTimer.Start()
    }
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

# --- REAL-TIME PHYSICS ACCELERATED WAVE ENGINE WITH VELOCITY SUSTAIN ---
function Update-WaveAnimation {
    param([string]$State)
    
    if ($null -eq $wavePath1 -or $null -eq $waveTrans1 -or $null -eq $waveTrans2) { return }
    
    # 1. Initialize background rendering clock on startup
    if ($null -eq $global:wavePhysicsTimer) {
        $global:waveX1 = 0.0
        $global:waveX2 = -75.0
        $global:waveCurrentSpeed1 = 0.4
        $global:waveCurrentSpeed2 = 0.5
        $global:waveTargetSpeed1 = 0.4
        $global:waveTargetSpeed2 = 0.5
        
        $global:wavePhysicsTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:wavePhysicsTimer.Interval = [TimeSpan]::FromMilliseconds(25)
        $global:wavePhysicsTimer.add_Tick({
            # Smooth Inertia Easing: Closes 8% of the speed gap every single frame
            $global:waveCurrentSpeed1 += ($global:waveTargetSpeed1 - $global:waveCurrentSpeed1) * 0.08
            $global:waveCurrentSpeed2 += ($global:waveTargetSpeed2 - $global:waveCurrentSpeed2) * 0.08
            
            $global:waveX1 -= $global:waveCurrentSpeed1
            $global:waveX2 -= $global:waveCurrentSpeed2
            
            if ($global:waveX1 -le -150.0) { $global:waveX1 += 150.0 }
            if ($global:waveX2 -le -225.0) { $global:waveX2 += 150.0 }
            
            $waveTrans1.X = $global:waveX1
            $waveTrans2.X = $global:waveX2
        })
        $global:wavePhysicsTimer.Start()
    }
    
    $colorHex = "#718096"
    if ($null -ne $global:waveHoldTimer) { $global:waveHoldTimer.Stop() }
    
    # 2. Adjust speeds and hold thresholds per state
    switch ($State) {
        "Idle" {
            $colorHex = "#718096"
            $global:waveTargetSpeed1 = 0.4
            $global:waveTargetSpeed2 = 0.5
        }
        "Connecting" {
            $colorHex = "#B78854"
            $global:waveCurrentSpeed1 = 5.5
            $global:waveCurrentSpeed2 = 6.0
            $global:waveTargetSpeed1 = 5.5 
            $global:waveTargetSpeed2 = 6.0
            
            $global:waveHoldTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:waveHoldTimer.Interval = [TimeSpan]::FromMilliseconds(600) 
            $global:waveHoldTimer.add_Tick({
                $global:waveHoldTimer.Stop()
                $global:waveTargetSpeed1 = 1.1
                $global:waveTargetSpeed2 = 1.3
            }.GetNewClosure())
            $global:waveHoldTimer.Start()
        }
        "Connected" {
            $colorHex = "#68D391"
            $global:waveCurrentSpeed1 = 5.5
            $global:waveCurrentSpeed2 = 6.0
            $global:waveTargetSpeed1 = 5.5
            $global:waveTargetSpeed2 = 6.0
            
            $global:waveHoldTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:waveHoldTimer.Interval = [TimeSpan]::FromMilliseconds(600)
            $global:waveHoldTimer.add_Tick({
                $global:waveHoldTimer.Stop()
                $global:waveTargetSpeed1 = 0.4
                $global:waveTargetSpeed2 = 0.5
            }.GetNewClosure())
            $global:waveHoldTimer.Start()
        }
    }
    
    # 3. Smooth Color Cross-Fades
    try {
        $targetColor = [System.Windows.Media.ColorConverter]::ConvertFromString($colorHex)
        $colorAnim = New-Object System.Windows.Media.Animation.ColorAnimation
        $colorAnim.To = $targetColor
        $colorAnim.Duration = New-Object System.Windows.Duration([TimeSpan]::FromSeconds(0.8))
        
        $brush1 = New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Colors]::Gray)
        $brush2 = New-Object System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.Colors]::Gray)
        $brush1.Opacity = 0.25; $brush2.Opacity = 0.15
        $wavePath1.Fill = $brush1; $wavePath2.Fill = $brush2
        
        $brush1.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $colorAnim)
        $brush2.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $colorAnim)
    } catch {}
}

# --- ASYNC GEO-IP TRACKER ---
function Start-GeoPing {
    $lblGeoData.Text = "Loc: TRACING...`nPing: --"
    $lblGeoData.Foreground = "#68D391" 
    
    $geoClient = New-Object System.Net.WebClient
    $geoClient.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:10818")
    
    $global:geoSw = [System.Diagnostics.Stopwatch]::StartNew()
    
    $geoClient.Add_DownloadStringCompleted({
        param($sender, $e)
        $global:geoSw.Stop()
        $pingMs = $global:geoSw.ElapsedMilliseconds
        
        $form.Dispatcher.Invoke([System.Action]{
            if ($global:isConnected) {
                if (-not $e.Cancelled -and $e.Error -eq $null) {
                    try {
                        $data = $e.Result | ConvertFrom-Json
                        $geoStr = ""
                        
                        $selConfig = if ($comboConfig.SelectedItem.Tag -match "Fast") { "Fast" } elseif ($comboConfig.SelectedItem.Tag -match "Custom") { "Custom" } else { "Stable" }
                        if ($selConfig -eq "Custom" -or $global:enableV2rayChain) {
                            $geoStr = $data.country
                        } else {
                            $cMap = @{ "NA"="NORTH AMERICA"; "EU"="EUROPE"; "AS"="ASIA"; "SA"="SOUTH AMERICA"; "AF"="AFRICA"; "OC"="OCEANIA"; "AN"="ANTARCTICA" }
                            $geoStr = $cMap[$data.continent_code]
                            if (-not $geoStr) { $geoStr = $data.continent_code }
                        }
                        
                        $lblGeoData.Text = "Loc: $($geoStr.ToUpper())`nPing: $($pingMs)ms"
                        $lblGeoData.Foreground = "#68D391" 
                    } catch { $lblGeoData.Text = "Loc: ERROR`nPing: --"; $lblGeoData.Foreground = "#8B4A4A" }
                } else { $lblGeoData.Text = "Loc: TIMEOUT`nPing: --"; $lblGeoData.Foreground = "#8B4A4A" }
            }
        })
        $sender.Dispose()
    })
    
    try { $geoClient.DownloadStringAsync([uri]"https://get.geojs.io/v1/ip/geo.json") } catch { $lblGeoData.Text = "Loc: ERROR`nPing: --"; $lblGeoData.Foreground = "#8B4A4A" }
}

function Reset-ButtonText { 
    $btnActionMainText.Text = "CONNECT"
    $btnActionSubText.Text = ""
    $btnActionMainText.Foreground = "#E2E8F0"
    Update-WaveAnimation -State "Idle"
}

function Stop-AllEngines($isClosing = $false) {
    $global:abortBoot = $true; Set-SystemProxy $false
    $global:isEngineRunning = $false
    
    Get-Process tor, haproxy, xray, sing-box -ErrorAction SilentlyContinue | ForEach-Object { try { $p = $_.Path; if ($null -ne $p -and ($p -eq "$xrayDir\xray.exe" -or $p -eq "$haPath\haproxy.exe" -or $p -eq "$global:baseDir\Data\sing_box\sing-box.exe" -or $p -match "Data\\Tors\\Tor")) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } } catch {} }
    if ($null -ne $global:cmdDebugPid) { Stop-Process -Id $global:cmdDebugPid -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid = $null }
    if ($null -ne $global:cmdDebugPid2) { Stop-Process -Id $global:cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid2 = $null }
    if ($null -ne $global:xrayDohPid) { Stop-Process -Id $global:xrayDohPid -Force -ErrorAction SilentlyContinue; $global:xrayDohPid = $null }
    $global:isConnected = $false; $global:lastTotalBytes = 0; $global:sessionDataBytes = 0
    
    if (-not $isClosing) {
        Reset-ButtonText
        $btnAction.IsEnabled = $true
        $lblSocksTitle.Text = "Mixed Port:"
        $lblSocksDataIPs.Text = "Waiting for connection..."
        $lblSocksDataTags.Text = ""
        $lblStatsData.Text = "Speed: 0 KB/s`nTotal: 0 MB"
        $lblGeoData.Text = "Loc: --`nPing: --"
        $lblGeoData.Foreground = "#68D391"
    }
}

function Start-Engines {
    try {
        if (Get-Process tor -ErrorAction SilentlyContinue) { $btnActionSubText.Text = "Clearing old engines..."; DoEvents; Stop-AllEngines; Start-Sleep -Seconds 1 }
        $global:abortBoot = $false; $selBridge = $comboBridge.SelectedItem.Tag
        $selConfig = if ($comboConfig.SelectedItem.Tag -match "Fast") { "Fast" } elseif ($comboConfig.SelectedItem.Tag -match "Custom") { "Custom" } else { "Stable" }
        $selCount = [int]($comboCount.SelectedItem.Tag)
        $mode = $global:lastXrayMode; $cfgFileTarget = "torrc"

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
        
        $btnActionMainText.Text = "CONNECTING"
        Update-WaveAnimation -State "Connecting"
        $btnActionMainText.Foreground = "#F6AD55"; $btnActionSubText.Foreground = "#B78854"
        Format-HAProxyConfig $selCount; $dynamicWait = 16 - $selCount

        if ($global:enableTorDoh -and -not $global:enableOutboundProxy) {
            Write-TorOutboundDohConfig
            $pDoH = Start-Process -FilePath "$xrayDir\xray.exe" -ArgumentList "run -c tor-doh.json" -WorkingDirectory $xrayDir -WindowStyle Hidden -PassThru
            $global:xrayDohPid = $pDoH.Id
        }
        
        for ($i=1; $i -le $selCount; $i++) {
            if ($global:abortBoot) { break } 
            $btnActionSubText.Text = "Booting Tor $i of $selCount"
            DoEvents
            
            $path = "$global:baseDir\Data\Tors\Tor$i"
            if (Test-Path "$path\$cfgFileTarget") {
                $c = @(Get-Content "$path\$cfgFileTarget"); $cleanConfig = @()
                foreach ($line in $c) {
                    if ($line -match "^# --- MANAGED BRIDGES ---") { break }
                    if ($line -notmatch "^UseBridges" -and $line -notmatch "^ClientTransportPlugin" -and $line -notmatch "^Bridge" -and $line -notmatch "^HTTPSProxy" -and $line -notmatch "^Socks5Proxy" -and $line -notmatch "^Socks5ProxyUsername" -and $line -notmatch "^Socks5ProxyPassword" -and $line -notmatch "^HTTPSProxyAuthenticator" -and $line -notmatch "^Log notice file" -and $line -notmatch "^MaxCircuitDirtiness" -and $line -notmatch "^ExitNodes" -and $line -notmatch "^StrictNodes" -and $line -notmatch "^# --- DYNAMIC ROUTING ---") {
                        if ($line.Trim() -ne "") { $cleanConfig += $line.Trim() }
                    }
                }
                
                $cleanConfig += ""
                $cleanConfig += "# --- DYNAMIC ROUTING ---"
                if ($selConfig -eq "Fast") {
                    $cleanConfig += "MaxCircuitDirtiness 600"
                    $cleanConfig += "ExitNodes {de},{nl},{ch}"
                    $cleanConfig += "StrictNodes 1"
                } elseif ($selConfig -eq "Custom" -and -not [string]::IsNullOrWhiteSpace($global:customExitCountry)) {
                    $cleanConfig += "ExitNodes {$($global:customExitCountry)}"
                    $cleanConfig += "StrictNodes 1"
                } else {
                    $cleanConfig += "ExitNodes {de},{fr},{nl},{uk},{se},{ch}"
                    $cleanConfig += "StrictNodes 0"
                }

                $cleanConfig += ""
                $cleanConfig += "# --- MANAGED BRIDGES ---"
                $cleanConfig += "Log notice file tor.log"
                
                if ($global:enableOutboundProxy -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyAddress) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPort)) {
                    if ($global:outboundProxyType -eq "SOCKS5") {
                        $cleanConfig += "Socks5Proxy $($global:outboundProxyAddress):$($global:outboundProxyPort)"
                        if ($global:enableOutboundAuth -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyUser) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPass)) { $cleanConfig += "Socks5ProxyUsername $($global:outboundProxyUser)"; $cleanConfig += "Socks5ProxyPassword $($global:outboundProxyPass)" }
                    } elseif ($global:outboundProxyType -eq "HTTPS") {
                        $cleanConfig += "HTTPSProxy $($global:outboundProxyAddress):$global:outboundProxyPort"
                        if ($global:enableOutboundAuth -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyUser) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPass)) { $cleanConfig += "HTTPSProxyAuthenticator $($global:outboundProxyUser):$($global:outboundProxyPass)" }
                    }
                } elseif ($global:enableTorDoh) {
                    $cleanConfig += "Socks5Proxy 127.0.0.1:10820"
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
            $btnActionSubText.Text = "Booting Core Engines"; DoEvents
            
            Remove-Item "$xrayDir\access.log" -ErrorAction SilentlyContinue
            Remove-Item "$xrayDir\error.log" -ErrorAction SilentlyContinue

            if (Test-Path "$haPath\haproxy.exe") { Start-Process -FilePath "$haPath\haproxy.exe" -ArgumentList "-f haproxy.cfg" -WorkingDirectory $haPath -WindowStyle $winStyle }
            Restart-Xray $mode
            
            $lblSocksTitle.Text = "Mixed Port:"
            $lblSocksDataIPs.Text = "127.0.0.1:10818`n$lanIp`:10818"
            $lblSocksDataTags.Text = "(Local)`n(LAN)"

            $global:isConnected = $true
            $btnActionMainText.Text = "CONNECTED"
            $btnActionSubText.Text = ""
            $btnActionMainText.Foreground = "#68D391"
            
            Start-GeoPing 
            Update-WaveAnimation -State "Connected"
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
            $action = New-ScheduledTaskAction -Execute "$global:baseDir\Launch Multiplexer.exe" -WorkingDirectory $global:baseDir
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
    $targetW = if ($script:isLogsOpen) { 913.0 } else { 605.0 }
    $targetH = if ($script:isAdvancedOpen) { 547.0 } else { 295.0 }
    
    $advOpac = if ($script:isAdvancedOpen) { 1.0 } else { 0.0 }
    $logOpac = if ($script:isLogsOpen) { 1.0 } else { 0.0 }
    
    $panelTop = if ($script:isAdvancedOpen) { 432.0 } else { 180.0 }
    $logsH = if ($script:isAdvancedOpen) { 477.0 } else { 225.0 }
    $xrayH = if ($script:isAdvancedOpen) { 327.0 } else { 75.0 }

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
    $UnifiedPanel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, $slideAnim)

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
# --- LOG AUTO-CLEANER (2 HOURS) ---
$logClearTimer = New-Object System.Windows.Threading.DispatcherTimer
$logClearTimer.Interval = [TimeSpan]::FromHours(2)
$logClearTimer.add_Tick({
    try {
        if (Test-Path "$xrayDir\access.log") { 
            $fs = New-Object System.IO.FileStream("$xrayDir\access.log", [System.IO.FileMode]::Truncate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            $fs.Close()
        }
        if (Test-Path "$xrayDir\error.log") { 
            $fs = New-Object System.IO.FileStream("$xrayDir\error.log", [System.IO.FileMode]::Truncate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            $fs.Close()
        }
    } catch {
        Clear-Content "$xrayDir\access.log" -ErrorAction SilentlyContinue
        Clear-Content "$xrayDir\error.log" -ErrorAction SilentlyContinue
    }
})
$logClearTimer.Start()

# --- EVENT BINDINGS ---
# --- SYSTEM TRAY ICON ENGINE ---
if (Test-Path "$global:baseDir\icon.ico") {
    $global:sysTrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $global:sysTrayIcon.Icon = New-Object System.Drawing.Icon("$global:baseDir\icon.ico")
    $global:sysTrayIcon.Text = "Tor Multiplexer"
    $global:sysTrayIcon.Visible = $true

    # Double-click the tray icon to pop the window back up safely
    $global:sysTrayIcon.add_DoubleClick({
        $form.Dispatcher.Invoke([System.Action]{
            $form.ShowInTaskbar = $true
            $form.WindowState = [System.Windows.WindowState]::Normal
            $form.Activate() | Out-Null
        })
    })

    # Create a clean Right-Click Menu for the tray icon
    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $menuShow = $trayMenu.Items.Add("Show Window")
    $menuExit = $trayMenu.Items.Add("Exit Application")

    # Right-click -> Show Window action
    $menuShow.add_Click({
        $form.Dispatcher.Invoke([System.Action]{
            $form.ShowInTaskbar = $true
            $form.WindowState = [System.Windows.WindowState]::Normal
            $form.Activate() | Out-Null
        })
    })

    # Right-click -> Exit Application action
    $menuExit.add_Click({
        $form.Dispatcher.Invoke([System.Action]{
            $form.Close()
        })
    })

    $global:sysTrayIcon.ContextMenuStrip = $trayMenu
}

# --- MINIMIZE TO TRAY HANDLER ---
$form.add_StateChanged({
    if ($form.WindowState -eq [System.Windows.WindowState]::Minimized) {
        if ($global:minimizeToTray) {
            # Stealth mode: Remove from taskbar entirely
            $form.ShowInTaskbar = $false
        } else {
            # Normal mode: Force it to stay visible on the windows taskbar
            $form.ShowInTaskbar = $true
        }
    }
})

# --- EVENT BINDINGS FOR THE TOGGLE ---
$btnTrayTog.add_Click({
    $global:minimizeToTray = -not $global:minimizeToTray
    Set-WpfToggleState $btnTrayTog $global:minimizeToTray
    Save-Config
})

$btnTrayLbl.add_Click({ $btnTrayTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$comboBridge.add_SelectionChanged({
    if ($comboBridge.SelectedItem.Tag -eq "Custom") { if (-not (Show-CustomBridgeDialog)) { Set-ComboSelectedTag $comboBridge $global:previousBridge } else { $global:previousBridge = "Custom" } } else { $global:previousBridge = $comboBridge.SelectedItem.Tag }
    Save-Config
})

$btnStatsPanel.add_Click({
    if ($global:isConnected) {
        Start-GeoPing
    }
})

$comboConfig.add_SelectionChanged({ 
    if ($comboConfig.SelectedItem.Tag -eq "Custom") { 
        if (-not (Show-ExitNodeDialog)) { 
            Set-ComboSelectedTag $comboConfig $global:previousConfig 
        } else { 
            $global:previousConfig = "Custom" 
        } 
    } else { 
        $global:previousConfig = $comboConfig.SelectedItem.Tag 
    }
    Save-Config 
})

$comboCount.add_SelectionChanged({ Save-Config })

$btnAction.add_Click({ if ($global:isConnected -or $btnActionMainText.Text -eq "CONNECTING") { Stop-AllEngines } else { Start-Engines } })
$btnUpdate.add_Click({ Update-Application })

$btnDesktop.add_Click({
    $deskFolder = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $deskFolder "TorMultiplexer.lnk"
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = Join-Path $global:baseDir "Launch Multiplexer.exe"
        $Shortcut.WorkingDirectory = $global:baseDir
        $Shortcut.Save()
        
        [System.Windows.Forms.MessageBox]::Show("Desktop shortcut created successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch { 
        [System.Windows.Forms.MessageBox]::Show("Failed to create Desktop shortcut.`n" + $_.Exception.Message, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null 
    }
})


$btnGithub.add_Click({ Start-Process "https://github.com/RichTiTAN/Tor-Multiplexer" })
$btnTelegram.add_Click({ Start-Process "https://t.me/itsTitanVPN" })

$btnAutoStartTog.add_Click({ $script:autoStart = -not $script:autoStart; Set-WpfToggleState $btnAutoStartTog $script:autoStart; Save-Config })
$btnAutoStartLbl.add_Click({ $btnAutoStartTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

$btnDirectTog.add_Click({ $global:enableDirect = -not $global:enableDirect; Set-WpfToggleState $btnDirectTog $global:enableDirect; Save-Config; if ($global:isConnected) { Restart-Xray $global:lastXrayMode } })
$btnDirectConfig.add_Click({ if (Show-DirectRulesDialog) { Save-Config; if ($global:isConnected) { Restart-Xray $global:lastXrayMode } } })

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

$btnDohTog.add_Click({
    if ($global:isConnected) {
        [System.Windows.Forms.MessageBox]::Show("You cannot change DNS rules while connected. Please disconnect first.", "Action Denied", 0, 48)
        return
    }
    if ($global:enableTorDoh -or $global:enableUpstreamDoh) {
        $global:enableTorDoh = $false; $global:enableUpstreamDoh = $false
        Set-WpfToggleState $btnDohTog $false; Save-Config; Evaluate-ProxyExclusivity
    } else {
        if (-not (Show-DohDialog)) { Set-WpfToggleState $btnDohTog $false } else { Set-WpfToggleState $btnDohTog ($global:enableTorDoh -or $global:enableUpstreamDoh); Save-Config; Evaluate-ProxyExclusivity }
    }
})
$btnDohConfig.add_Click({ Show-DohDialog | Out-Null; Set-WpfToggleState $btnDohTog ($global:enableTorDoh -or $global:enableUpstreamDoh); Save-Config; Evaluate-ProxyExclusivity })

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
$btnCloseLogs.add_Click({
    if ($script:isLogsOpen) {
        $btnLogsTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

$toggleAction = {
    param($mode); if ($global:lastXrayMode -ne $mode) {
        $global:lastXrayMode = $mode; Update-RoutingToggle
        Save-Config
        if ($global:isConnected) { Restart-Xray $mode }
    }
}
$btnProxyMode.add_Click({ &$toggleAction "Proxy Mode" })
$btnClearProxy.add_Click({ &$toggleAction "Clear Proxy" })
$btnVpnMode.add_Click({ &$toggleAction "VPN Mode" })

$form.add_Closing({ 
    Stop-AllEngines $true 
    
    # Clean up the system tray icon instantly so it disappears on exit
    if ($global:sysTrayIcon) {
        $global:sysTrayIcon.Visible = $false
        $global:sysTrayIcon.Dispose()
    }
})
$form.add_Closed({ [Environment]::Exit(0) })

# --- AD BLOCKER INTERACTION TRIGGERS ---
$btnAdBlockTog.add_Click({
    $global:enableAdBlock = -not $global:enableAdBlock
    Set-WpfToggleState $btnAdBlockTog $global:enableAdBlock
    Save-Config
    # Live hot-swap if the proxy core engine is active
    if ($global:isConnected) { Restart-Xray $global:lastXrayMode }
})
$btnAdBlockLbl.add_Click({ $btnAdBlockTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

# Safe Auto-Boot Timer & Missing Components Dialog
$form.add_ContentRendered({ 
    if ($global:appInitialized) { return }
    $global:appInitialized = $true
    Check-UpdateSilent 

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
Update-WaveAnimation -State "Idle"

$form.ShowDialog() | Out-Null