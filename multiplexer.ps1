Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# ASSEMBLIES
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::Default
[System.AppDomain]::CurrentDomain.add_ProcessExit({
    Stop-AllEngines -isClosing $true
    Disable-SystemProxy
})

# WINDOWS NATIVE DARK TITLE BAR API
try {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class DWM {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
        public static void DarkTitleBar(IntPtr hwnd) {
            try {
                int useImmersiveDarkMode = 1;
                DwmSetWindowAttribute(hwnd, 20, ref useImmersiveDarkMode, sizeof(int));
                DwmSetWindowAttribute(hwnd, 19, ref useImmersiveDarkMode, sizeof(int));
            } catch {}
        }
    }
"@
} catch {}

# SYSTEM PROXY REFRESH API
if (-not ("Win32.WinInet" -as [type])) {
    Add-Type -MemberDefinition @'
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
'@ -Name 'WinInet' -Namespace 'Win32' -PassThru | Out-Null
}

#  LEGACY UPDATE STUBS 
$global:currentVersion       = "5.1.2" 
$global:forceManualUpdate    = $true
$global:minAutoUpdateVersion = "5.1.0"

#  CENTRAL APP STATE 
$App = [ordered]@{
    # Persisted + path config
    Config = [ordered]@{
        currentVersion       = "5.1.2"
        minAutoUpdateVersion = "5.1.0"
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
        enableTorDoh         = $false
        torDohUrl            = "https://cloudflare-dns.com/dns-query"
        enableUpstreamDoh    = $false
        upstreamDohUrl       = "https://cloudflare-dns.com/dns-query"
        customExitCountry    = "us"
        minimizeToTray       = $false
        enableAdBlock        = $false
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
        isFetchingStats   = $false
        statsWebClient    = $null
        statsTimer        = $null
        wavePhysicsTimer  = $null
        waveHoldTimer     = $null
        pingTimer         = $null
        hideAdvTimer      = $null
        hideLogTimer      = $null
        geoSw             = $null
        sysTrayIcon       = $null
        waveX1            = 0.0
        waveX2            = -75.0
        waveCurrentSpeed1 = 0.4
        waveCurrentSpeed2 = 0.5
        waveTargetSpeed1  = 0.4
        waveTargetSpeed2  = 0.5
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
        waveBrush1           = $null
        waveBrush2           = $null
        comboBridge          = $null
        comboConfig          = $null
        comboCount           = $null
        btnAction            = $null
        btnActionMainText    = $null
        btnActionSubText     = $null
        wavePath1            = $null
        wavePath2            = $null
        waveTrans1           = $null
        waveTrans2           = $null
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
    }
}

#  PATH SETUP
$App.Config.baseDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($App.Config.baseDir)) { $App.Config.baseDir = Get-Location }
Set-Location $App.Config.baseDir

function Get-AppPath {
    param([string]$Path)
    Join-Path $App.Config.baseDir $Path
}

$App.Config.scriptPath = $PSCommandPath
if ([string]::IsNullOrEmpty($App.Config.scriptPath)) { $App.Config.scriptPath = Get-AppPath "multiplexer.ps1" }
$App.Config.cfgFile    = Get-AppPath "multiplexer_settings.json"
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
        
        $cfgMap = @{
            "LastConfig"           = "lastConfig"
            "SelectedBridge"       = "lastBridge"
            "InstanceCount"        = "lastCount"
            "XrayMode"             = "lastXrayMode"
            "ManualSplit"          = "lastManualSplit"
            "AppSplit"             = "lastAppSplit"
            "BlockSplit"           = "lastBlockSplit"
            "EnableDirect"         = "enableDirect"
            "CustomBridgeLine"     = "customBridgeLine"
            "V2rayChainJson"       = "v2rayChainJson"
            "EnableV2rayChain"     = "enableV2rayChain"
            "EnableOutboundProxy"  = "enableOutboundProxy"
            "OutboundProxyAddress" = "outboundProxyAddress"
            "OutboundProxyPort"    = "outboundProxyPort"
            "OutboundProxyType"    = "outboundProxyType"
            "OutboundProxyUser"    = "outboundProxyUser"
            "OutboundProxyPass"    = "outboundProxyPass"
            "EnableOutboundAuth"   = "enableOutboundAuth"
            "EnableTorDoh"         = "enableTorDoh"
            "TorDohUrl"            = "torDohUrl"
            "EnableUpstreamDoh"    = "enableUpstreamDoh"
            "UpstreamDohUrl"       = "upstreamDohUrl"
            "CustomExitCountry"    = "customExitCountry"
            "MinimizeToTray"       = "minimizeToTray"
            "EnableAdBlock"        = "enableAdBlock"
        }
        
        foreach ($key in $cfgMap.Keys) {
            if ($null -ne $s.$key) { $App.Config[$cfgMap[$key]] = $s.$key }
        }
        if ($App.Config.lastConfig -eq "Stable" -or $App.Config.lastConfig -eq "Fast") {
            $App.Config.lastConfig = "Optimized"
        }
    } catch {
        Write-Host "Config Load Error: $($_.Exception.Message)"
    }
}

# LAN IP
$_ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
        Where-Object { $_.AddressFamily -eq 'InterNetwork' -and
                       $_.ToString() -notmatch '^127\.' -and
                       $_.ToString() -notmatch '^169\.254\.' }
if ($_ips) { $App.State.lanIp = $_ips[0].ToString() }

#  SHARED DIALOG XAML RESOURCES
$sharedDialogResources = @"
    <Window.Resources>
        <SolidColorBrush x:Key="BgDark"    Color="#1A1A1B"/>
        <SolidColorBrush x:Key="BgPanel"   Color="#121417"/>
        <SolidColorBrush x:Key="BgInput"   Color="#0A0C0F"/>
        <SolidColorBrush x:Key="BorderMain"  Color="#2D3748"/>
        <SolidColorBrush x:Key="BorderLight" Color="#3A3F44"/>
        <SolidColorBrush x:Key="TextMain"  Color="#E2E8F0"/>
        <SolidColorBrush x:Key="TextMuted" Color="#A0AEC0"/>
        <SolidColorBrush x:Key="TextGreen" Color="#68D391"/>
        <SolidColorBrush x:Key="ColorOk"   Color="#4E7A5E"/>
        <SolidColorBrush x:Key="ColorHover" Color="#5F9774"/>
        <SolidColorBrush x:Key="BtnStandard" Color="#3A3F44"/>
        <SolidColorBrush x:Key="BtnHover"  Color="#4A5568"/>
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource BtnStandard}"/>
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
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
                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource BtnHover}"/></Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="Button" x:Key="SaveButton" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{StaticResource ColorOk}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource ColorHover}"/></Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="Button" x:Key="DialogTogFlat" BasedOn="{StaticResource {x:Type Button}}">
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
        <Style TargetType="Button" x:Key="DialogTogRight" BasedOn="{StaticResource {x:Type Button}}">
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
        <Style TargetType="ComboBox" x:Key="DarkComboBox">
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
            <Setter Property="Background" Value="{StaticResource BgInput}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderMain}"/>
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
                                <Path Fill="{StaticResource TextMuted}" Data="M0,0 L4,4 L8,0 Z" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,5,0"/>
                            </ToggleButton>
                            <ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="8,0,23,2" VerticalAlignment="Center" HorizontalAlignment="Left">
                                <ContentPresenter.Resources>
                                    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource TextGreen}"/></Style>
                                </ContentPresenter.Resources>
                            </ContentPresenter>
                            <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Border Name="DropDownBorder" Background="#1A202C" BorderThickness="1" BorderBrush="{StaticResource BorderLight}" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="150">
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
        <Style TargetType="ComboBox" x:Key="DarkComboBoxJoined">
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
            <Setter Property="Background" Value="{StaticResource BgInput}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderMain}"/>
            <Setter Property="BorderThickness" Value="0,1,1,1"/>
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
                                <Path Fill="{StaticResource TextMuted}" Data="M0,0 L4,4 L8,0 Z" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,5,0"/>
                            </ToggleButton>
                            <ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="8,0,23,2" VerticalAlignment="Center" HorizontalAlignment="Left">
                                <ContentPresenter.Resources>
                                    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource TextGreen}"/></Style>
                                </ContentPresenter.Resources>
                            </ContentPresenter>
                            <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Border Name="DropDownBorder" Background="#1A202C" BorderThickness="1" BorderBrush="{StaticResource BorderLight}" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="150">
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
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
            <Setter Property="Padding" Value="4,2"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource BtnHover}"/></Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>
"@

#  DIALOG HELPER
function Show-AppDialog {
    param([string]$Title, [int]$Width, [int]$Height, [string]$InnerXaml,
          [scriptblock]$OnLoad, [scriptblock]$OnSave)
    $bW = $Width - 30
    $bH = $Height - 54
    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="$Title" Height="$Height" Width="$Width"
            WindowStartupLocation="CenterOwner" Background="#1A1A1B" Foreground="#E2E8F0"
            ResizeMode="NoResize" FontFamily="Segoe UI" ShowInTaskbar="False">
        $sharedDialogResources
        <Canvas>
            <Border Name="borderMain" Canvas.Left="12" Canvas.Top="12" Width="$bW" Height="$bH"
                    Background="{StaticResource BgPanel}" CornerRadius="4"
                    BorderBrush="{StaticResource BorderMain}" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="$Title" Canvas.Left="15" Canvas.Top="12"
                               FontSize="10" Foreground="{StaticResource TextMuted}" FontWeight="Bold"/>
                    $InnerXaml
                </Canvas>
            </Border>
        </Canvas>
    </Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    $dlg.Owner = $App.UI.form
    $dlg.Add_SourceInitialized({
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($dlg)).Handle
            [DWM]::DarkTitleBar($hwnd)
        } catch {}
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
    
    $dlg.Add_Loaded({ if ($null -ne $OnLoad) { & $OnLoad $dlg } }.GetNewClosure())
    return $dlg.ShowDialog() -eq $true
}

#  MAIN WINDOW XAML
$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Tor Multiplexer" Height="340" Width="595"
    WindowStartupLocation="CenterScreen" Background="#000000" Foreground="#E2E8F0"
    ResizeMode="CanMinimize" FontFamily="Segoe UI">
    <Window.Triggers>
        <EventTrigger RoutedEvent="Window.Loaded">
            <BeginStoryboard>
                <Storyboard>
                    <ColorAnimationUsingKeyFrames Storyboard.TargetName="bgGlow" Storyboard.TargetProperty="Color" Duration="0:1:0" RepeatBehavior="Forever" AutoReverse="True">
                        <EasingColorKeyFrame Value="#803A70B0" KeyTime="0:0:0"/>
                        <EasingColorKeyFrame Value="#807030A0" KeyTime="0:0:20"/>
                        <EasingColorKeyFrame Value="#80A03030" KeyTime="0:0:40"/>
                        <EasingColorKeyFrame Value="#803A70B0" KeyTime="0:1:0"/>
                    </ColorAnimationUsingKeyFrames>
                    <DoubleAnimationUsingKeyFrames Storyboard.TargetName="bgTransform" Storyboard.TargetProperty="X" Duration="0:0:45" RepeatBehavior="Forever" AutoReverse="True">
                        <EasingDoubleKeyFrame Value="0"    KeyTime="0:0:0"/>
                        <EasingDoubleKeyFrame Value="250"  KeyTime="0:0:15"/>
                        <EasingDoubleKeyFrame Value="50"   KeyTime="0:0:30"/>
                        <EasingDoubleKeyFrame Value="-100" KeyTime="0:0:45"/>
                    </DoubleAnimationUsingKeyFrames>
                    <DoubleAnimationUsingKeyFrames Storyboard.TargetName="bgTransform" Storyboard.TargetProperty="Y" Duration="0:0:45" RepeatBehavior="Forever" AutoReverse="True">
                        <EasingDoubleKeyFrame Value="0"   KeyTime="0:0:0"/>
                        <EasingDoubleKeyFrame Value="150" KeyTime="0:0:20"/>
                        <EasingDoubleKeyFrame Value="-50" KeyTime="0:0:35"/>
                        <EasingDoubleKeyFrame Value="80"  KeyTime="0:0:45"/>
                    </DoubleAnimationUsingKeyFrames>
                </Storyboard>
            </BeginStoryboard>
        </EventTrigger>
    </Window.Triggers>
    <Window.Resources>
        <Style TargetType="ComboBox" x:Key="DarkComboBox">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="Background" Value="#121417"/>
            <Setter Property="BorderBrush" Value="#3A3F44"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton Name="ToggleButton" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Focusable="False" Cursor="Hand" IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Grid>
                                            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="0,4,4,0"/>
                                            <Border x:Name="HoverOverlay" Background="Transparent" CornerRadius="0,4,4,0"/>
                                            <ContentPresenter HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,5,0"/>
                                        </Grid>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="HoverOverlay" Property="Background" Value="#1AFFFFFF"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                                <Path Fill="#A0AEC0" Data="M0,0 L4,4 L8,0 Z" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,5,0"/>
                            </ToggleButton>
                            <ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" Margin="8,0,23,2" VerticalAlignment="Center" HorizontalAlignment="Left">
                                <ContentPresenter.Resources>
                                    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#E2E8F0"/></Style>
                                </ContentPresenter.Resources>
                            </ContentPresenter>
                            <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Border Name="DropDownBorder" Background="#121417" BorderThickness="1" BorderBrush="#3A3F44" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="300">
                                    <ScrollViewer Margin="0,2" SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
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
                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#646B75"/></Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="Border" x:Key="AdvancedRowStyle">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="CornerRadius" Value="4"/>
            <Setter Property="Margin" Value="0,1,0,-1"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#1AFFFFFF"/>
                </Trigger>            </Style.Triggers>
        </Style>
        <Style TargetType="Button" x:Key="AdvancedTextStyle">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="10"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="#A0AEC0"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Padding" Value="10,0,0,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="Transparent">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <DataTrigger Binding="{Binding IsMouseOver, RelativeSource={RelativeSource AncestorType=Border}}" Value="True">
                    <Setter Property="Foreground" Value="#E2E8F0"/>
                </DataTrigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="Button" x:Key="AdvancedToggleStyle">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="10"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalAlignment" Value="Right"/>
            <Setter Property="Width" Value="60"/>
            <Setter Property="Height" Value="20"/>
            <Setter Property="Margin" Value="0,3,5,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="InnerBorder" Background="Transparent" CornerRadius="4" Margin="1">
                            <Border.RenderTransform><TranslateTransform Y="-0.5"/></Border.RenderTransform>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="InnerBorder" Property="Background" Value="#25FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Canvas>
        <Ellipse x:Name="MovingGlow" Width="800" Height="800" Canvas.Left="50" Canvas.Top="-50" IsHitTestVisible="False">
            <Ellipse.Effect><BlurEffect Radius="80" KernelType="Gaussian"/></Ellipse.Effect>
            <Ellipse.Fill>
                <RadialGradientBrush>
                    <GradientStop x:Name="bgGlow" Color="#601A3A6A" Offset="0"/>
                    <GradientStop Color="#001A1A1B" Offset="1"/>
                </RadialGradientBrush>
            </Ellipse.Fill>
            <Ellipse.RenderTransform><TranslateTransform x:Name="bgTransform" X="0" Y="0"/></Ellipse.RenderTransform>
        </Ellipse>
        <Border Background="#8C121417" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4" Canvas.Left="20" Canvas.Top="15" Width="550" Height="200">
            <Canvas>
                <!-- TITLE BAR -->
                <Button Name="btnTitleUpdate" Canvas.Left="0" Canvas.Top="0" Width="548" Height="25" Cursor="Hand" Background="Transparent" BorderThickness="0">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="TitleBorder" Background="#990A0C0F" CornerRadius="3,3,0,0" BorderBrush="#2D3748" BorderThickness="0,0,0,1">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="TitleBorder" Property="Background" Value="#25FFFFFF"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                    <TextBlock Name="lblTitleText" Text="TOR MULTIPLEXER" FontSize="10" FontWeight="Bold" Foreground="#718096" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                </Button>
                <!-- ROW: combos -->
                <Border BorderBrush="#3A3F44" BorderThickness="1" CornerRadius="4,0,0,4" Canvas.Left="15" Canvas.Top="38" Width="80" Height="26">
                    <TextBlock Text="BRIDGE TYPE" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                </Border>
                <ComboBox Name="comboBridge" Canvas.Left="95" Canvas.Top="38" Width="85" Height="26" FontSize="11" BorderThickness="0,1,1,1" Style="{StaticResource DarkComboBox}"/>
                <Border BorderBrush="#3A3F44" BorderThickness="1" CornerRadius="4,0,0,4" Canvas.Left="195" Canvas.Top="38" Width="80" Height="26">
                    <TextBlock Text="ROUTING" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                </Border>
                <ComboBox Name="comboConfig" Canvas.Left="275" Canvas.Top="38" Width="85" Height="26" FontSize="11" BorderThickness="0,1,1,1" Style="{StaticResource DarkComboBox}"/>
                <Border BorderBrush="#3A3F44" BorderThickness="1" CornerRadius="4,0,0,4" Canvas.Left="375" Canvas.Top="38" Width="80" Height="26">
                    <TextBlock Text="TOR ENGINES" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                </Border>
                <ComboBox Name="comboCount" Canvas.Left="455" Canvas.Top="38" Width="80" Height="26" FontSize="11" BorderThickness="0,1,1,1" Style="{StaticResource DarkComboBox}"/>
                <Rectangle Canvas.Left="0" Canvas.Top="79" Width="550" Height="1" Fill="#2D3748"/>
                <!-- LEFT PANEL: session / auto-connect / advanced -->
                <Border BorderBrush="#3A3F44" BorderThickness="1" CornerRadius="4" Canvas.Left="15" Canvas.Top="96" Width="210" Height="84" Background="Transparent">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="1"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="1"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <TextBlock Name="lblSessionTime" Text="SESSION: OFFLINE" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                        <Rectangle Grid.Row="1" Fill="#3A3F44" VerticalAlignment="Stretch"/>
                        <Button Name="btnAutoStartMain" Grid.Row="2" Background="Transparent" Cursor="Hand">
                            <Button.Style>
                                <Style TargetType="Button">
                                    <Setter Property="Background" Value="Transparent"/>
                                    <Setter Property="Template">
                                        <Setter.Value>
                                            <ControlTemplate TargetType="Button">
                                                <Grid>
                                                    <Border Background="{TemplateBinding Background}"/>
                                                    <Border x:Name="HoverOverlay" Background="Transparent"/>
                                                    <Grid HorizontalAlignment="Center" VerticalAlignment="Center">
                                                        <TextBlock x:Name="txtAutoConnect" Text="AUTO-CONNECT" FontSize="10" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center">
                                                            <TextBlock.Foreground><SolidColorBrush Color="#A0AEC0"/></TextBlock.Foreground>
                                                            <TextBlock.RenderTransform><TranslateTransform x:Name="transAutoConnect" X="0"/></TextBlock.RenderTransform>
                                                        </TextBlock>
                                                        <TextBlock x:Name="txtOn" Text="ON" FontSize="10" FontWeight="Bold" Foreground="#68D391" HorizontalAlignment="Center" VerticalAlignment="Center" Panel.ZIndex="-1" Opacity="0">
                                                            <TextBlock.RenderTransform><TranslateTransform x:Name="transOn" X="0"/></TextBlock.RenderTransform>
                                                        </TextBlock>
                                                    </Grid>
                                                </Grid>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="HoverOverlay" Property="Background" Value="#1AFFFFFF"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Setter.Value>
                                    </Setter>
                                </Style>
                            </Button.Style>
                        </Button>
                        <Rectangle Grid.Row="3" Fill="#3A3F44" VerticalAlignment="Stretch"/>
                        <Button Name="btnAdvMain" Grid.Row="4" Background="Transparent" Cursor="Hand">
                            <Button.Style>
                                <Style TargetType="Button">
                                    <Setter Property="Background" Value="Transparent"/>
                                    <Setter Property="Template">
                                        <Setter.Value>
                                            <ControlTemplate TargetType="Button">
                                                <Grid>
                                                    <Border Background="{TemplateBinding Background}"/>
                                                    <Border x:Name="HoverOverlay" Background="Transparent"/>
                                                    <TextBlock x:Name="txtAdv" Text="ADVANCED SETTINGS" FontSize="10" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center">
                                                        <TextBlock.Foreground><SolidColorBrush Color="#A0AEC0"/></TextBlock.Foreground>
                                                    </TextBlock>
                                                </Grid>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="HoverOverlay" Property="Background" Value="#1AFFFFFF"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Setter.Value>
                                    </Setter>
                                </Style>
                            </Button.Style>
                        </Button>
                    </Grid>
                </Border>
                <!-- RIGHT PANEL: mode tabs + connect button -->
                <Border BorderBrush="#3A3F44" BorderThickness="1" CornerRadius="4" Canvas.Left="239" Canvas.Top="96" Width="296" Height="84" Background="Transparent">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="28"/>
                            <RowDefinition Height="1"/>
                            <RowDefinition Height="55"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="1"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="1"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Name="btnProxyMode" Grid.Row="0" Grid.Column="0" Content="PROXY MODE" FontSize="10" FontWeight="Bold" Foreground="#FFFFFF">
                            <Button.Style>
                                <Style TargetType="Button">
                                    <Setter Property="Background" Value="#80646B75"/>
                                    <Setter Property="Cursor" Value="Hand"/>
                                    <Setter Property="Template">
                                        <Setter.Value>
                                            <ControlTemplate TargetType="Button">
                                                <Grid>
                                                    <Border Background="{TemplateBinding Background}" CornerRadius="4,0,0,0"/>
                                                    <Border x:Name="HoverOverlay" Background="Transparent" CornerRadius="4,0,0,0"/>
                                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                                </Grid>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="HoverOverlay" Property="Background" Value="#1AFFFFFF"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Setter.Value>
                                    </Setter>
                                </Style>
                            </Button.Style>
                            <Button.ToolTip><ToolTip Content="Enable a system-wide proxy that will route your apps through proxy." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                        </Button>
                        <Rectangle Grid.Row="0" Grid.Column="1" Fill="#3A3F44" VerticalAlignment="Stretch"/>
                        <Button Name="btnVpnMode" Grid.Row="0" Grid.Column="2" Content="VPN MODE" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0">
                            <Button.Style>
                                <Style TargetType="Button">
                                    <Setter Property="Background" Value="Transparent"/>
                                    <Setter Property="Cursor" Value="Hand"/>
                                    <Setter Property="Template">
                                        <Setter.Value>
                                            <ControlTemplate TargetType="Button">
                                                <Grid>
                                                    <Border Background="{TemplateBinding Background}"/>
                                                    <Border x:Name="HoverOverlay" Background="Transparent"/>
                                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                                </Grid>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="HoverOverlay" Property="Background" Value="#1AFFFFFF"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Setter.Value>
                                    </Setter>
                                </Style>
                            </Button.Style>
                            <Button.ToolTip>
                                <ToolTip Name="vpnToolTip" Content="Route your entire system's network globally through the secure tunnel." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/>
                            </Button.ToolTip>
                        </Button>
                        <Rectangle Grid.Row="0" Grid.Column="3" Fill="#3A3F44" VerticalAlignment="Stretch"/>
                        <Button Name="btnClearProxy" Grid.Row="0" Grid.Column="4" Content="CLEAR PROXY" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0">
                            <Button.Style>
                                <Style TargetType="Button">
                                    <Setter Property="Background" Value="Transparent"/>
                                    <Setter Property="Cursor" Value="Hand"/>
                                    <Setter Property="Template">
                                        <Setter.Value>
                                            <ControlTemplate TargetType="Button">
                                                <Grid>
                                                    <Border Background="{TemplateBinding Background}" CornerRadius="0,4,0,0"/>
                                                    <Border x:Name="HoverOverlay" Background="Transparent" CornerRadius="0,4,0,0"/>
                                                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                                </Grid>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="HoverOverlay" Property="Background" Value="#1AFFFFFF"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Setter.Value>
                                    </Setter>
                                </Style>
                            </Button.Style>
                            <Button.ToolTip><ToolTip Content="Restore your normal Internet connection while having a proxy open on port 10818." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                        </Button>
                        <Rectangle Grid.Row="1" Grid.ColumnSpan="5" Fill="#3A3F44" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>
                        <Grid Grid.Row="2" Grid.ColumnSpan="5">
                            <Grid.Clip>
                                <PathGeometry Figures="M 0,0 L 294,0 L 294,51 A 4,4 0 0 1 290,55 L 4,55 A 4,4 0 0 1 0,51 Z"/>
                            </Grid.Clip>
                            <Border Background="#A6121417" CornerRadius="0,0,4,4">
                                <Grid HorizontalAlignment="Stretch" VerticalAlignment="Stretch">
                                    <Canvas Background="Transparent" IsHitTestVisible="False">
                                        <Path Name="wavePath1" Data="M 0,26 C 75,-4 75,56 150,26 C 225,-4 225,56 300,26 C 375,-4 375,56 450,26 C 525,-4 525,56 600,26 L 600,80 L 0,80 Z" Fill="#25718096" Height="80" Width="600" Canvas.Top="0">
                                            <Path.RenderTransform><TranslateTransform x:Name="waveTrans1" X="0" Y="0"/></Path.RenderTransform>
                                        </Path>
                                        <Path Name="wavePath2" Data="M 0,28 C 60,-2 90,58 150,28 C 210,-2 240,58 300,28 C 360,-2 390,58 450,28 C 510,-2 540,58 600,28 L 600,80 L 0,80 Z" Fill="#15718096" Height="80" Width="600" Canvas.Top="0">
                                            <Path.RenderTransform><TranslateTransform x:Name="waveTrans2" X="-75" Y="0"/></Path.RenderTransform>
                                        </Path>
                                    </Canvas>
                                    <Grid IsHitTestVisible="False" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">
                                        <Grid.Effect>
                                            <DropShadowEffect Color="#000000" BlurRadius="15" ShadowDepth="1.0" Direction="270" Opacity="0.65"/>
                                        </Grid.Effect>
                                        <TextBlock Name="btnActionMainText" Text="CONNECT" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-5,0,0"/>
                                        <TextBlock Name="btnActionSubText" FontSize="10" FontFamily="Consolas" FontWeight="Bold" Foreground="#718096" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,3"/>
                                    </Grid>
                                    <Button Name="btnAction" Background="Transparent" Cursor="Hand" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">
                                        <Button.Template>
                                            <ControlTemplate TargetType="Button">
                                                <Border x:Name="HoverOverlay" Background="Transparent" CornerRadius="0,0,4,4"/>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="HoverOverlay" Property="Background" Value="#1AFFFFFF"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Button.Template>
                                    </Button>
                                </Grid>
                            </Border>
                        </Grid>
                    </Grid>
                </Border>
            </Canvas>
        </Border>
        <!-- STATUS BAR -->
        <Border Name="UnifiedPanel" Canvas.Left="20" Canvas.Top="230" Width="550" Height="65" Background="#8C121417" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4">
            <Canvas>
                <TextBlock Name="lblSocksTitle"   Text="MIXED PORT"               Canvas.Left="10"  Canvas.Top="10" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0"/>
                <TextBlock Name="lblSocksDataIPs" Text="Waiting for connection..." Canvas.Left="10"  Canvas.Top="26" FontSize="12" FontFamily="Consolas" FontWeight="Bold" Foreground="#68D391"/>
                <TextBlock Name="lblSocksDataTags" Text=""                          Canvas.Left="200" Canvas.Top="26" FontSize="12" FontFamily="Consolas" FontWeight="Bold" Foreground="#68D391" TextAlignment="Right" Width="60"/>
                <Rectangle Canvas.Left="275" Canvas.Top="0" Width="1" Height="63" Fill="#2D3748"/>
                <TextBlock Name="lblStatsTitle" Text="STATS"                      Canvas.Left="285" Canvas.Top="10" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0"/>
                <TextBlock Name="lblStatsData"  Text="Speed: 0 KB/s&#x0a;Total: 0 MB" Canvas.Left="285" Canvas.Top="26" FontSize="12" FontFamily="Consolas" Foreground="#68D391" FontWeight="Bold"/>
                <TextBlock Name="lblGeoData"    Text="Loc: --&#x0a;Ping: --"     Canvas.Left="410" Canvas.Top="26" FontSize="12" FontFamily="Consolas" Foreground="#68D391" FontWeight="Bold"/>
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
                                <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#1AFFFFFF"/></Trigger>
                            </Style.Triggers>
                        </Style>
                    </Button.Style>
                </Button>
            </Canvas>
        </Border>
        <!-- ADVANCED SETTINGS PANEL -->
        <Canvas Name="AdvancedCanvas" Canvas.Left="0" Canvas.Top="205" Opacity="0" Visibility="Hidden">
            <Border Name="AdvancedBorder" Background="#8C121417" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4" ClipToBounds="True" Canvas.Left="20" Canvas.Top="25" Width="550" Height="194">
                <Canvas>
                    <Border Width="548" Height="26" Canvas.Left="0" Canvas.Top="0" Background="#990A0C0F" CornerRadius="3,3,0,0" BorderBrush="#2D3748" BorderThickness="0,0,0,1"/>
                    <TextBlock Text="ROUTING" Canvas.Left="0"   Canvas.Top="6" Width="275" TextAlignment="Center" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    <TextBlock Text="SYSTEM"  Canvas.Left="275" Canvas.Top="6" Width="275" TextAlignment="Center" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    <Rectangle Canvas.Left="275" Canvas.Top="0" Width="1" Height="194" Fill="#2D3748"/>
                    <!-- LEFT: routing toggles -->
                    <Border Canvas.Left="15" Canvas.Top="40" Width="245" Height="135" Background="Transparent" BorderThickness="0">
                        <StackPanel>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnDirectLbl" Content="SPLIT TUNNELING" Style="{StaticResource AdvancedTextStyle}">
                                        <Button.ToolTip><ToolTip Content="Bypass the proxy for specific websites or local IP addresses." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                                    </Button>
                                    <Button Name="btnDirectTog" Content="DISABLED" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnV2rayLbl" Content="CUSTOM V2RAY EXIT-NODE" Style="{StaticResource AdvancedTextStyle}">
                                        <Button.ToolTip><ToolTip Content="Force your traffic to exit through a specific geographic country." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                                    </Button>
                                    <Button Name="btnV2rayTog" Content="DISABLED" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnOutboundLbl" Content="OUTBOUND PROXY" Style="{StaticResource AdvancedTextStyle}">
                                        <Button.ToolTip><ToolTip Content="Route your Tor engines through an upstream SOCKS5/HTTPS proxy." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                                    </Button>
                                    <Button Name="btnOutboundTog" Content="DISABLED" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnDohLbl" Content="DNS SETTINGS" Style="{StaticResource AdvancedTextStyle}">
                                        <Button.ToolTip><ToolTip Content="Encrypt your initial DNS queries to hide your traffic from your ISP." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                                    </Button>
                                    <Button Name="btnDohTog" Content="DISABLED" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnAdBlockLbl" Content="AD AND TRACKER BLOCKER" Style="{StaticResource AdvancedTextStyle}">
                                        <Button.ToolTip><ToolTip Content="Block system-wide ads, trackers, and telemetry loops inside Xray." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                                    </Button>
                                    <Button Name="btnAdBlockTog" Content="DISABLED" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                        </StackPanel>
                    </Border>
                    <!-- RIGHT: system toggles -->
                    <Border Canvas.Left="290" Canvas.Top="40" Width="245" Height="135" Background="Transparent" BorderThickness="0">
                        <StackPanel>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnBootLbl" Content="LAUNCH ON START-UP" Style="{StaticResource AdvancedTextStyle}"/>
                                    <Button Name="btnBootTog" Content="DISABLED" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnDebugLbl" Content="DEBUG MODE" Style="{StaticResource AdvancedTextStyle}">
                                        <Button.ToolTip><ToolTip Content="Launch the background engines in visible console windows for troubleshooting." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                                    </Button>
                                    <Button Name="btnDebugTog" Content="DISABLED" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnTrayLbl" Content="MINIMIZE TO TRAY" Style="{StaticResource AdvancedTextStyle}">
                                        <Button.ToolTip><ToolTip Content="Hide the application into the system tray when minimized." Background="#1A202C" Foreground="#E2E8F0" BorderBrush="#2D3748"/></Button.ToolTip>
                                    </Button>
                                    <Button Name="btnTrayTog" Content="ENABLED" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnLogsLbl" Content="LIVE LOGS" Style="{StaticResource AdvancedTextStyle}"/>
                                    <Button Name="btnLogsTog" Content="SHOW" Foreground="#A0AEC0" Style="{StaticResource AdvancedToggleStyle}"/>
                                </Grid>
                            </Border>
                            <Border Style="{StaticResource AdvancedRowStyle}" Height="27">
                                <Grid Margin="0,-1,0,1">
                                    <Button Name="btnDesktop" Content="CREATE DESKTOP SHORTCUT" Style="{StaticResource AdvancedTextStyle}" HorizontalContentAlignment="Center" Padding="0"/>
                                </Grid>
                            </Border>
                        </StackPanel>
                    </Border>
                </Canvas>
            </Border>
        </Canvas>
        <!-- LOGS PANEL -->
        <Canvas Name="LogsCanvas" Canvas.Left="585" Canvas.Top="15" Width="300" Height="474" Visibility="Hidden" Opacity="0">
            <Border Name="logBorder" Background="#8C121417" Width="300" Height="474" CornerRadius="4" BorderBrush="#2D3748" BorderThickness="1">
                <Canvas>
                    <TextBlock Name="lblTorTitle" Text="TOR BOOTSTRAP STATUS" Canvas.Left="15" Canvas.Top="10" Foreground="#A0AEC0" FontSize="10" FontWeight="Bold"/>
                    <Button Name="btnCloseLogs" Canvas.Left="272" Canvas.Top="6" Width="22" Height="22" Content="&#x2715;" FontSize="10" FontWeight="Bold" Padding="0,-1,0,0">
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
                    <TextBlock Name="lblTor1" Text="Tor 01: Offline" Canvas.Left="15"  Canvas.Top="30"  Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor2" Text="Tor 02: Offline" Canvas.Left="15"  Canvas.Top="48"  Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor3" Text="Tor 03: Offline" Canvas.Left="15"  Canvas.Top="66"  Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor4" Text="Tor 04: Offline" Canvas.Left="15"  Canvas.Top="84"  Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor5" Text="Tor 05: Offline" Canvas.Left="155" Canvas.Top="30"  Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor6" Text="Tor 06: Offline" Canvas.Left="155" Canvas.Top="48"  Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor7" Text="Tor 07: Offline" Canvas.Left="155" Canvas.Top="66"  Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor8" Text="Tor 08: Offline" Canvas.Left="155" Canvas.Top="84"  Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <Rectangle Name="logSeparator" Canvas.Left="15" Canvas.Top="110" Width="270" Height="1" Fill="#2D3748"/>
                    <TextBlock Name="lblConnTitle" Text="CONNECTIONS" Canvas.Left="15" Canvas.Top="120" Foreground="#A0AEC0" FontSize="10" FontWeight="Bold"/>
                    <TextBox Name="txtXrayLogs" Canvas.Left="15" Canvas.Top="138" Width="270" Height="321"
                             Background="#990A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1"
                             FontSize="10" TextWrapping="Wrap" VerticalScrollBarVisibility="Hidden"
                             HorizontalScrollBarVisibility="Hidden" IsReadOnly="True" FontFamily="Consolas"/>
                </Canvas>
            </Border>
        </Canvas>
    </Canvas>
</Window>
"@

#  COMPILE XAML
try {
    $App.UI.form = [Windows.Markup.XamlReader]::Parse($xaml)
    $App.UI.form.Add_SourceInitialized({
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($App.UI.form)).Handle
            [DWM]::DarkTitleBar($hwnd)
        } catch {}
    })
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
    "wavePath1","wavePath2","waveTrans1","waveTrans2",
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
    "lblTitleText","btnTitleUpdate"
)
foreach ($n in $_names) { $App.UI[$n] = $App.UI.form.FindName($n) }
$App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)"

#  PRE-BUILD BRUSHES
$_bc = New-Object System.Windows.Media.BrushConverter
$App.UI.brGreen          = $_bc.ConvertFromString("#68D391")
$App.UI.brGray           = $_bc.ConvertFromString("#A0AEC0")
$App.UI.brRed            = $_bc.ConvertFromString("#E53E3E")
$App.UI.brWhite          = $_bc.ConvertFromString("#FFFFFF")
$App.UI.brTransparent    = [System.Windows.Media.Brushes]::Transparent
$App.UI.brActiveRouting  = $_bc.ConvertFromString("#80646B75")
$App.UI.brInactiveRouting = [System.Windows.Media.Brushes]::Transparent
$App.UI.waveBrush1 = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::DimGray)
$App.UI.waveBrush1.Opacity = 0.25
$App.UI.waveBrush2 = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::DimGray)
$App.UI.waveBrush2.Opacity = 0.15
$App.UI.wavePath1.Fill = $App.UI.waveBrush1
$App.UI.wavePath2.Fill = $App.UI.waveBrush2

#  COMBO BOX POPULATION
function Add-ComboItem($combo, $text, $tag) {
    $cbi = New-Object System.Windows.Controls.ComboBoxItem
    $cbi.Content = $text
    $cbi.Tag     = $tag
    if ($tag -eq "Custom") {
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
                } else { $App.State.previousBridge = "Custom" }
                Save-Config
                $App.State.ignoreComboChange = $false
            } elseif ($combo.Name -eq "comboConfig") {
                $App.State.ignoreComboChange = $true
                $combo.SelectedItem = $sender
                DoEvents
                if (-not (Show-ExitNodeDialog)) {
                    Set-ComboSelectedTag $combo $App.State.previousConfig
                } else { $App.State.previousConfig = "Custom" }
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
        plugin = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"
        lines  = @("Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN")
    }
    "obfs4" = @{
        plugin = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"
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
        plugin = "ClientTransportPlugin snowflake exec ..\..\PluggableTransports\lyrebird.exe"
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
        [System.Action]{ $frame.Continue = $false }
    ) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Wait-NonBlocking($s) {
    $end = (Get-Date).AddSeconds($s)
    while ((Get-Date) -lt $end) {
        if ($App.State.abortBoot) { return }
        DoEvents
        [System.Threading.Thread]::Sleep(10) 
    }
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
    $App.UI.btnVpnMode.Background    = $App.UI.brInactiveRouting
    $App.UI.btnVpnMode.Foreground    = $App.UI.brGray
    $App.UI.btnVpnMode.Cursor        = [System.Windows.Input.Cursors]::Hand
    $App.UI.vpnToolTip.Content       = "Route your entire system's network globally through the secure tunnel."
    $App.UI.vpnToolTip.Visibility    = "Visible"
    
    switch ($App.Config.lastXrayMode) {
        "Proxy Mode"  { $App.UI.btnProxyMode.Background  = $App.UI.brActiveRouting; $App.UI.btnProxyMode.Foreground  = $App.UI.brWhite }
        "VPN Mode"    { $App.UI.btnVpnMode.Background    = $App.UI.brActiveRouting; $App.UI.btnVpnMode.Foreground    = $App.UI.brWhite }
        "Clear Proxy" { $App.UI.btnClearProxy.Background = $App.UI.brActiveRouting; $App.UI.btnClearProxy.Foreground = $App.UI.brWhite }
    }
    
    $App.UI.btnDirectLbl.IsEnabled = $true; $App.UI.btnDirectLbl.Opacity = 1.0
    $App.UI.btnDirectTog.IsEnabled = $true; $App.UI.btnDirectTog.Opacity = 1.0
}

function Evaluate-ProxyExclusivity {
    $ok = -not $App.Config.enableTorDoh
    $App.UI.btnOutboundLbl.IsEnabled = $ok; $App.UI.btnOutboundLbl.Opacity = if ($ok) { 1.0 } else { 0.5 }
    $App.UI.btnOutboundTog.IsEnabled = $ok; $App.UI.btnOutboundTog.Opacity = if ($ok) { 1.0 } else { 0.5 }
}

#  INITIAL UI STATE
function Force-InitialColors {
    Set-AutoConnectState $false $false
    Set-AdvState $App.State.isAdvancedOpen
    Set-WpfToggleState $App.UI.btnV2rayTog $App.Config.enableV2rayChain "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnDirectTog $App.Config.enableDirect "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnOutboundTog $App.Config.enableOutboundProxy "Enabled" "Disabled"
    Set-WpfToggleState $App.UI.btnDohTog ($App.Config.enableTorDoh -or $App.Config.enableUpstreamDoh) "Enabled" "Disabled"
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
    $ix = @"
        <TextBlock Name="lblDomains" Text="Domains or IPs to bypass Tor (Comma Separated | Proxy Mode):" Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="{StaticResource TextMain}"/>
        <TextBox Name="txtDomains" Canvas.Left="15" Canvas.Top="55" Width="410" Height="45" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" TextWrapping="Wrap" Padding="5" FontSize="11" FontFamily="Consolas"/>
        <TextBlock Name="lblApps" Text="Applications to bypass VPN Tunnel (e.g., spotify.exe | VPN Mode):" Canvas.Left="15" Canvas.Top="115" FontSize="11" Foreground="{StaticResource TextMain}"/>
        <TextBox Name="txtApps" Canvas.Left="15" Canvas.Top="135" Width="410" Height="45" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" TextWrapping="Wrap" Padding="5" FontSize="11" FontFamily="Consolas"/>
        <TextBlock Name="lblBlock" Text="Custom Blacklisted Domains to Block Completely (e.g., tiktok.com):" Canvas.Left="15" Canvas.Top="195" FontSize="11" Foreground="{StaticResource TextMain}"/>
        <TextBox Name="txtBlock" Canvas.Left="15" Canvas.Top="215" Width="410" Height="45" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" TextWrapping="Wrap" Padding="5" FontSize="11" FontFamily="Consolas"/>
        <Button Name="btnOk" Content="Save Config" Canvas.Left="235" Canvas.Top="290" Width="90" Height="25" IsDefault="True" Style="{StaticResource SaveButton}"/>
        <Button Name="btnCancel" Content="Cancel" Canvas.Left="335" Canvas.Top="290" Width="90" Height="25" IsCancel="True"/>
"@
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
    
    $result = Show-AppDialog -Title "SPLIT TUNNELING AND PRIVACY ENGINE" -Width 480 -Height 400 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
    if ($result) {
        $hasRules = -not [string]::IsNullOrWhiteSpace($App.Config.lastManualSplit) -or
                    -not [string]::IsNullOrWhiteSpace($App.Config.lastAppSplit)
        if (-not $App.Config.enableDirect -and $hasRules) {
            $App.Config.enableDirect = $true
            Set-WpfToggleState $App.UI.btnDirectTog $true
        }
        Save-Config
        if ($App.State.isConnected) { Restart-Xray $App.Config.lastXrayMode }
    }
    return $result
}

function Show-CustomBridgeDialog {
    $ix = @"
        <TextBox Name="txtInput" Canvas.Left="15" Canvas.Top="35" Width="350" Height="80" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Padding="5" FontSize="11" FontFamily="Consolas"/>
        <Button Name="btnOk" Content="Save" Canvas.Left="175" Canvas.Top="132" Width="90" Height="25" IsDefault="True" Style="{StaticResource SaveButton}"/>
        <Button Name="btnCancel" Content="Cancel" Canvas.Left="275" Canvas.Top="132" Width="90" Height="25" IsCancel="True"/>
"@
    $onLoad = {
        param($d)
        $t = $d.FindName("txtInput")
        $t.Text = $App.Config.customBridgeLine
        $t.Focus() | Out-Null; $t.CaretIndex = $t.Text.Length
    }
    $onSave = {
        param($d)
        $App.Config.customBridgeLine = $d.FindName("txtInput").Text.Trim()
    }
    return Show-AppDialog -Title "CUSTOM BRIDGE CONFIGURATIONS" -Width 420 -Height 240 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

function Show-V2rayDialog {
    $ix = @"
        <TextBlock Text="Paste the full v2rayN JSON or raw Xray Outbound below:" Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="{StaticResource TextMain}"/>
        <TextBox Name="txtInput" Canvas.Left="15" Canvas.Top="60" Width="448" Height="180" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" Padding="5" FontSize="11" FontFamily="Consolas"/>
        <Button Name="btnImport" Content="Import .json File" Canvas.Left="15" Canvas.Top="257" Width="120" Height="25"/>
        <Button Name="btnOk" Content="Validate &amp; Save" Canvas.Left="243" Canvas.Top="257" Width="110" Height="25" IsDefault="True" Style="{StaticResource SaveButton}"/>
        <Button Name="btnCancel" Content="Cancel" Canvas.Left="363" Canvas.Top="257" Width="100" Height="25" IsCancel="True"/>
"@
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
            [System.Windows.Forms.MessageBox]::Show("Invalid Xray JSON syntax!", "Validation Error", 0, 16)
            return $false
        }
    }
    return Show-AppDialog -Title "V2RAY OUTBOUND CHAIN CONFIGURATION" -Width 520 -Height 365 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

function Show-OutboundProxyDialog {
    $ix = @"
        <Border BorderBrush="{StaticResource BorderLight}" BorderThickness="1" CornerRadius="4,0,0,4" Canvas.Left="15" Canvas.Top="35" Width="120" Height="26">
            <TextBlock Text="PROXY TYPE" FontSize="10" FontWeight="Bold" Foreground="{StaticResource TextMuted}" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
        </Border>
        <Rectangle Canvas.Left="134" Canvas.Top="35" Width="1" Height="26" Fill="{StaticResource BorderLight}"/>
        <ComboBox Name="cmbProxyType" Canvas.Left="135" Canvas.Top="35" Width="120" Height="26" FontSize="11" Style="{StaticResource DarkComboBoxJoined}">
            <ComboBoxItem Content="SOCKS5"/><ComboBoxItem Content="HTTPS"/>
        </ComboBox>
        <TextBlock Text="Address/IP:" Canvas.Left="15" Canvas.Top="70" FontSize="11" Foreground="{StaticResource TextMuted}"/>
        <TextBox Name="txtAddr" Canvas.Left="15" Canvas.Top="88" Width="240" Height="26" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" Padding="4" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
        <TextBlock Text="Port:" Canvas.Left="270" Canvas.Top="70" FontSize="11" Foreground="{StaticResource TextMuted}"/>
        <TextBox Name="txtPort" Canvas.Left="270" Canvas.Top="88" Width="95" Height="26" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" Padding="4" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
        <Border BorderBrush="{StaticResource BorderLight}" BorderThickness="1" CornerRadius="4,0,0,4" Canvas.Left="15" Canvas.Top="128" Width="120" Height="26">
            <TextBlock Text="AUTHENTICATION" FontSize="10" FontWeight="Bold" Foreground="{StaticResource TextMuted}" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
        </Border>
        <Rectangle Canvas.Left="134" Canvas.Top="128" Width="1" Height="26" Fill="{StaticResource BorderLight}"/>
        <ComboBox Name="cmbAuth" Canvas.Left="135" Canvas.Top="128" Width="120" Height="26" FontSize="11" Style="{StaticResource DarkComboBoxJoined}">
            <ComboBoxItem Content="Disabled"/><ComboBoxItem Content="Enabled"/>
        </ComboBox>
        <Canvas Name="panAuth" Canvas.Left="15" Canvas.Top="165" Visibility="Hidden" Opacity="0">
            <TextBlock Text="Username:" Canvas.Left="0" Canvas.Top="0" FontSize="11" Foreground="{StaticResource TextMuted}"/>
            <TextBox Name="txtUser" Canvas.Left="0" Canvas.Top="18" Width="165" Height="26" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" Padding="4" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
            <TextBlock Text="Password:" Canvas.Left="185" Canvas.Top="0" FontSize="11" Foreground="{StaticResource TextMuted}"/>
            <TextBox Name="txtPass" Canvas.Left="185" Canvas.Top="18" Width="165" Height="26" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" Padding="4" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
        </Canvas>
        <Button Name="btnOk" Content="Save" Canvas.Left="175" Canvas.Top="168" Width="90" Height="25" IsDefault="True" Style="{StaticResource SaveButton}"/>
        <Button Name="btnCancel" Content="Cancel" Canvas.Left="275" Canvas.Top="168" Width="90" Height="25" IsCancel="True"/>
"@
    $onLoad = {
        param($dlg)
        $cmbProxyType = $dlg.FindName("cmbProxyType"); $cmbAuth   = $dlg.FindName("cmbAuth")
        $txtAddr      = $dlg.FindName("txtAddr");       $txtPort   = $dlg.FindName("txtPort")
        $txtUser      = $dlg.FindName("txtUser");       $txtPass   = $dlg.FindName("txtPass")
        $panAuth      = $dlg.FindName("panAuth");       $btnOk     = $dlg.FindName("btnOk")
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
            $isEnabled  = ($null -ne $cmbAuth.SelectedItem -and $cmbAuth.SelectedItem.Content -eq "Enabled")
            $targetH    = if ($isEnabled) { 320.0 } else { 263.0 }
            $tBorderH   = if ($isEnabled) { 267.0 } else { 210.0 }
            $tBtnTop    = if ($isEnabled) { 225.0 } else { 168.0 }
            $tOpac      = if ($isEnabled) { 1.0   } else { 0.0   }
            if ($isFirstLoad) {
                $dlg.Height = $targetH; $borderMain.Height = $tBorderH
                $btnOk.SetValue(    [System.Windows.Controls.Canvas]::TopProperty, [double]$tBtnTop)
                $btnCancel.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$tBtnTop)
                $panAuth.Opacity = $tOpac
                $panAuth.Visibility = if ($isEnabled) { "Visible" } else { "Hidden" }
            } else {
                if ($isEnabled) { $panAuth.Visibility = "Visible" }
                $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(250))
                $dlg.BeginAnimation(       [System.Windows.Window]::HeightProperty,                (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetH, $dur)))
                $borderMain.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,      (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBorderH, $dur)))
                $btnOk.BeginAnimation(     [System.Windows.Controls.Canvas]::TopProperty,          (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBtnTop, $dur)))
                $btnCancel.BeginAnimation( [System.Windows.Controls.Canvas]::TopProperty,          (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tBtnTop, $dur)))
                $panAuth.BeginAnimation(   [System.Windows.UIElement]::OpacityProperty,            (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$tOpac, $dur)))
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
    $ix = @"
        <TextBlock Name="lblWarn" Text="&#x26A0;&#xFE0F; Tor DoH cannot be active while an Outbound Proxy is enabled." Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="#F6AD55" Visibility="Hidden"/>
        <TextBlock Name="lblTor" Text="Tor Outbound DoH (Initial Handshake):" Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="{StaticResource TextMuted}"/>
        <Border Name="borTor" Canvas.Left="15" Canvas.Top="55" Width="350" Height="26" Background="{StaticResource BgInput}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" CornerRadius="4">
            <Canvas>
                <TextBox Name="txtTorDoh" Canvas.Left="2" Canvas.Top="0" Width="268" Height="24" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" CaretBrush="White" BorderThickness="0" Padding="5,0,4,0" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                <Rectangle Canvas.Left="269" Canvas.Top="0" Width="1" Height="24" Fill="{StaticResource BorderMain}"/>
                <Button Name="btnTorTog" Canvas.Left="270" Canvas.Top="0" Width="80" Height="24" Content="DISABLED" FontSize="10" FontFamily="Consolas" FontWeight="Bold" Background="Transparent" BorderThickness="0" Cursor="Hand">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="InnerBorder" Background="Transparent" CornerRadius="0,4,4,0">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="InnerBorder" Property="Background" Value="#1AFFFFFF"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Canvas>
        </Border>
        <TextBlock Name="lblUp" Text="Upstream DoH (Xray / Sing-box):" Canvas.Left="15" Canvas.Top="90" FontSize="11" Foreground="{StaticResource TextMuted}"/>
        <Border Name="borUp" Canvas.Left="15" Canvas.Top="110" Width="350" Height="26" Background="{StaticResource BgInput}" BorderBrush="{StaticResource BorderMain}" BorderThickness="1" CornerRadius="4">
            <Canvas>
                <TextBox Name="txtUpDoh" Canvas.Left="2" Canvas.Top="0" Width="268" Height="24" Background="{StaticResource BgInput}" Foreground="{StaticResource TextGreen}" CaretBrush="White" BorderThickness="0" Padding="5,0,4,0" FontSize="12" FontFamily="Consolas" VerticalContentAlignment="Center"/>
                <Rectangle Canvas.Left="269" Canvas.Top="0" Width="1" Height="24" Fill="{StaticResource BorderMain}"/>
                <Button Name="btnUpTog" Canvas.Left="270" Canvas.Top="0" Width="80" Height="24" Content="DISABLED" FontSize="10" FontFamily="Consolas" FontWeight="Bold" Background="Transparent" BorderThickness="0" Cursor="Hand">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="InnerBorder" Background="Transparent" CornerRadius="0,4,4,0">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-1,0,0"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="InnerBorder" Property="Background" Value="#1AFFFFFF"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Canvas>
        </Border>
        <TextBlock Name="lblHint" Canvas.Left="15" Canvas.Top="145" Width="350" TextWrapping="Wrap" FontSize="11" Foreground="#4A5568" Text="Hint: Enter a full DoH URL or a standard IPv4 DNS.&#x0a;(e.g., https://1.1.1.1/dns-query OR 10.202.10.10)"/>
        <Button Name="btnOk" Content="Save" Canvas.Left="175" Canvas.Top="192" Width="90" Height="25" IsDefault="True" Style="{StaticResource SaveButton}"/>
        <Button Name="btnCancel" Content="Cancel" Canvas.Left="275" Canvas.Top="192" Width="90" Height="25" IsCancel="True"/>
"@
    $onLoad = {
        param($dlg)
        $_bc2 = New-Object System.Windows.Media.BrushConverter
        $tGreen = $_bc2.ConvertFromString("#68D391"); $tRed = $_bc2.ConvertFromString("#E53E3E"); $tGray = $_bc2.ConvertFromString("#A0AEC0")
        
        $lblWarn   = $dlg.FindName("lblWarn");   $lblTor    = $dlg.FindName("lblTor")
        $borTor    = $dlg.FindName("borTor");    $btnTorTog = $dlg.FindName("btnTorTog")
        $txtTorDoh = $dlg.FindName("txtTorDoh"); $lblUp     = $dlg.FindName("lblUp")
        $borUp     = $dlg.FindName("borUp");     $btnUpTog  = $dlg.FindName("btnUpTog")
        $txtUpDoh  = $dlg.FindName("txtUpDoh");  $lblHint   = $dlg.FindName("lblHint")
        $btnOk2    = $dlg.FindName("btnOk");     $btnC2     = $dlg.FindName("btnCancel")
        $bMain     = $dlg.FindName("borderMain")
        
        $txtTorDoh.Text = $App.Config.torDohUrl; $txtUpDoh.Text = $App.Config.upstreamDohUrl
        $btnUpTog.Content   = if ($App.Config.enableUpstreamDoh) { "ENABLED" } else { "DISABLED" }
        $btnUpTog.Foreground = if ($App.Config.enableUpstreamDoh) { $tGreen } else { $tRed }
        
        if ($App.Config.enableOutboundProxy) {
            $dlg.Height = 320; $bMain.Height = 254; $lblWarn.Visibility = "Visible"
            $lblTor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]55)
            $borTor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]75)
            $lblUp.SetValue( [System.Windows.Controls.Canvas]::TopProperty, [double]110)
            $borUp.SetValue( [System.Windows.Controls.Canvas]::TopProperty, [double]130)
            $lblHint.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]165)
            $btnOk2.SetValue( [System.Windows.Controls.Canvas]::TopProperty, [double]212)
            $btnC2.SetValue(  [System.Windows.Controls.Canvas]::TopProperty, [double]212)
            $btnTorTog.Content = "DISABLED"; $btnTorTog.Foreground = $tGray
            $btnTorTog.IsEnabled = $false; $txtTorDoh.IsEnabled = $false
            $borTor.Opacity = 0.3; $lblTor.Opacity = 0.5
        } else {
            $btnTorTog.Content    = if ($App.Config.enableTorDoh) { "ENABLED" } else { "DISABLED" }
            $btnTorTog.Foreground = if ($App.Config.enableTorDoh) { $tGreen } else { $tRed }
            $btnTorTog.Add_Click({
                if ($this.Content -eq "DISABLED") { $this.Content = "ENABLED"; $this.Foreground = $tGreen }
                else { $this.Content = "DISABLED"; $this.Foreground = $tRed }
            }.GetNewClosure())
        }
        $btnUpTog.Add_Click({
            if ($this.Content -eq "DISABLED") { $this.Content = "ENABLED"; $this.Foreground = $tGreen }
            else { $this.Content = "DISABLED"; $this.Foreground = $tRed }
        }.GetNewClosure())
        $txtTorDoh.Focus() | Out-Null; $txtTorDoh.CaretIndex = $txtTorDoh.Text.Length
    }
    $onSave = {
        param($d)
        $App.Config.enableTorDoh = ($d.FindName("btnTorTog").Content -eq "ENABLED")
        $tDoh = $d.FindName("txtTorDoh").Text
        if (-not [string]::IsNullOrWhiteSpace($tDoh)) { $App.Config.torDohUrl = $tDoh.Trim() }
        $App.Config.enableUpstreamDoh = ($d.FindName("btnUpTog").Content -eq "ENABLED")
        $uDoh = $d.FindName("txtUpDoh").Text
        if (-not [string]::IsNullOrWhiteSpace($uDoh)) { $App.Config.upstreamDohUrl = $uDoh.Trim() }
    }
    return Show-AppDialog -Title "DNS SETTINGS" -Width 420 -Height 300 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

function Show-ExitNodeDialog {
    $ix = @"
        <TextBlock Text="Select your desired geographic exit location:" Canvas.Left="15" Canvas.Top="35" FontSize="11" Foreground="{StaticResource TextMain}"/>
        <ComboBox Name="cmbCountries" Canvas.Left="15" Canvas.Top="57" Width="350" Height="28" FontSize="11" FontFamily="Consolas" Style="{StaticResource DarkComboBox}"/>
        <Button Name="btnOk" Content="Save" Canvas.Left="175" Canvas.Top="102" Width="90" Height="25" IsDefault="True" Style="{StaticResource SaveButton}"/>
        <Button Name="btnCancel" Content="Cancel" Canvas.Left="275" Canvas.Top="102" Width="90" Height="25" IsCancel="True"/>
"@
    $onLoad = {
        param($d)
        $cmb = $d.FindName("cmbCountries")
        $countries = [ordered]@{
            "Argentina"="ar";"Australia"="au";"Austria"="at";"Brazil"="br";"Canada"="ca";
            "Finland"="fi";"France"="fr";"Germany"="de";"Hong Kong"="hk";"Iceland"="is";
            "India"="in";"Iran"="ir";"Italy"="it";"Japan"="jp";"Mexico"="mx";
            "Netherlands"="nl";"New Zealand"="nz";"Romania"="ro";"Singapore"="sg";
            "South Africa"="za";"South Korea"="kr";"Spain"="es";"Sweden"="se";
            "Switzerland"="ch";"United Arab Emirates"="ae";"United Kingdom"="uk";"United States"="us"
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
    return Show-AppDialog -Title "CUSTOM EXIT-NODE ROUTING" -Width 420 -Height 210 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

#  CORE LOGIC
function Save-Config {
    $data = [ordered]@{
        AutoStart            = [bool]$App.Config.autoStart
        LaunchOnBoot         = [bool]$App.Config.launchOnBoot
        LastConfig           = if ($App.UI.comboConfig.SelectedItem) { $App.UI.comboConfig.SelectedItem.Tag } else { $App.Config.lastConfig }
        SelectedBridge       = $App.UI.comboBridge.SelectedItem.Tag
        InstanceCount        = [int]$App.UI.comboCount.SelectedItem.Tag
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
        EnableTorDoh         = [bool]$App.Config.enableTorDoh
        TorDohUrl            = $App.Config.torDohUrl
        EnableUpstreamDoh    = [bool]$App.Config.enableUpstreamDoh
        UpstreamDohUrl       = $App.Config.upstreamDohUrl
        CustomExitCountry    = $App.Config.customExitCountry
        MinimizeToTray       = [bool]$App.Config.minimizeToTray
        EnableAdBlock        = [bool]$App.Config.enableAdBlock
    }
    try { $data | ConvertTo-Json -Depth 10 | Set-Content -Path $App.Config.cfgFile -Force }
    catch { Write-Host "Failed to save config: $($_.Exception.Message)" }
}

function Write-TorOutboundDohConfig {
    $dohUrl    = $App.Config.torDohUrl
    $dnsAddr   = if ($dohUrl.StartsWith("https://")) {
        try {
            $uri     = [uri]$dohUrl
            $dnsHost = $uri.Host
            $dnsPath = if ($uri.AbsolutePath -eq "/") { "/dns-query" } else { $uri.PathAndQuery }
            "https://$dnsHost$dnsPath"
        } catch { "https://cloudflare-dns.com/dns-query" }
    } else { $dohUrl }
    
    @{
        log      = @{ logLevel = "error" }
        dns      = @{ servers  = @($dnsAddr) }
        inbounds = @( @{ listen="127.0.0.1"; port=10820; protocol="socks"; settings=@{ udp=$false } } )
        outbounds = @( @{ tag="direct"; protocol="freedom"; settings=@{} } )
        routing  = @{ domainStrategy="UseIP"; rules=@( @{ type="field"; network="tcp,udp"; outboundTag="direct" } ) }
    } | ConvertTo-Json -Depth 10 | Set-Content (Get-AppPath "Data\Xray\tor-doh.json")
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
    $inbounds = @( @{ listen="0.0.0.0"; port=10818; protocol="mixed"; settings=@{ udp=$true }; sniffing=@{ enabled=$true; destOverride=@("http","tls","quic","fakedns") } } )
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
    $cfg = @{ log=@{ logLevel="info"; access="access.log"; error="error.log" }; inbounds=$inbounds; outbounds=$outbounds; routing=@{ domainStrategy="AsIs"; rules=$rules } }
    if ($App.Config.enableUpstreamDoh -and -not [string]::IsNullOrWhiteSpace($App.Config.upstreamDohUrl)) {
        $cfg.Add("dns", @{ servers=@($App.Config.upstreamDohUrl) })
    }
    $cfg | ConvertTo-Json -Depth 10 | Set-Content (Get-AppPath "Data\Xray\config.json")
}

function Write-SingboxConfig {
    $bypassApps = @("tor.exe","haproxy.exe","lyrebird.exe","obfs4proxy.exe","snowflake-client.exe","xray.exe","sing-box.exe")
    if ($App.Config.enableDirect -and -not [string]::IsNullOrWhiteSpace($App.Config.lastAppSplit)) {
        $App.Config.lastAppSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
            $appStr = if ($_ -notmatch "\.exe$") { "$_.exe" } else { $_ }
            $bypassApps += $appStr.ToLower()
        }
    }
    $sbRules = @(
        @{ process_name=$bypassApps; outbound="direct" }
        @{ action="sniff" }
        @{ port=@(53); action="hijack-dns" }
        @{ protocol="dns"; action="hijack-dns" }
        @{ ip_is_private=$true; outbound="direct" }
        @{ network="udp"; port=@(443); outbound="block" }
    )
    $dnsSrv = if ($App.Config.enableUpstreamDoh -and -not [string]::IsNullOrWhiteSpace($App.Config.upstreamDohUrl)) {
        if ($App.Config.upstreamDohUrl.StartsWith("https://")) {
            try {
                $u = [uri]$App.Config.upstreamDohUrl
                $dPath = if ($u.AbsolutePath -eq "/") { "/dns-query" } else { $u.PathAndQuery }
                @{ tag="dns_proxy"; type="https"; server=$u.Host; path=$dPath; detour="proxy" }
            } catch { @{ tag="dns_proxy"; type="tcp"; server="1.1.1.1"; detour="proxy" } }
        } else { @{ tag="dns_proxy"; type="tcp"; server=$App.Config.upstreamDohUrl; detour="proxy" } }
    } else { @{ tag="dns_proxy"; type="https"; server="cloudflare-dns.com"; path="/dns-query"; detour="proxy" } }
    
    @{
        log      = @{ level="fatal" }
        dns      = @{ servers=@($dnsSrv); final="dns_proxy"; strategy="ipv4_only" }
        inbounds = @( @{ type="tun"; tag="tun-in"; interface_name="singbox_tun"; address=@("172.18.0.1/30"); mtu=9000; auto_route=$true; strict_route=$true; stack="gvisor" } )
        outbounds = @( @{ type="socks"; tag="proxy"; server="127.0.0.1"; server_port=10818 }, @{ type="direct"; tag="direct" }, @{ type="block"; tag="block" } )
        route    = @{ auto_detect_interface=$true; rules=$sbRules; final="proxy" }
    } | ConvertTo-Json -Depth 10 | Set-Content (Get-AppPath "Data\sing_box\config.json")
}

function Set-SystemProxy($enable) {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($enable) {
        Set-ItemProperty $regPath -Name "ProxyEnable" -Value 1
        Set-ItemProperty $regPath -Name "ProxyServer"  -Value "127.0.0.1:10818"
        $bypass = "<local>"
        if ($App.Config.enableDirect -and -not [string]::IsNullOrWhiteSpace($App.Config.lastManualSplit) -and $App.Config.lastXrayMode -eq "Proxy Mode") {
            $clean = $App.Config.lastManualSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            $bypass = "$($clean -join ';');<local>"
        }
        Set-ItemProperty $regPath -Name "ProxyOverride" -Value $bypass
    } else { Set-ItemProperty $regPath -Name "ProxyEnable" -Value 0 }
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
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
    $haData = Get-Content $cfgPath; $newData = @(); $hasStats = $false
    foreach ($line in $haData) {
        if ($line -match "^listen stats") { $hasStats = $true }
        if ($line -match "^\s*#?\s*server\s+tor(\d+)") {
            if ([int]$matches[1] -le $activeCount) { $newData += ($line -replace "^\s*#+\s*", "    ") }
            else { $newData += if ($line -notmatch "^\s*#") { "    # $($line.TrimStart())" } else { $line } }
        } else { $newData += $line }
    }
    if (-not $hasStats) { $newData += "","listen stats","    bind 127.0.0.1:10888","    mode http","    stats enable","    stats uri /stats" }
    $newData | Set-Content $cfgPath
}

function Restart-Xray($targetMode) {
    Get-Process sing-box, xray -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($null -ne $_.Path -and ($_.Path -eq (Get-AppPath "Data\Xray\xray.exe") -or $_.Path -eq (Get-AppPath "Data\sing_box\sing-box.exe"))) {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    if ($null -ne $App.Runtime.cmdDebugPid)  { Stop-Process -Id $App.Runtime.cmdDebugPid  -Force -ErrorAction SilentlyContinue; $App.Runtime.cmdDebugPid  = $null }
    if ($null -ne $App.Runtime.cmdDebugPid2) { Stop-Process -Id $App.Runtime.cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $App.Runtime.cmdDebugPid2 = $null }
    if ($null -ne $App.Runtime.xrayDohPid)   { Stop-Process -Id $App.Runtime.xrayDohPid   -Force -ErrorAction SilentlyContinue; $App.Runtime.xrayDohPid   = $null }
    
    Start-Sleep -Milliseconds 500
    Write-XrayConfig
    
    if ($App.Config.debugMode) {
        $p = Start-Process "cmd.exe" -ArgumentList "/c `"title XrayDebug & .\xray.exe run -c config.json || pause`"" -WorkingDirectory $App.Config.xrayDir -WindowStyle Normal -PassThru
        $App.Runtime.cmdDebugPid = $p.Id
    } else {
        Start-Process -FilePath (Get-AppPath "Data\Xray\xray.exe") -ArgumentList "run -c config.json" -WorkingDirectory $App.Config.xrayDir -WindowStyle Hidden
    }
    if ($targetMode -eq "VPN Mode") {
        Write-SingboxConfig
        if ($App.Config.debugMode) {
            $p2 = Start-Process "cmd.exe" -ArgumentList "/c `"title SingBoxDebug & .\sing-box.exe run -c config.json || pause`"" -WorkingDirectory $App.Config.sbDir -WindowStyle Normal -PassThru
            $App.Runtime.cmdDebugPid2 = $p2.Id
        } else { Start-Process -FilePath (Get-AppPath "Data\sing_box\sing-box.exe") -ArgumentList "run -c config.json" -WorkingDirectory $App.Config.sbDir -WindowStyle Hidden }
    } elseif ($targetMode -eq "Proxy Mode") { Set-SystemProxy $true }
    
    if ($targetMode -ne "Proxy Mode") { Set-SystemProxy $false }
    
    if ($App.State.isConnected) {
        if ($null -ne $App.Runtime.pingTimer) { $App.Runtime.pingTimer.Stop() }
        $App.Runtime.pingTimer = New-Object System.Windows.Threading.DispatcherTimer
        $App.Runtime.pingTimer.Interval = [TimeSpan]::FromSeconds(1.5)
        $App.Runtime.pingTimer.add_Tick({ $App.Runtime.pingTimer.Stop(); Start-GeoPing })
        $App.Runtime.pingTimer.Start()
    }
}

#  WAVE ANIMATION
function Update-WaveAnimation {
    param([string]$State)
    if ($null -eq $App.UI.wavePath1 -or $null -eq $App.UI.waveTrans1 -or $null -eq $App.UI.waveTrans2) { return }
    if ($null -eq $App.Runtime.wavePhysicsTimer) {
        $App.Runtime.wavePhysicsTimer = New-Object System.Windows.Threading.DispatcherTimer
        $App.Runtime.wavePhysicsTimer.Interval = [TimeSpan]::FromMilliseconds(25)
        $App.Runtime.wavePhysicsTimer.add_Tick({
            $App.Runtime.waveCurrentSpeed1 += ($App.Runtime.waveTargetSpeed1 - $App.Runtime.waveCurrentSpeed1) * 0.08
            $App.Runtime.waveCurrentSpeed2 += ($App.Runtime.waveTargetSpeed2 - $App.Runtime.waveCurrentSpeed2) * 0.08
            $App.Runtime.waveX1 -= $App.Runtime.waveCurrentSpeed1
            $App.Runtime.waveX2 -= $App.Runtime.waveCurrentSpeed2
            if ($App.Runtime.waveX1 -le -150.0) { $App.Runtime.waveX1 += 150.0 }
            if ($App.Runtime.waveX2 -le -225.0) { $App.Runtime.waveX2 += 150.0 }
            $App.UI.waveTrans1.X = $App.Runtime.waveX1
            $App.UI.waveTrans2.X = $App.Runtime.waveX2
        })
        $App.Runtime.wavePhysicsTimer.Start()
    }
    if ($null -ne $App.Runtime.waveHoldTimer) { $App.Runtime.waveHoldTimer.Stop() }
    
    $colorHex = "#718096"
    switch ($State) {
        "Idle"       { $App.Runtime.waveTargetSpeed1 = 0.4; $App.Runtime.waveTargetSpeed2 = 0.5 }
        "Connecting" {
            $colorHex = "#B78854"
            $App.Runtime.waveCurrentSpeed1 = 5.5; $App.Runtime.waveCurrentSpeed2 = 6.0
            $App.Runtime.waveTargetSpeed1  = 5.5; $App.Runtime.waveTargetSpeed2  = 6.0
            $App.Runtime.waveHoldTimer = New-Object System.Windows.Threading.DispatcherTimer
            $App.Runtime.waveHoldTimer.Interval = [TimeSpan]::FromMilliseconds(600)
            $App.Runtime.waveHoldTimer.add_Tick({ $App.Runtime.waveHoldTimer.Stop(); $App.Runtime.waveTargetSpeed1 = 1.1; $App.Runtime.waveTargetSpeed2 = 1.3 }.GetNewClosure())
            $App.Runtime.waveHoldTimer.Start()
        }
        "Connected"  {
            $colorHex = "#68D391"
            $App.Runtime.waveCurrentSpeed1 = 5.5; $App.Runtime.waveCurrentSpeed2 = 6.0
            $App.Runtime.waveTargetSpeed1  = 5.5; $App.Runtime.waveTargetSpeed2  = 6.0
            $App.Runtime.waveHoldTimer = New-Object System.Windows.Threading.DispatcherTimer
            $App.Runtime.waveHoldTimer.Interval = [TimeSpan]::FromMilliseconds(600)
            $App.Runtime.waveHoldTimer.add_Tick({ $App.Runtime.waveHoldTimer.Stop(); $App.Runtime.waveTargetSpeed1 = 0.4; $App.Runtime.waveTargetSpeed2 = 0.5 }.GetNewClosure())
            $App.Runtime.waveHoldTimer.Start()
        }
    }
    
    try {
        $col  = [System.Windows.Media.ColorConverter]::ConvertFromString($colorHex)
        $anim = New-Object System.Windows.Media.Animation.ColorAnimation($col, (New-Object System.Windows.Duration([TimeSpan]::FromSeconds(0.8))))
        $App.UI.waveBrush1.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $anim)
        $App.UI.waveBrush2.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $anim)
    } catch {}
}

#  GEO-IP
function Start-GeoPing {
    if ($App.State.isGeoTracing) { return }
    $App.State.isGeoTracing = $true
    $App.UI.lblGeoData.Text       = "Loc: TRACING...`nPing: --"
    $App.UI.lblGeoData.Foreground = $App.UI.brGreen
    $gc = New-Object System.Net.WebClient
    $gc.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:10818")
    $App.Runtime.geoSw = [System.Diagnostics.Stopwatch]::StartNew()
    $gc.Add_DownloadStringCompleted({
        param($sender, $e)
        $App.State.isGeoTracing = $false
        $App.Runtime.geoSw.Stop()
        $pingMs = $App.Runtime.geoSw.ElapsedMilliseconds
        $App.UI.form.Dispatcher.Invoke([System.Action]{
            if ($App.State.isConnected) {
                if (-not $e.Cancelled -and $null -eq $e.Error) {
                    try {
                        $data = $e.Result | ConvertFrom-Json
                        $selCfg = if ($App.UI.comboConfig.SelectedItem.Tag -match "Custom") { "Custom" } else { "Optimized" }
                        $geoStr = if ($selCfg -eq "Custom" -or $App.Config.enableV2rayChain) { $data.country } else {
                            $cMap = @{ NA="NORTH AMERICA"; EU="EUROPE"; AS="ASIA"; SA="SOUTH AMERICA"; AF="AFRICA"; OC="OCEANIA"; AN="ANTARCTICA" }
                            if ($cMap[$data.continent_code]) { $cMap[$data.continent_code] } else { $data.continent_code }
                        }
                        $App.UI.lblGeoData.Text       = "Loc: $($geoStr.ToUpper())`nPing: $($pingMs)ms"
                        $App.UI.lblGeoData.Foreground = $App.UI.brGreen
                    } catch { $App.UI.lblGeoData.Text = "Loc: ERROR`nPing: --"; $App.UI.lblGeoData.Foreground = $_bc.ConvertFromString("#8B4A4A") }
                } else { $App.UI.lblGeoData.Text = "Loc: TIMEOUT`nPing: --"; $App.UI.lblGeoData.Foreground = $_bc.ConvertFromString("#8B4A4A") }
            }
        })
        $sender.Dispose()
    })
    try { $gc.DownloadStringAsync([uri]"https://get.geojs.io/v1/ip/geo.json") }
    catch { $App.State.isGeoTracing = $false; $gc.Dispose() }
}

#  ENGINE CONTROL
function Reset-ButtonText {
    $App.UI.btnActionMainText.Text       = "CONNECT"
    $App.UI.btnActionSubText.Text        = ""
    $App.UI.btnActionMainText.Foreground = $App.UI.brWhite
    Update-WaveAnimation -State "Idle"
}

function Stop-AllEngines($isClosing = $false) {
    $App.State.abortBoot       = $true
    $App.State.isEngineRunning = $false
    Set-SystemProxy $false
    Get-Process tor, haproxy, xray, sing-box -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $p = $_.Path
            if ($null -ne $p -and (
                $p -eq (Get-AppPath "Data\Xray\xray.exe")         -or
                $p -eq (Get-AppPath "Data\HAproxy\haproxy.exe")    -or
                $p -eq (Get-AppPath "Data\sing_box\sing-box.exe")  -or
                $p -match "Data\\Tors\\Tor")) {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                $proc = Get-Process -Id $_.Id -ErrorAction SilentlyContinue
                if ($null -ne $proc) { $null = $proc.WaitForExit(500) }
            }
        } catch { Write-Host "Stop error: $($_.Exception.Message)" }
    }
    if ($null -ne $App.Runtime.cmdDebugPid)  { Stop-Process -Id $App.Runtime.cmdDebugPid  -Force -ErrorAction SilentlyContinue; $App.Runtime.cmdDebugPid  = $null }
    if ($null -ne $App.Runtime.cmdDebugPid2) { Stop-Process -Id $App.Runtime.cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $App.Runtime.cmdDebugPid2 = $null }
    if ($null -ne $App.Runtime.xrayDohPid)   { Stop-Process -Id $App.Runtime.xrayDohPid   -Force -ErrorAction SilentlyContinue; $App.Runtime.xrayDohPid   = $null }
    
    $App.State.isConnected      = $false
    $App.State.lastTotalBytes   = 0
    $App.State.sessionDataBytes = 0
    $App.State.sessionStartTime = $null
    
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
    }
}

function Start-Engines {
    try {
        if (Get-Process tor -ErrorAction SilentlyContinue) {
            $App.UI.btnActionSubText.Text = "Clearing old engines..."
            DoEvents; Stop-AllEngines; Start-Sleep -Seconds 1
        }
        $App.State.abortBoot = $false
        $selBridge  = $App.UI.comboBridge.SelectedItem.Tag
        $selConfig  = if ($App.UI.comboConfig.SelectedItem.Tag -match "Custom") { "Custom" } else { "Optimized" }
        $selCount   = [int]($App.UI.comboCount.SelectedItem.Tag)
        $mode       = $App.Config.lastXrayMode
        $torrcFile  = "torrc"
        
        for ($i = 1; $i -le 8; $i++) {
            Remove-Item (Get-AppPath "Data\Tors\Tor$i\tor.log") -ErrorAction SilentlyContinue
            $lbl    = $App.UI.form.FindName("lblTor$i")
            $padded = $i.ToString().PadLeft(2,'0')
            if ($null -ne $lbl) {
                if ($i -le $selCount) { $lbl.Text = "Tor $padded`: Waiting..."; $lbl.Foreground = $App.UI.brGray }
                else                  { $lbl.Text = "Tor $padded`: Disabled";   $lbl.Foreground = $_bc.ConvertFromString("#4A5568") }
            }
        }
        Remove-Item (Get-AppPath "Data\Xray\access.log")     -ErrorAction SilentlyContinue
        Remove-Item (Get-AppPath "Data\Xray\access.log.tmp") -ErrorAction SilentlyContinue
        if ($null -ne $App.UI.txtXrayLogs) { $App.UI.txtXrayLogs.Text = "" }
        
        $App.State.isEngineRunning          = $true
        Save-Config
        $winStyle                           = if ($App.Config.debugMode) { "Normal" } else { "Hidden" }
        $App.UI.btnActionMainText.Text      = "CONNECTING"
        $App.UI.btnActionMainText.Foreground = $_bc.ConvertFromString("#F6AD55")
        $App.UI.btnActionSubText.Foreground  = $_bc.ConvertFromString("#B78854")
        
        Update-WaveAnimation -State "Connecting"
        Format-HAProxyConfig $selCount
        
        $dynamicWait = 16 - $selCount
        if ($App.Config.enableTorDoh -and -not $App.Config.enableOutboundProxy) {
            Write-TorOutboundDohConfig
            $pDoH = Start-Process -FilePath (Get-AppPath "Data\Xray\xray.exe") -ArgumentList "run -c tor-doh.json" -WorkingDirectory $App.Config.xrayDir -WindowStyle Hidden -PassThru
            $App.Runtime.xrayDohPid = $pDoH.Id
        }
        
        for ($i = 1; $i -le $selCount; $i++) {
            if ($App.State.abortBoot) { break }
            $padded = $i.ToString().PadLeft(2,'0')
            $App.UI.btnActionSubText.Text = "Booting Tor $i of $selCount"
            if ($i % 2 -eq 0) { DoEvents }
            
            $path = Get-AppPath "Data\Tors\Tor$i"
            if (-not (Test-Path "$path\$torrcFile")) { continue }
            $c = @(Get-Content "$path\$torrcFile")
            $cleanCfg = @()
            foreach ($line in $c) {
                if ($line -match "^# --- MANAGED BRIDGES ---") { break }
                if ($line -notmatch "^UseBridges|^ClientTransportPlugin|^Bridge|^HTTPSProxy|^Socks5Proxy|^Socks5ProxyUsername|^Socks5ProxyPassword|^HTTPSProxyAuthenticator|^Log notice file|^MaxCircuitDirtiness|^ExitNodes|^StrictNodes|^CircuitBuildTimeout|^HardwareAccel|^KeepalivePeriod|^NewCircuitPeriod|^# --- DYNAMIC ROUTING ---") {
                    if ($line.Trim()) { $cleanCfg += $line.Trim() }
                }
            }
            $cleanCfg += "","# --- DYNAMIC ROUTING ---"
            switch ($selConfig) {
                "Optimized" {
                    $cleanCfg += "CircuitBuildTimeout 10","KeepalivePeriod 60","NewCircuitPeriod 120","HardwareAccel 1"
                    $cleanCfg += "ExitNodes {nl},{de},{it},{is},{fi},{au},{nz},{ch},{hk},{ae},{us}","StrictNodes 0"
                }
                "Custom" {
                    if (-not [string]::IsNullOrWhiteSpace($App.Config.customExitCountry)) {
                        $cleanCfg += "ExitNodes {$($App.Config.customExitCountry)}","StrictNodes 1"
                    }
                }
                default {
                    $cleanCfg += "ExitNodes {nl},{de},{it},{is},{fi},{au},{nz},{ch},{hk},{ae},{us}","StrictNodes 0"
                }
            }
            $cleanCfg += "","# --- MANAGED BRIDGES ---","Log notice file tor.log"
            
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
            } elseif ($App.Config.enableTorDoh) { $cleanCfg += "Socks5Proxy 127.0.0.1:10820" }
            
            if ($selBridge -eq "Custom" -and $App.Config.customBridgeLine) {
                $cleanCfg += "UseBridges 1"
                $cleanCfg += "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel,snowflake exec ..\..\PluggableTransports\lyrebird.exe"
                $App.Config.customBridgeLine.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch "^ClientTransportPlugin" } | ForEach-Object {
                    $cleanCfg += if ($_ -notmatch "^Bridge\s") { "Bridge $_" } else { $_ }
                }
            } elseif ($selBridge -ne "Direct (None)") {
                $b = $bridgeData[$selBridge]
                $cleanCfg += "UseBridges 1",$b.plugin
                foreach ($bl in $b.lines) { $cleanCfg += $bl }
            } else { $cleanCfg += "UseBridges 0" }
            
            $cleanCfg | Set-Content "$path\$torrcFile"
            Start-Process -FilePath "$path\tor.exe" -ArgumentList "-f $torrcFile" -WorkingDirectory $path -WindowStyle $winStyle
            Wait-NonBlocking $dynamicWait
        }
        if (-not $App.State.abortBoot) {
            $App.UI.btnActionSubText.Text = "Booting Core Engines"
            DoEvents
            Remove-Item (Get-AppPath "Data\Xray\access.log") -ErrorAction SilentlyContinue
            Remove-Item (Get-AppPath "Data\Xray\error.log")  -ErrorAction SilentlyContinue
            if (Test-Path (Get-AppPath "Data\HAproxy\haproxy.exe")) {
                Start-Process -FilePath (Get-AppPath "Data\HAproxy\haproxy.exe") -ArgumentList "-f haproxy.cfg" -WorkingDirectory $App.Config.haPath -WindowStyle $winStyle
            }
            Restart-Xray $mode
            $App.UI.lblSocksTitle.Text    = "MIXED PORT"
            $App.UI.lblSocksDataIPs.Text  = "127.0.0.1:10818`n$($App.State.lanIp)`:10818"
            $App.UI.lblSocksDataTags.Text = "(Local)`n(LAN)"
            $App.State.isConnected        = $true
            $App.State.sessionStartTime   = Get-Date
            $App.UI.btnActionMainText.Text      = "CONNECTED"
            $App.UI.btnActionSubText.Text        = ""
            $App.UI.btnActionMainText.Foreground = $App.UI.brGreen
            Start-GeoPing
            Update-WaveAnimation -State "Connected"
        } else { Reset-ButtonText }
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
            $App.UI.btnTitleUpdate.IsEnabled = $true
            if (-not $e.Cancelled -and $null -eq $e.Error) {
                if ($e.Result -match '\$App\.Config\.currentVersion\s*=\s*"([^"]+)"|currentVersion\s*=\s*"([^"]+)"') {
                    $remoteVer = if ($matches[1]) { $matches[1] } else { $matches[2] }
                    if ([version]$remoteVer -gt [version]$App.Config.currentVersion) {
                        $remoteMinVer = "0.0.0" # Default fallback
                        if ($e.Result -match 'minAutoUpdateVersion\s*=\s*"([^"]+)"') {
                            $remoteMinVer = $matches[1]
                        }
                        if ([version]$App.Config.currentVersion -lt [version]$remoteMinVer) {
                            $App.UI.lblTitleText.Text = "MANUAL UPDATE REQUIRED ($remoteVer)"
                            $App.UI.lblTitleText.Foreground = $App.UI.brRed
                            [System.Windows.Forms.MessageBox]::Show("A major update (v$remoteVer) is available!`n`nYour current version ($($App.Config.currentVersion)) is too old to update automatically.`n`nPlease download the latest release manually from GitHub.", "Manual Update Required", 0, 48)
                            Start-Process $App.Config.repoReleaseUrl
                            return
                        }
                        $App.UI.lblTitleText.Text       = "TOR MULTIPLEXER v$($App.Config.currentVersion) — UPDATE AVAILABLE ($remoteVer)"
                        $App.UI.lblTitleText.Foreground = $App.UI.brWhite
                        $msg = [System.Windows.Forms.MessageBox]::Show("Version $remoteVer is available! Update now?", "Update Available", 4, 64)
                        if ($msg -eq "Yes") {
                            $dlClient = New-Object System.Net.WebClient
                            $dlClient.DownloadFile($App.Config.repoRawUrl, $App.Config.scriptPath)
                            $dlClient.Dispose()
                            $launcher = Get-AppPath "Launch Multiplexer.exe"
                            if (Test-Path $launcher) { Start-Process -FilePath $launcher -WorkingDirectory $App.Config.baseDir }
                            else { Start-Process powershell.exe -ArgumentList "-STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($App.Config.scriptPath)`"" }
                            [Environment]::Exit(0)
                        }
                    } else {
                        $App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)"
                        [System.Windows.Forms.MessageBox]::Show("You are already on the latest version!", "Up to Date", 0, 64)
                    }
                }
            } else {
                $App.UI.lblTitleText.Text = "TOR MULTIPLEXER v$($App.Config.currentVersion)"
                [System.Windows.Forms.MessageBox]::Show("Update check failed. Check your internet connection.", "Error", 0, 16)
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
                if ($e.Result -match 'currentVersion\s*=\s*"([^"]+)"') {
                    if ([version]$matches[1] -gt [version]$localVer) {
                        $localForm.Dispatcher.Invoke([System.Action]{
                            if ($null -ne $localTitle) {
                                $localTitle.Text       = "TOR MULTIPLEXER v$localVer  —  UPDATE AVAILABLE"
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
            $action    = New-ScheduledTaskAction -Execute (Get-AppPath "Launch Multiplexer.exe") -WorkingDirectory $App.Config.baseDir
            $trigger   = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to create Auto-Start task.`n$($_.Exception.Message)", "Error", 0, 16)
            $App.Config.launchOnBoot = $false
            Set-WpfToggleState $App.UI.btnBootTog $false
        }
    } else {
        try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    }
    $old = Join-Path ([Environment]::GetFolderPath('Startup')) "TorMultiplexer.lnk"
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
}

#  STATS TIMER
$App.Runtime.statsWebClient = New-Object System.Net.WebClient
$App.Runtime.statsWebClient.Add_DownloadStringCompleted({
    param($sender, $e)
    if (-not $e.Cancelled -and $null -eq $e.Error) {
        try {
            $rows    = $e.Result -split "`n"
            $servers = $rows | Where-Object { $_ -match ",tor\d+," }
            $curBytes = 0
            foreach ($srv in $servers) {
                $cols = $srv -split ","
                if ($cols.Count -ge 10) { $curBytes += [long]$cols[8] + [long]$cols[9] }
            }
            if ($App.State.lastTotalBytes -gt 0) {
                $diff = [Math]::Max(0, ($curBytes - $App.State.lastTotalBytes))
                $App.State.sessionDataBytes += $diff
                $App.State.speedSamples = @($diff) + $App.State.speedSamples[0..3]
                $avg  = ($App.State.speedSamples | Measure-Object -Average).Average
                $spd  = if ($avg -ge 1048576) { "$([Math]::Round($avg/1048576,2)) MB/s" } elseif ($avg -ge 1024) { "$([Math]::Round($avg/1024,1)) KB/s" } else { "$([int]$avg) B/s" }
                $tot  = if ($App.State.sessionDataBytes -ge 1073741824) { "$([Math]::Round($App.State.sessionDataBytes/1073741824,2)) GB" } elseif ($App.State.sessionDataBytes -ge 1048576) { "$([Math]::Round($App.State.sessionDataBytes/1048576,1)) MB" } else { "$([Math]::Round($App.State.sessionDataBytes/1024,1)) KB" }
                $App.UI.form.Dispatcher.Invoke([System.Action]{
                    if ($null -ne $App.UI.lblStatsData) { $App.UI.lblStatsData.Text = "Speed: $spd`nTotal: $tot" }
                })
            }
            if ($curBytes -gt 0) { $App.State.lastTotalBytes = $curBytes }
        } catch {}
    }
    $App.Runtime.isFetchingStats = $false
}.GetNewClosure())

$App.Runtime.statsTimer = New-Object System.Windows.Threading.DispatcherTimer
$App.Runtime.statsTimer.Interval = [TimeSpan]::FromSeconds(1)
$App.Runtime.statsTimer.add_Tick({
    if ($null -eq $App.UI.form -or $App.UI.form.Dispatcher.HasShutdownStarted) { $App.Runtime.statsTimer.Stop(); return }
    if ($App.State.isConnected) {
        if ($null -ne $App.State.sessionStartTime -and $null -ne $App.UI.lblSessionTime) {
            $elapsed = (Get-Date) - $App.State.sessionStartTime
            $App.UI.lblSessionTime.Text       = "SESSION: " + $elapsed.ToString("hh\:mm\:ss")
            $App.UI.lblSessionTime.Foreground = $App.UI.brGreen
        }
        if (-not $App.Runtime.isFetchingStats -and $null -ne $App.Runtime.statsWebClient) {
            $App.Runtime.isFetchingStats = $true
            try { $App.Runtime.statsWebClient.DownloadStringAsync([uri]"http://127.0.0.1:10888/stats;csv") }
            catch { $App.Runtime.isFetchingStats = $false }
        }
    }
}.GetNewClosure())
$App.Runtime.statsTimer.Start()

#  WINDOW SIZE / PANEL ANIMATION
function Update-WindowSize {
    $ts       = New-Object TimeSpan(0,0,0,0,300)
    $targetW  = if ($App.State.isLogsOpen -and $App.State.isAdvancedOpen) { 909.0  } else { 595.0 }
    $targetH  = if ($App.State.isAdvancedOpen -or $App.State.isLogsOpen)  { 534.0  } else { 340.0 }
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
        $App.UI.AdvancedCanvas.Visibility = "Visible"; 1.0
    } else { 0.0 }
    
    if ($App.State.isLogsOpen) {
        $App.UI.LogsCanvas.Visibility = "Visible"; $logTimer.Start()
        if ($App.State.isAdvancedOpen) {
            # MODE A — side panel
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(585.0,  $ts)))
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
            # MODE B — bottom panel
            $App.UI.LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(20.0,  $ts)))
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
    } else { $logOpac = 0.0; $logTimer.Stop() }
    
    $App.UI.form.BeginAnimation([System.Windows.Window]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation($targetW, $ts)))
    $App.UI.form.BeginAnimation([System.Windows.Window]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($targetH, $ts)))
    $App.UI.AdvancedCanvas.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($advOpac, $ts)))
    $App.UI.LogsCanvas.BeginAnimation([System.Windows.UIElement]::OpacityProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation($logOpac, $ts)))
    $App.UI.UnifiedPanel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($panelTop, $ts)))
    
    if (-not $App.State.isAdvancedOpen) {
        $App.Runtime.hideAdvTimer = New-Object System.Windows.Threading.DispatcherTimer
        $App.Runtime.hideAdvTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $App.Runtime.hideAdvTimer.add_Tick({ $App.Runtime.hideAdvTimer.Stop(); $App.UI.AdvancedCanvas.Visibility = "Hidden" }.GetNewClosure())
        $App.Runtime.hideAdvTimer.Start()
    }
    if (-not $App.State.isLogsOpen) {
        $App.Runtime.hideLogTimer = New-Object System.Windows.Threading.DispatcherTimer
        $App.Runtime.hideLogTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $App.Runtime.hideLogTimer.add_Tick({ $App.Runtime.hideLogTimer.Stop(); $App.UI.LogsCanvas.Visibility = "Hidden" }.GetNewClosure())
        $App.Runtime.hideLogTimer.Start()
    }
}

#  LIVE LOGS TIMER
$logTimer = New-Object System.Windows.Threading.DispatcherTimer
$logTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
$logTimer.add_Tick({
    try {
        if (-not $App.State.isLogsOpen -or $null -eq $App.UI.comboCount.SelectedItem) { return }
        $selCount = [int]($App.UI.comboCount.SelectedItem.Tag)
        if (-not $App.State.isEngineRunning) {
            for ($i = 1; $i -le 8; $i++) {
                $lbl = $App.UI.form.FindName("lblTor$i")
                if ($null -ne $lbl) {
                    $padded = $i.ToString().PadLeft(2,'0')
                    if ($i -le $selCount) { $lbl.Text = "Tor $padded`: Offline";   $lbl.Foreground = $_bc.ConvertFromString("#4A5568") }
                    else                  { $lbl.Text = "Tor $padded`: Disabled";  $lbl.Foreground = $_bc.ConvertFromString("#4A5568") }
                }
            }
            if ($null -ne $App.UI.txtXrayLogs) { $App.UI.txtXrayLogs.Text = "" }
            return
        }
        for ($i = 1; $i -le 8; $i++) {
            $lbl = $App.UI.form.FindName("lblTor$i")
            if ($null -eq $lbl) { continue }
            $padded = $i.ToString().PadLeft(2,'0')
            if ($i -gt $selCount) { $lbl.Text = "Tor $padded`: Disabled"; $lbl.Foreground = $_bc.ConvertFromString("#4A5568"); continue }
            $logPath = Get-AppPath "Data\Tors\Tor$i\tor.log"
            if (Test-Path $logPath) {
                try {
                    $fs = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $sr = New-Object System.IO.StreamReader($fs)
                    $content = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
                    $pm = [regex]::Matches($content, 'Bootstrapped (\d+)%')
                    if ($pm.Count -gt 0) {
                        $pct = $pm[$pm.Count-1].Groups[1].Value
                        $lbl.Text       = "Tor $padded`: $pct%"
                        $lbl.Foreground = if ($pct -eq "100") { $App.UI.brGreen } else { $_bc.ConvertFromString("#F6AD55") }
                    } else { $lbl.Text = "Tor $padded`: Booting..."; $lbl.Foreground = $App.UI.brGray }
                } catch {}
            } else { $lbl.Text = "Tor $padded`: Waiting..."; $lbl.Foreground = $App.UI.brGray }
        }
        $xrayLog = Get-AppPath "Data\Xray\access.log"
        if (Test-Path $xrayLog) {
            try {
                $fs = New-Object System.IO.FileStream($xrayLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr = New-Object System.IO.StreamReader($fs)
                $content = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
                $lines   = $content -split "`r?`n" | Where-Object { $_ -match "accepted|proxy" }
                $cleaned = ($lines | Select-Object -Last 15) | ForEach-Object { $_ -replace "^.*?\s\d{2}:\d{2}:\d{2}\s+(127\.0\.0\.1:\d+\s+)?","" }
                if ($null -ne $App.UI.txtXrayLogs) { $App.UI.txtXrayLogs.Text = $cleaned -join "`n"; $App.UI.txtXrayLogs.ScrollToEnd() }
            } catch {}
        }
    } catch {}
})

# LOG AUTO-CLEANER
$logClearTimer = New-Object System.Windows.Threading.DispatcherTimer
$logClearTimer.Interval = [TimeSpan]::FromHours(2)
$logClearTimer.add_Tick({
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
$logClearTimer.Start()

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
    if ($App.UI.comboBridge.SelectedItem.Tag -eq "Custom") {
        $App.State.ignoreComboChange = $true
        if (-not (Show-CustomBridgeDialog)) { Set-ComboSelectedTag $App.UI.comboBridge $App.State.previousBridge }
        else { $App.State.previousBridge = "Custom" }
        $App.State.ignoreComboChange = $false
    } else { $App.State.previousBridge = $App.UI.comboBridge.SelectedItem.Tag }
    Save-Config
})

$App.UI.comboConfig.add_SelectionChanged({
    if ($App.State.ignoreComboChange) { return }
    if ($App.UI.comboConfig.SelectedItem.Tag -eq "Custom") {
        $App.State.ignoreComboChange = $true
        if (-not (Show-ExitNodeDialog)) { Set-ComboSelectedTag $App.UI.comboConfig $App.State.previousConfig }
        else { $App.State.previousConfig = "Custom" }
        $App.State.ignoreComboChange = $false
    } else { $App.State.previousConfig = $App.UI.comboConfig.SelectedItem.Tag }
    Save-Config
})

$App.UI.comboCount.add_SelectionChanged({ Save-Config })

#  BUTTON EVENTS
$App.UI.btnStatsPanel.add_Click({ if ($App.State.isConnected) { Start-GeoPing } })
$App.UI.btnAction.add_Click({
    if ($App.State.isConnected -or $App.UI.btnActionMainText.Text -eq "CONNECTING") { Stop-AllEngines } else { Start-Engines }
})
$App.UI.btnAutoStartMain.Add_Click({
    $App.Config.autoStart = -not $App.Config.autoStart
    Set-AutoConnectState $App.Config.autoStart $true
    Save-Config
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
        $sc.TargetPath = Get-AppPath "Launch Multiplexer.exe"; $sc.WorkingDirectory = $App.Config.baseDir; $sc.Save()
        [System.Windows.Forms.MessageBox]::Show("Desktop shortcut created successfully!", "Success")
    } catch { [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)", "Error") }
})
$App.UI.btnCloseLogs.add_Click({
    if ($App.State.isLogsOpen) {
        $App.State.isLogsOpen = $false
        Set-WpfToggleState $App.UI.btnLogsTog $false "HIDE" "SHOW"
        Update-WindowSize; Save-Config
    }
})

$toggleModeAction = {
    param($mode)
    if ($App.Config.lastXrayMode -ne $mode) {
        $App.Config.lastXrayMode = $mode
        Update-RoutingToggle; Save-Config
        if ($App.State.isConnected) { Restart-Xray $mode }
    }
}
$App.UI.btnProxyMode.add_Click({ & $toggleModeAction "Proxy Mode"  })
$App.UI.btnClearProxy.add_Click({ & $toggleModeAction "Clear Proxy" })
$App.UI.btnVpnMode.add_Click({ & $toggleModeAction "VPN Mode"    })

$App.UI.btnV2rayTog.Add_Click({
    if (-not $App.Config.enableV2rayChain -and [string]::IsNullOrWhiteSpace($App.Config.v2rayChainJson)) {
        if (-not (Show-V2rayDialog)) { return }
    }
    $App.Config.enableV2rayChain = -not $App.Config.enableV2rayChain
    Set-WpfToggleState $App.UI.btnV2rayTog $App.Config.enableV2rayChain
    Save-Config
    if ($App.State.isConnected) { Restart-Xray $App.Config.lastXrayMode }
})
$App.UI.btnV2rayLbl.Add_Click({ Show-V2rayDialog | Out-Null; Set-WpfToggleState $App.UI.btnV2rayTog $App.Config.enableV2rayChain })

$App.UI.btnDirectTog.Add_Click({
    $newState = -not $App.Config.enableDirect
    if ($newState -and -not ([string]::IsNullOrWhiteSpace($App.Config.lastManualSplit) -eq $false -or [string]::IsNullOrWhiteSpace($App.Config.lastAppSplit) -eq $false)) {
        if (-not (Show-DirectRulesDialog)) { return }
    }
    $App.Config.enableDirect = $newState
    Set-WpfToggleState $App.UI.btnDirectTog $App.Config.enableDirect
    Save-Config
    if ($App.State.isConnected) { Restart-Xray $App.Config.lastXrayMode }
})
$App.UI.btnDirectLbl.Add_Click({ Show-DirectRulesDialog | Out-Null })

$App.UI.btnOutboundTog.Add_Click({
    if ($App.State.isConnected) { [System.Windows.Forms.MessageBox]::Show("Disconnect first.", "Action Denied", 0, 48); return }
    $newState = -not $App.Config.enableOutboundProxy
    if ($newState -and [string]::IsNullOrWhiteSpace($App.Config.outboundProxyAddress)) {
        if (-not (Show-OutboundProxyDialog)) { return }
    }
    $App.Config.enableOutboundProxy = $newState
    Set-WpfToggleState $App.UI.btnOutboundTog $App.Config.enableOutboundProxy
    Save-Config
})
$App.UI.btnOutboundLbl.Add_Click({ Show-OutboundProxyDialog | Out-Null; Set-WpfToggleState $App.UI.btnOutboundTog $App.Config.enableOutboundProxy })

$App.UI.btnDohTog.Add_Click({
    if ($App.State.isConnected) { [System.Windows.Forms.MessageBox]::Show("Disconnect first.", "Action Denied", 0, 48); return }
    if ($App.Config.enableTorDoh -or $App.Config.enableUpstreamDoh) {
        $App.Config.enableTorDoh = $false; $App.Config.enableUpstreamDoh = $false
        Set-WpfToggleState $App.UI.btnDohTog $false; Save-Config; Evaluate-ProxyExclusivity
    } else {
        if (-not (Show-DohDialog)) { Set-WpfToggleState $App.UI.btnDohTog $false }
        else { Set-WpfToggleState $App.UI.btnDohTog ($App.Config.enableTorDoh -or $App.Config.enableUpstreamDoh); Save-Config; Evaluate-ProxyExclusivity }
    }
})
$App.UI.btnDohLbl.Add_Click({ $App.UI.btnDohTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

# Simple toggles
$App.UI.btnBootTog.Add_Click({
    $App.Config.launchOnBoot = -not $App.Config.launchOnBoot
    Set-WpfToggleState $App.UI.btnBootTog $App.Config.launchOnBoot; Update-BootShortcut; Save-Config
})
$App.UI.btnDebugTog.Add_Click({
    $App.Config.debugMode = -not $App.Config.debugMode
    Set-WpfToggleState $App.UI.btnDebugTog $App.Config.debugMode
})
$App.UI.btnTrayTog.Add_Click({
    $App.Config.minimizeToTray = -not $App.Config.minimizeToTray
    Set-WpfToggleState $App.UI.btnTrayTog $App.Config.minimizeToTray; Save-Config
})
$App.UI.btnLogsTog.Add_Click({
    $App.State.isLogsOpen = -not $App.State.isLogsOpen
    Set-WpfToggleState $App.UI.btnLogsTog $App.State.isLogsOpen "HIDE" "SHOW"; Update-WindowSize; Save-Config
})
$App.UI.btnAdBlockTog.Add_Click({
    $App.Config.enableAdBlock = -not $App.Config.enableAdBlock
    Set-WpfToggleState $App.UI.btnAdBlockTog $App.Config.enableAdBlock; Save-Config
    if ($App.State.isConnected) { Restart-Xray $App.Config.lastXrayMode }
})

# Label → toggle relay
$App.UI.btnBootLbl.Add_Click({    $App.UI.btnBootTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$App.UI.btnDebugLbl.Add_Click({   $App.UI.btnDebugTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$App.UI.btnTrayLbl.Add_Click({    $App.UI.btnTrayTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$App.UI.btnLogsLbl.Add_Click({    $App.UI.btnLogsTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$App.UI.btnAdBlockLbl.Add_Click({ $App.UI.btnAdBlockTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

#  WINDOW CLOSE / CONTENT RENDERED
$App.UI.form.add_Closing({
    $App.Runtime.statsTimer.Stop()
    $logTimer.Stop()
    $logClearTimer.Stop()
    if ($null -ne $App.Runtime.wavePhysicsTimer) { $App.Runtime.wavePhysicsTimer.Stop() }
    if ($null -ne $App.Runtime.waveHoldTimer)    { $App.Runtime.waveHoldTimer.Stop() }
    if ($null -ne $App.Runtime.hideAdvTimer)     { $App.Runtime.hideAdvTimer.Stop() }
    if ($null -ne $App.Runtime.hideLogTimer)     { $App.Runtime.hideLogTimer.Stop() }
    if ($null -ne $App.Runtime.pingTimer)        { $App.Runtime.pingTimer.Stop() }
    
    try {
        if ($null -ne $App.Runtime.statsWebClient) {
            $App.Runtime.statsWebClient.CancelAsync()
            $App.Runtime.statsWebClient.Dispose()
            $App.Runtime.statsWebClient = $null
        }
    } catch {}
    
    Stop-AllEngines $true
    if ($null -ne $App.Runtime.sysTrayIcon) {
        $App.Runtime.sysTrayIcon.Visible = $false
        $App.Runtime.sysTrayIcon.Dispose()
    }
})

$App.UI.form.add_Closed({ [Environment]::Exit(0) })

$App.UI.form.add_ContentRendered({
    try {
        if ($App.State.appInitialized) { return }
        $App.State.appInitialized = $true
        Check-UpdateSilent
        if ($App.Config.autoStart) {
            $animT = New-Object System.Windows.Threading.DispatcherTimer
            $animT.Interval = [TimeSpan]::FromMilliseconds(150)
            $animT.add_Tick({ $animT.Stop(); Set-AutoConnectState $true $true }.GetNewClosure())
            $animT.Start()
        }
        
        # Missing launcher check
        if (-not (Test-Path (Get-AppPath "Launch Multiplexer.exe"))) {
            $ix = @"
                <TextBlock Text="Your installation is missing 'Launch Multiplexer.exe'.&#x0a;&#x0a;Please download the latest full release from GitHub." Canvas.Left="15" Canvas.Top="35" Width="350" TextWrapping="Wrap" FontSize="11" Foreground="{StaticResource TextMain}"/>
                <Button Name="btnGit" Content="Open GitHub" Canvas.Left="15" Canvas.Top="132" Width="130" Height="25" Style="{StaticResource SaveButton}"/>
                <Button Name="btnCancel" Content="Close" Canvas.Left="275" Canvas.Top="132" Width="90" Height="25" IsCancel="True"/>
"@
            $onLoad = {
                param($d)
                $d.FindName("btnGit").Add_Click({ Start-Process "https://github.com/RichTiTAN/Tor-Multiplexer"; $d.Close() }.GetNewClosure())
            }
            Show-AppDialog -Title "MISSING CORE COMPONENT" -Width 420 -Height 240 -InnerXaml $ix -OnLoad $onLoad | Out-Null
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
Update-WaveAnimation -State "Idle"
if ($null -ne $App.UI.form) {
    try { $App.UI.form.ShowDialog() | Out-Null }
    catch { [System.Windows.Forms.MessageBox]::Show("ShowDialog failed: $($_.Exception.Message)") }
} else {
    [System.Windows.Forms.MessageBox]::Show("Main Form is NULL — XAML parse failed.")
}