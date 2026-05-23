Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
# ASSEMBLIES 
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

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

# LOCK SCOPE FOR EVENT HANDLERS
$global:baseDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($global:baseDir)) { $global:baseDir = Get-Location }
Set-Location $global:baseDir

# PATH HELPER
function Get-AppPath {
    param([string]$Path)
    Join-Path $global:baseDir $Path
}
$global:scriptPath = $PSCommandPath
if ([string]::IsNullOrEmpty($global:scriptPath)) { 
    $global:scriptPath = Get-AppPath "multiplexer.ps1" 
}

# SYSTEM PROXY REFRESH API
if (-not ("Win32.WinInet" -as [type])) {
    $MethodDefinition = @'
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int lpdwBufferLength);
'@
    Add-Type -MemberDefinition $MethodDefinition -Name 'WinInet' -Namespace 'Win32' -PassThru | Out-Null
}

# VERSION CONTROL & GLOBALS 
$global:currentVersion = "5.1.1" 
$repoRawUrl = "https://raw.githubusercontent.com/RichTiTAN/Tor-Multiplexer/main/multiplexer.ps1"
$global:forceManualUpdate = $true
$global:minAutoUpdateVersion = "5.1.0"
$global:abortBoot = $false
$global:isConnected = $false
$global:isEngineRunning = $false
$global:cmdDebugPid = $null 
$global:cmdDebugPid2 = $null 
$global:xrayDohPid = $null
$global:lastTotalBytes = 0
$global:sessionDataBytes = 0
$global:sessionStartTime = $null
$global:appInitialized = $false
$global:isAdvancedOpen = $false
$global:isLogsOpen = $false
$global:ignoreComboChange = $false
$global:isGeoTracing = $false  # FIX: explicit initialization

# Stats Smoothing Buffer
$global:speedSamples = @(0, 0, 0, 0, 0)
$global:minimizeToTray = $false
$global:enableAdBlock = $false
$global:lastAppSplit = ""
$global:lastBlockSplit = ""

# CONFIGURATION & PATHS
$cfgFile = Get-AppPath "multiplexer_settings.json"
$xrayDir = Get-AppPath "Data\Xray"
$haPath  = Get-AppPath "Data\HAproxy"
$sbDir   = Get-AppPath "Data\sing_box"
$script:autoStart = $true
$script:launchOnBoot = $false
$script:debugMode = $false 
$lastConfig = "Stable"
$lastBridge = "meek_lite"
$lastCount = "6"
$global:lastXrayMode = "Proxy Mode"
$global:lastManualSplit = ""
$global:enableDirect = $false
$global:customBridgeLine = ""
$global:v2rayChainJson = ""
$global:enableV2rayChain = $false
$global:outboundProxyAddress = ""
$global:outboundProxyPort = ""
$global:outboundProxyType = "SOCKS5"
$global:enableOutboundProxy = $false
$global:outboundProxyUser = ""
$global:outboundProxyPass = ""
$global:enableOutboundAuth = $false
$global:enableTorDoh = $false
$global:torDohUrl = "https://cloudflare-dns.com/dns-query"
$global:enableUpstreamDoh = $false
$global:upstreamDohUrl = "https://cloudflare-dns.com/dns-query"
$global:customExitCountry = "us"
$isFirstLaunch = $true 

if (Test-Path $cfgFile) {
    $isFirstLaunch = $false
    try {
        $s = Get-Content $cfgFile -Raw | ConvertFrom-Json
        if ($null -ne $s.AutoStart) { $script:autoStart = [bool]$s.AutoStart }
        if ($null -ne $s.LaunchOnBoot) { $script:launchOnBoot = [bool]$s.LaunchOnBoot }
        $globalVars = @{
            "LastConfig" = "lastConfig"; "SelectedBridge" = "lastBridge"; 
            "InstanceCount" = "lastCount"; "ManualSplit" = "lastManualSplit";
            "AppSplit" = "lastAppSplit"; "BlockSplit" = "lastBlockSplit";
            "EnableDirect" = "enableDirect"; "CustomBridgeLine" = "customBridgeLine";
            "V2rayChainJson" = "v2rayChainJson"; "EnableV2rayChain" = "enableV2rayChain";
            "EnableOutboundProxy" = "enableOutboundProxy"; "OutboundProxyAddress" = "outboundProxyAddress";
            "OutboundProxyPort" = "outboundProxyPort"; "OutboundProxyType" = "outboundProxyType";
            "OutboundProxyUser" = "outboundProxyUser"; "OutboundProxyPass" = "outboundProxyPass";
            "EnableOutboundAuth" = "enableOutboundAuth"; "EnableTorDoh" = "enableTorDoh";
            "TorDohUrl" = "torDohUrl"; "EnableUpstreamDoh" = "enableUpstreamDoh";
            "UpstreamDohUrl" = "upstreamDohUrl"; "CustomExitCountry" = "customExitCountry";
            "MinimizeToTray" = "minimizeToTray"; "EnableAdBlock" = "enableAdBlock"; "XrayMode" = "lastXrayMode"
        }
        foreach ($key in $globalVars.Keys) {
            if ($null -ne $s.$key) {
                Set-Variable -Name $globalVars[$key] -Value $s.$key -Scope Global -Force
            }
        }
        if ($lastConfig -eq "Stable" -or $lastConfig -eq "Fast") {
            $lastConfig = "Optimized"
        }
    } catch {
        Write-Host "Config Load Error: $($_.Exception.Message)"
    }
}

$lanIp = "UNKNOWN"
$ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { 
    $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notmatch '^127\.' -and $_.ToString() -notmatch '^169\.254\.' 
}
if ($ips) { $lanIp = $ips[0].ToString() }

# THEME BRUSHES FOR WPF & WINFORMS MODALS
$bc = New-Object System.Windows.Media.BrushConverter
$brushActiveRouting = $bc.ConvertFromString("#80646B75")
$brushInactiveRouting = [System.Windows.Media.Brushes]::Transparent
$global:brushGreen = $bc.ConvertFromString("#68D391")
$global:brushGray = $bc.ConvertFromString("#A0AEC0")

# SHARED DIALOG RESOURCES & MASTER BUILDER
$global:sharedDialogResources = @"
    <Window.Resources>
        <SolidColorBrush x:Key="BgDark" Color="#1A1A1B"/>
        <SolidColorBrush x:Key="BgPanel" Color="#121417"/>
        <SolidColorBrush x:Key="BgInput" Color="#0A0C0F"/>
        <SolidColorBrush x:Key="BorderMain" Color="#2D3748"/>
        <SolidColorBrush x:Key="BorderLight" Color="#3A3F44"/>
        <SolidColorBrush x:Key="TextMain" Color="#E2E8F0"/>
        <SolidColorBrush x:Key="TextMuted" Color="#A0AEC0"/>
        <SolidColorBrush x:Key="TextGreen" Color="#68D391"/>
        <SolidColorBrush x:Key="ColorOk" Color="#4E7A5E"/>
        <SolidColorBrush x:Key="ColorHover" Color="#5F9774"/>
        <SolidColorBrush x:Key="BtnStandard" Color="#3A3F44"/>
        <SolidColorBrush x:Key="BtnHover" Color="#4A5568"/>
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

function Show-AppDialog {
    param([string]$Title, [int]$Width, [int]$Height, [string]$InnerXaml, [scriptblock]$OnLoad, [scriptblock]$OnSave)
    $bW = $Width - 30
    $bH = $Height - 54
    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="$Title" Height="$Height" Width="$Width" 
            WindowStartupLocation="CenterOwner" Background="#1A1A1B" Foreground="#E2E8F0"
            ResizeMode="NoResize" FontFamily="Segoe UI" ShowInTaskbar="False">
        $global:sharedDialogResources
        <Canvas>
            <Border Name="borderMain" Canvas.Left="12" Canvas.Top="12" Width="$bW" Height="$bH" 
                    Background="{StaticResource BgPanel}" CornerRadius="4" BorderBrush="{StaticResource BorderMain}" BorderThickness="1">
                <Canvas>
                    <TextBlock Text="$Title" Canvas.Left="15" Canvas.Top="12" FontSize="10" Foreground="{StaticResource TextMuted}" FontWeight="Bold"/>
                    $InnerXaml
                </Canvas>
            </Border>
        </Canvas>
    </Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Parse($xaml)
    $dlg.Owner = $form
    
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
    $dlg.Add_Loaded({
        if ($null -ne $OnLoad) { & $OnLoad $dlg }
    }.GetNewClosure())
    return $dlg.ShowDialog() -eq $true
}

# EVENT HELPER
function Bind-ToggleEvent {
    param($lbl, $btn, [scriptblock]$action)
    $boundAction = {
        param($sender, $eventArgs)
        $eventArgs.Handled = $true
        & $action
    }.GetNewClosure()
    if ($null -ne $btn) { $btn.Add_Click($boundAction) }
    if ($null -ne $lbl -and $null -ne $btn) { $lbl.Add_Click($boundAction) }
}

# WPF XAML UI
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
                        <EasingColorKeyFrame Value="#803A70B0" KeyTime="0:0:0" />
                        <EasingColorKeyFrame Value="#807030A0" KeyTime="0:0:20" /> 
                        <EasingColorKeyFrame Value="#80A03030" KeyTime="0:0:40" />
                        <EasingColorKeyFrame Value="#803A70B0" KeyTime="0:1:0" />
                    </ColorAnimationUsingKeyFrames>
                    <DoubleAnimationUsingKeyFrames Storyboard.TargetName="bgTransform" Storyboard.TargetProperty="X" Duration="0:0:45" RepeatBehavior="Forever" AutoReverse="True">
                        <EasingDoubleKeyFrame Value="0" KeyTime="0:0:0" />
                        <EasingDoubleKeyFrame Value="250" KeyTime="0:0:15" />
                        <EasingDoubleKeyFrame Value="50" KeyTime="0:0:30" />
                        <EasingDoubleKeyFrame Value="-100" KeyTime="0:0:45" />
                    </DoubleAnimationUsingKeyFrames>
                    <DoubleAnimationUsingKeyFrames Storyboard.TargetName="bgTransform" Storyboard.TargetProperty="Y" Duration="0:0:45" RepeatBehavior="Forever" AutoReverse="True">
                        <EasingDoubleKeyFrame Value="0" KeyTime="0:0:0" />
                        <EasingDoubleKeyFrame Value="150" KeyTime="0:0:20" />
                        <EasingDoubleKeyFrame Value="-50" KeyTime="0:0:35" />
                        <EasingDoubleKeyFrame Value="80" KeyTime="0:0:45" />
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
                            <ToggleButton Name="ToggleButton" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Focusable="False" Cursor="Hand"  IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"  ClickMode="Press">
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
                                    <Style TargetType="TextBlock">
                                        <Setter Property="Foreground" Value="#E2E8F0"/>
                                    </Style>
                                </ContentPresenter.Resources>
                            </ContentPresenter>
                            <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Border Name="DropDownBorder" Background="#121417" BorderThickness="1" BorderBrush="#3A3F44" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="300">
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
                </Trigger>
            </Style.Triggers>
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
                            <Border.RenderTransform>
                                <TranslateTransform Y="-0.5" />
                            </Border.RenderTransform>
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
            <Ellipse.Effect>
                <BlurEffect Radius="80" KernelType="Gaussian" />
            </Ellipse.Effect>
            <Ellipse.Fill>
                <RadialGradientBrush>
                    <GradientStop x:Name="bgGlow" Color="#601A3A6A" Offset="0"/> 
                    <GradientStop Color="#001A1A1B" Offset="1"/>
                </RadialGradientBrush>
            </Ellipse.Fill>
            <Ellipse.RenderTransform>
                <TranslateTransform x:Name="bgTransform" X="0" Y="0"/>
            </Ellipse.RenderTransform>
        </Ellipse>
        <Border Background="#8C121417" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4" Canvas.Left="20" Canvas.Top="15" Width="550" Height="200">
            <Canvas>
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
                                                            <TextBlock.Foreground>
                                                                <SolidColorBrush Color="#A0AEC0"/>
                                                            </TextBlock.Foreground>
                                                            <TextBlock.RenderTransform>
                                                                <TranslateTransform x:Name="transAutoConnect" X="0"/>
                                                            </TextBlock.RenderTransform>
                                                        </TextBlock>
                                                        <TextBlock x:Name="txtOn" Text="ON" FontSize="10" FontWeight="Bold" Foreground="#68D391" HorizontalAlignment="Center" VerticalAlignment="Center" Panel.ZIndex="-1" Opacity="0">
                                                            <TextBlock.RenderTransform>
                                                                <TranslateTransform x:Name="transOn" X="0"/>
                                                            </TextBlock.RenderTransform>
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
                                                        <TextBlock.Foreground>
                                                            <SolidColorBrush Color="#A0AEC0"/>
                                                        </TextBlock.Foreground>
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
        <Border Name="UnifiedPanel" Canvas.Left="20" Canvas.Top="230" Width="550" Height="65" Background="#8C121417" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4">
            <Canvas>
                <TextBlock Name="lblSocksTitle" Text="MIXED PORT" Canvas.Left="10" Canvas.Top="10" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0"/>
                <TextBlock Name="lblSocksDataIPs" Text="Waiting for connection..." Canvas.Left="10" Canvas.Top="26" FontSize="12" FontFamily="Consolas" FontWeight="Bold" Foreground="#68D391"/>
                <TextBlock Name="lblSocksDataTags" Text="" Canvas.Left="200" Canvas.Top="26" FontSize="12" FontFamily="Consolas" FontWeight="Bold" Foreground="#68D391" TextAlignment="Right" Width="60"/>
                <Rectangle Canvas.Left="275" Canvas.Top="0" Width="1" Height="63" Fill="#2D3748"/>
                <TextBlock Name="lblStatsTitle" Text="STATS" Canvas.Left="285" Canvas.Top="10" FontSize="10" FontWeight="Bold" Foreground="#A0AEC0"/>
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
        <Canvas Name="AdvancedCanvas" Canvas.Left="0" Canvas.Top="205" Opacity="0" Visibility="Hidden">
            <Border Name="AdvancedBorder" Background="#8C121417" BorderBrush="#2D3748" BorderThickness="1" CornerRadius="4" ClipToBounds="True" Canvas.Left="20" Canvas.Top="25" Width="550" Height="194">
                <Canvas>
                    <Border Width="548" Height="26" Canvas.Left="0" Canvas.Top="0" Background="#990A0C0F" CornerRadius="3,3,0,0" BorderBrush="#2D3748" BorderThickness="0,0,0,1"/>
                    <TextBlock Text="ROUTING" Canvas.Left="0" Canvas.Top="6" Width="275" TextAlignment="Center" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    <TextBlock Text="SYSTEM" Canvas.Left="275" Canvas.Top="6" Width="275" TextAlignment="Center" FontSize="10" Foreground="#A0AEC0" FontWeight="Bold"/>
                    <Rectangle Canvas.Left="275" Canvas.Top="0" Width="1" Height="194" Fill="#2D3748"/>
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
                    <TextBlock Name="lblTor1" Text="Tor 01: Offline" Canvas.Left="15" Canvas.Top="30" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor2" Text="Tor 02: Offline" Canvas.Left="15" Canvas.Top="48" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor3" Text="Tor 03: Offline" Canvas.Left="15" Canvas.Top="66" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor4" Text="Tor 04: Offline" Canvas.Left="15" Canvas.Top="84" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor5" Text="Tor 05: Offline" Canvas.Left="155" Canvas.Top="30" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor6" Text="Tor 06: Offline" Canvas.Left="155" Canvas.Top="48" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor7" Text="Tor 07: Offline" Canvas.Left="155" Canvas.Top="66" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <TextBlock Name="lblTor8" Text="Tor 08: Offline" Canvas.Left="155" Canvas.Top="84" Foreground="#4A5568" FontSize="12" FontFamily="Consolas"/>
                    <Rectangle Name="logSeparator" Canvas.Left="15" Canvas.Top="110" Width="270" Height="1" Fill="#2D3748" />
                    <TextBlock Name="lblConnTitle" Text="CONNECTIONS" Canvas.Left="15" Canvas.Top="120" Foreground="#A0AEC0" FontSize="10" FontWeight="Bold" />
                    <TextBox Name="txtXrayLogs" Canvas.Left="15" Canvas.Top="138" Width="270" Height="321" 
                             Background="#990A0C0F" Foreground="#68D391" BorderBrush="#2D3748" BorderThickness="1" 
                             FontSize="10" TextWrapping="Wrap" VerticalScrollBarVisibility="Hidden" HorizontalScrollBarVisibility="Hidden" IsReadOnly="True" FontFamily="Consolas" />
                </Canvas>
            </Border>
        </Canvas>
    </Canvas>
</Window>
"@

# INTERFACE LAUNCH COMPILER
try {
    $form = [Windows.Markup.XamlReader]::Parse($xaml)
    $lblTitleText = $form.FindName("lblTitleText")
    $lblTitleText.Text = "TOR MULTIPLEXER v$global:currentVersion"
    if (Test-Path (Get-AppPath "icon.ico")) { 
        $form.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([uri](Get-AppPath "icon.ico")) 
    }
} catch {
    [System.Windows.Forms.MessageBox]::Show("App failed to compile the layout window.`n`nError: $($_.Exception.Message)", "Launch Crash Debugger", 0, 16)
    [Environment]::Exit(0)
}

# ENFORCE NATIVE DARK TITLE BAR
$form.Add_SourceInitialized({
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($form)).Handle
        [DWM]::DarkTitleBar($hwnd)
    } catch {}
})

# MAP WPF ELEMENTS TO POWERSHELL
$comboBridge        = $form.FindName("comboBridge")
$comboConfig        = $form.FindName("comboConfig")
$comboCount         = $form.FindName("comboCount")
$btnAction          = $form.FindName("btnAction")
$btnActionMainText  = $form.FindName("btnActionMainText")
$btnActionSubText   = $form.FindName("btnActionSubText")
$wavePath1          = $form.FindName("wavePath1")
$wavePath2          = $form.FindName("wavePath2")
$waveTrans1         = $form.FindName("waveTrans1")
$waveTrans2         = $form.FindName("waveTrans2")
$btnProxyMode       = $form.FindName("btnProxyMode")
$btnVpnMode         = $form.FindName("btnVpnMode")
$vpnToolTip         = $form.FindName("vpnToolTip")
$btnClearProxy      = $form.FindName("btnClearProxy")
$btnAutoStartMain   = $form.FindName("btnAutoStartMain")
$btnAdvMain         = $form.FindName("btnAdvMain")
$lblSessionTime     = $form.FindName("lblSessionTime")
$btnDirectLbl       = $form.FindName("btnDirectLbl")
$btnDirectTog       = $form.FindName("btnDirectTog")
$btnV2rayLbl        = $form.FindName("btnV2rayLbl")
$btnV2rayTog        = $form.FindName("btnV2rayTog")
$btnOutboundLbl     = $form.FindName("btnOutboundLbl")
$btnOutboundTog     = $form.FindName("btnOutboundTog")
$btnDohLbl          = $form.FindName("btnDohLbl")
$btnDohTog          = $form.FindName("btnDohTog")
$btnAdBlockLbl      = $form.FindName("btnAdBlockLbl")
$btnAdBlockTog      = $form.FindName("btnAdBlockTog")
$btnBootLbl         = $form.FindName("btnBootLbl")
$btnBootTog         = $form.FindName("btnBootTog")
$btnDebugLbl        = $form.FindName("btnDebugLbl")
$btnDebugTog        = $form.FindName("btnDebugTog")
$btnTrayLbl         = $form.FindName("btnTrayLbl")
$btnTrayTog         = $form.FindName("btnTrayTog")
$btnLogsLbl         = $form.FindName("btnLogsLbl")
$btnLogsTog         = $form.FindName("btnLogsTog")
$btnDesktop         = $form.FindName("btnDesktop")
$AdvancedCanvas     = $form.FindName("AdvancedCanvas")
$AdvancedBorder     = $form.FindName("AdvancedBorder")
$LogsCanvas         = $form.FindName("LogsCanvas")
$logBorder          = $form.FindName("logBorder")
$txtXrayLogs        = $form.FindName("txtXrayLogs")
$btnCloseLogs       = $form.FindName("btnCloseLogs")
$lblTorTitle        = $form.FindName("lblTorTitle")
$logSeparator       = $form.FindName("logSeparator")
$lblConnTitle       = $form.FindName("lblConnTitle")
$lblTor1            = $form.FindName("lblTor1")
$lblTor2            = $form.FindName("lblTor2")
$lblTor3            = $form.FindName("lblTor3")
$lblTor4            = $form.FindName("lblTor4")
$lblTor5            = $form.FindName("lblTor5")
$lblTor6            = $form.FindName("lblTor6")
$lblTor7            = $form.FindName("lblTor7")
$lblTor8            = $form.FindName("lblTor8")
$UnifiedPanel       = $form.FindName("UnifiedPanel")
$lblSocksTitle      = $form.FindName("lblSocksTitle")
$lblSocksDataIPs    = $form.FindName("lblSocksDataIPs")
$lblSocksDataTags   = $form.FindName("lblSocksDataTags")
$lblStatsTitle      = $form.FindName("lblStatsTitle")
$lblStatsData       = $form.FindName("lblStatsData")
$lblGeoData         = $form.FindName("lblGeoData")
$btnStatsPanel      = $form.FindName("btnStatsPanel")
$lblTitleText       = $form.FindName("lblTitleText")
$btnTitleUpdate     = $form.FindName("btnTitleUpdate")

function Add-ComboItem($combo, $text, $tag) {
    $cbi = New-Object System.Windows.Controls.ComboBoxItem
    $cbi.Content = $text
    $cbi.Tag = $tag
    if ($tag -eq "Custom") {
        $cbi.Add_PreviewMouseLeftButtonDown({
            param($sender, $e)
            $e.Handled = $true
            $combo.IsDropDownOpen = $false
            if ($combo.Name -eq "comboBridge") {
                $global:ignoreComboChange = $true
                $combo.SelectedItem = $sender
                DoEvents
                if (-not (Show-CustomBridgeDialog)) { 
                    Set-ComboSelectedTag $combo $global:previousBridge 
                } else { 
                    $global:previousBridge = "Custom" 
                }
                Save-Config
                $global:ignoreComboChange = $false
            } elseif ($combo.Name -eq "comboConfig") {
                $global:ignoreComboChange = $true
                $combo.SelectedItem = $sender
                DoEvents
                if (-not (Show-ExitNodeDialog)) { 
                    Set-ComboSelectedTag $combo $global:previousConfig 
                } else { 
                    $global:previousConfig = "Custom" 
                }
                Save-Config
                $global:ignoreComboChange = $false
            }
        }.GetNewClosure())
    }
    $combo.Items.Add($cbi) | Out-Null
}

Add-ComboItem $comboBridge "Direct (None)" "Direct (None)"
Add-ComboItem $comboBridge "meek_lite" "meek_lite"
Add-ComboItem $comboBridge "obfs4" "obfs4"
Add-ComboItem $comboBridge "snowflake" "snowflake"
Add-ComboItem $comboBridge "Custom" "Custom"
Add-ComboItem $comboConfig "Optimized" "Optimized"
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
        if ($item.Tag -eq $tag) { 
            $combo.SelectedItem = $item
            break 
        }
    }
}

Set-ComboSelectedTag $comboBridge $lastBridge
Set-ComboSelectedTag $comboConfig $lastConfig
Set-ComboSelectedTag $comboCount $lastCount
if ($null -ne $comboBridge.SelectedItem) { 
    $global:previousBridge = $comboBridge.SelectedItem.Tag 
} else { 
    $global:previousBridge = "meek_lite" 
}
if ($null -ne $comboConfig.SelectedItem) { 
    $global:previousConfig = $comboConfig.SelectedItem.Tag 
} else { 
    $global:previousConfig = "Optimized" 
}

# WPF HELPER FUNCTIONS
function DoEvents {
    try {
        if ($null -ne $form -and $null -ne $form.Dispatcher) {
            $frame = New-Object System.Windows.Threading.DispatcherFrame
            $form.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]{
                $frame.Continue = $false
            }) | Out-Null
            [System.Windows.Threading.Dispatcher]::PushFrame($frame)
        }
    } catch {}
}

function Wait-NonBlocking($s) { 
    $end = (Get-Date).AddSeconds($s)
    while ((Get-Date) -lt $end) { 
        if ($global:abortBoot) { return }
        DoEvents
        Start-Sleep -Milliseconds 50 
    } 
}

function Set-AutoConnectState([bool]$state, [bool]$animate) {
    if ($null -eq $btnAutoStartMain) { return }
    $template = $btnAutoStartMain.Template
    if ($null -eq $template) { return }
    $trans1        = $template.FindName("transAutoConnect", $btnAutoStartMain)
    $trans2        = $template.FindName("transOn", $btnAutoStartMain)
    $txtOn         = $template.FindName("txtOn", $btnAutoStartMain)
    $txtAutoConnect = $template.FindName("txtAutoConnect", $btnAutoStartMain)
    if ($null -eq $trans1 -or $null -eq $trans2 -or $null -eq $txtAutoConnect -or $null -eq $txtOn) { return }

    $dur  = if ($animate) { New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(300)) } else { New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(0)) }
    $t1X  = if ($state) { -10.0 } else { 0.0 }
    $t2X  = if ($state) { 44.0  } else { 0.0 }
    $op   = if ($state) { 1.0   } else { 0.0 }
    $col  = if ($state) { [System.Windows.Media.ColorConverter]::ConvertFromString("#E2E8F0") } else { [System.Windows.Media.ColorConverter]::ConvertFromString("#A0AEC0") }

    $trans1.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($t1X, $dur)))
    $trans2.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($t2X, $dur)))
    $txtOn.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($op, $dur)))
    $ca = New-Object System.Windows.Media.Animation.ColorAnimation($col, $dur)
    if ($txtAutoConnect.Foreground -is [System.Windows.Media.SolidColorBrush]) {
        $clonedBrush = $txtAutoConnect.Foreground.Clone()
    } else {
        $clonedBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#A0AEC0"))
    }
    $txtAutoConnect.Foreground = $clonedBrush
    $clonedBrush.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $ca)
}

function Set-AdvState([bool]$state) {
    if ($null -eq $btnAdvMain) { return }
    $txtAdv = $btnAdvMain.Template.FindName("txtAdv", $btnAdvMain)
    if ($null -ne $txtAdv) {
        $col = if ($state) { "#E2E8F0" } else { "#A0AEC0" }
        $txtAdv.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($col))
    }
}

function Set-WpfToggleState($btn, $state, $onText = "Enabled", $offText = "Disabled") {
    $bcConverter = New-Object System.Windows.Media.BrushConverter
    $textGreen = $bcConverter.ConvertFromString("#68D391")
    $textRed   = $bcConverter.ConvertFromString("#E53E3E") 
    $textGray  = $bcConverter.ConvertFromString("#A0AEC0")

    if ($btn.Name -eq "btnLogsTog") {
        $btn.Background = [System.Windows.Media.Brushes]::Transparent
        $btn.Foreground = $textGray
        $btn.Content    = if ($state) { "HIDE" } else { "SHOW" }
    } else {
        $btn.Background = [System.Windows.Media.Brushes]::Transparent
        if ($state) { 
            $btn.Content    = $onText.ToUpper()
            $btn.Foreground = $textGreen
        } else { 
            $btn.Content    = $offText.ToUpper()
            $btn.Foreground = $textRed
        }
    }
}

# INITIAL TOGGLE STATES
$toggles = @{
    $btnDirectTog   = $global:enableDirect
    $btnV2rayTog    = $global:enableV2rayChain
    $btnOutboundTog = $global:enableOutboundProxy
    $btnDohTog      = ($global:enableTorDoh -or $global:enableUpstreamDoh)
    $btnBootTog     = $script:launchOnBoot
    $btnDebugTog    = $script:debugMode
    $btnTrayTog     = $global:minimizeToTray
    $btnAdBlockTog  = $global:enableAdBlock
}
foreach ($btn in $toggles.Keys) { 
    if ($null -ne $btn) { Set-WpfToggleState $btn $toggles[$btn] } 
}

function Force-InitialColors {
    Set-AutoConnectState $false $false 
    Set-AdvState $global:isAdvancedOpen
    Set-WpfToggleState $btnV2rayTog    $global:enableV2rayChain "Enabled" "Disabled"
    Set-WpfToggleState $btnDirectTog   $global:enableDirect "Enabled" "Disabled"
    Set-WpfToggleState $btnOutboundTog $global:enableOutboundProxy "Enabled" "Disabled"
    Set-WpfToggleState $btnDohTog      ($global:enableTorDoh -or $global:enableUpstreamDoh) "Enabled" "Disabled"
    Set-WpfToggleState $btnBootTog     $script:launchOnBoot "Enabled" "Disabled"
    Set-WpfToggleState $btnDebugTog    $script:debugMode "Enabled" "Disabled"
    Set-WpfToggleState $btnTrayTog     $global:minimizeToTray "Enabled" "Disabled"
    Set-WpfToggleState $btnAdBlockTog  $global:enableAdBlock "Enabled" "Disabled"
    Set-WpfToggleState $btnLogsTog     $global:isLogsOpen "HIDE" "SHOW"
}
Force-InitialColors

function Update-RoutingToggle {
    $btnProxyMode.Background = $brushInactiveRouting
    $btnProxyMode.Foreground = "#A0AEC0"
    $btnClearProxy.Background = $brushInactiveRouting
    $btnClearProxy.Foreground = "#A0AEC0"
    $btnVpnMode.Background = $brushInactiveRouting
    $btnVpnMode.Foreground = "#A0AEC0"
    $btnVpnMode.Cursor = [System.Windows.Input.Cursors]::Hand
    $vpnToolTip.Content = "Route your entire system's network globally through the secure tunnel."
    $vpnToolTip.Visibility = "Visible" 
    switch ($global:lastXrayMode) {
        "Proxy Mode"  { $btnProxyMode.Background  = $brushActiveRouting; $btnProxyMode.Foreground  = "#FFFFFF" }
        "VPN Mode"    { $btnVpnMode.Background    = $brushActiveRouting; $btnVpnMode.Foreground    = "#FFFFFF" }
        "Clear Proxy" { $btnClearProxy.Background = $brushActiveRouting; $btnClearProxy.Foreground = "#FFFFFF" }
    }
    $btnDirectLbl.IsEnabled = $true; $btnDirectLbl.Opacity = 1.0
    $btnDirectTog.IsEnabled = $true; $btnDirectTog.Opacity = 1.0
}
Update-RoutingToggle

function Evaluate-ProxyExclusivity {
    $isEnabled = -not $global:enableTorDoh
    $btnOutboundLbl.IsEnabled = $isEnabled; $btnOutboundLbl.Opacity = if ($isEnabled) { 1.0 } else { 0.5 }
    $btnOutboundTog.IsEnabled = $isEnabled; $btnOutboundTog.Opacity = if ($isEnabled) { 1.0 } else { 0.5 }
}
Evaluate-ProxyExclusivity

# SAFE RELATIVE BRIDGE DATABASE
$bridgeData = @{
    "meek_lite" = @{ 
        "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"
        "lines"  = @("Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN") 
    }
    "obfs4" = @{ 
        "plugin" = "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec ..\..\PluggableTransports\lyrebird.exe"
        "lines"  = @(
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
        "plugin" = "ClientTransportPlugin snowflake exec ..\..\PluggableTransports\lyrebird.exe"
        "lines"  = @(
            "Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn",
            "Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn"
        ) 
    }
}

# POP UP WINDOWS
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
        $d.FindName("txtDomains").Text = $global:lastManualSplit
        $d.FindName("txtApps").Text    = $global:lastAppSplit
        $d.FindName("txtBlock").Text   = $global:lastBlockSplit
        if ($global:lastXrayMode -eq "VPN Mode") {
            $d.FindName("txtDomains").IsEnabled = $false
            $d.FindName("txtDomains").Opacity   = 0.3
            $d.FindName("lblDomains").Text    = "Domains & IPs (Disabled in VPN Mode - Use App Bypass below)"
            $d.FindName("lblDomains").Opacity = 0.5
            $d.FindName("txtApps").Focus() | Out-Null
        } else {
            $d.FindName("txtDomains").Focus() | Out-Null
        }
    }
    $onSave = {
        param($d)
        $global:lastManualSplit = $d.FindName("txtDomains").Text.Trim()
        $global:lastAppSplit    = $d.FindName("txtApps").Text.Trim()
        $global:lastBlockSplit  = $d.FindName("txtBlock").Text.Trim()
    }
    $result = Show-AppDialog -Title "SPLIT TUNNELING AND PRIVACY ENGINE" -Width 480 -Height 400 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
    if ($result) {
        $hasRulesNow = -not [string]::IsNullOrWhiteSpace($global:lastManualSplit) -or -not [string]::IsNullOrWhiteSpace($global:lastAppSplit)
        if (-not $global:enableDirect -and $hasRulesNow) {
            $global:enableDirect = $true
            if ($null -ne $btnDirectTog) { Set-WpfToggleState $btnDirectTog $true }
        }
        Save-Config
        if ($global:isConnected) { Restart-Xray $global:lastXrayMode }
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
        $t.Text = $global:customBridgeLine
        $t.Focus() | Out-Null
        $t.CaretIndex = $t.Text.Length
    }
    $onSave = {
        param($d)
        $global:customBridgeLine = $d.FindName("txtInput").Text.Trim()
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
        $t.Text = $global:v2rayChainJson
        $t.Focus() | Out-Null
        $t.CaretIndex = $t.Text.Length
        $d.FindName("btnImport").Add_Click({
            $fd = New-Object System.Windows.Forms.OpenFileDialog
            $fd.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
            if ($fd.ShowDialog() -eq "OK") { $t.Text = Get-Content $fd.FileName -Raw }
        }.GetNewClosure())
    }
    $onSave = {
        param($d)
        $txt = $d.FindName("txtInput").Text
        if ([string]::IsNullOrWhiteSpace($txt)) { $global:v2rayChainJson = ""; return $true }
        try { 
            $parsed  = $txt | ConvertFrom-Json 
            $testNode = if ($null -ne $parsed.outbounds) { $parsed.outbounds[0] } else { $parsed }
            if (-not $testNode.protocol) { throw "Missing Protocol" }
            $global:v2rayChainJson = $txt.Trim()
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
            <ComboBoxItem Content="SOCKS5"/>
            <ComboBoxItem Content="HTTPS"/>
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
            <ComboBoxItem Content="Disabled"/>
            <ComboBoxItem Content="Enabled"/>
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
        $cmbProxyType = $dlg.FindName("cmbProxyType")
        $cmbAuth      = $dlg.FindName("cmbAuth")
        $txtAddr      = $dlg.FindName("txtAddr")
        $txtPort      = $dlg.FindName("txtPort")
        $txtUser      = $dlg.FindName("txtUser")
        $txtPass      = $dlg.FindName("txtPass")
        $panAuth      = $dlg.FindName("panAuth")
        $btnOk        = $dlg.FindName("btnOk")
        $btnCancel    = $dlg.FindName("btnCancel")
        $borderMain   = $dlg.FindName("borderMain")
        $script:tempType = if ([string]::IsNullOrEmpty($global:outboundProxyType)) { "SOCKS5" } else { $global:outboundProxyType }
        $txtAddr.Text = $global:outboundProxyAddress
        $txtPort.Text = $global:outboundProxyPort
        $txtUser.Text = $global:outboundProxyUser
        $txtPass.Text = $global:outboundProxyPass
        foreach ($item in $cmbProxyType.Items) { if ($item.Content -eq $script:tempType) { $cmbProxyType.SelectedItem = $item; break } }
        $authTarget = if ($global:enableOutboundAuth) { "Enabled" } else { "Disabled" }
        foreach ($item in $cmbAuth.Items) { if ($item.Content -eq $authTarget) { $cmbAuth.SelectedItem = $item; break } }
        $isFirstLoad = $true
        $evaluateAuthView = {
            $isEnabled  = ($null -ne $cmbAuth.SelectedItem -and $cmbAuth.SelectedItem.Content -eq "Enabled")
            $targetH      = if ($isEnabled) { 320.0 } else { 263.0 }
            $targetBorderH = if ($isEnabled) { 267.0 } else { 210.0 }
            $targetBtnTop  = if ($isEnabled) { 225.0 } else { 168.0 }
            $targetOpac   = if ($isEnabled) { 1.0   } else { 0.0   }
            if ($isFirstLoad) {
                $dlg.Height = $targetH; $borderMain.Height = $targetBorderH
                $btnOk.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$targetBtnTop)
                $btnCancel.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$targetBtnTop)
                $panAuth.Opacity    = $targetOpac
                $panAuth.Visibility = if ($isEnabled) { "Visible" } else { "Hidden" }
            } else {
                if ($isEnabled) { $panAuth.Visibility = "Visible" }
                $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(250))
                $dlg.BeginAnimation([System.Windows.Window]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetH, $dur)))
                $borderMain.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetBorderH, $dur)))
                $btnOk.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetBtnTop, $dur)))
                $btnCancel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetBtnTop, $dur)))
                $panAuth.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation([double]$targetOpac, $dur)))
                if (-not $isEnabled) {
                    $hideTimer = New-Object System.Windows.Threading.DispatcherTimer
                    $hideTimer.Interval = [TimeSpan]::FromMilliseconds(250)
                    $hideTimer.add_Tick({ $hideTimer.Stop(); if ($cmbAuth.SelectedItem.Content -eq "Disabled") { $panAuth.Visibility = "Hidden" } }.GetNewClosure())
                    $hideTimer.Start()
                }
            }
        }.GetNewClosure()
        $cmbAuth.add_SelectionChanged({ & $evaluateAuthView }.GetNewClosure())
        $cmbProxyType.add_SelectionChanged({ 
            if ($null -ne $cmbProxyType.SelectedItem) { $script:tempType = $cmbProxyType.SelectedItem.Content }
        }.GetNewClosure())
        & $evaluateAuthView
        $isFirstLoad = $false
        $txtAddr.Focus() | Out-Null; $txtAddr.CaretIndex = $txtAddr.Text.Length
    }
    $onSave = {
        param($d)
        $global:outboundProxyAddress = $d.FindName("txtAddr").Text.Trim()
        $global:outboundProxyPort    = $d.FindName("txtPort").Text.Trim()
        $global:outboundProxyType    = $script:tempType
        $cmbAuth = $d.FindName("cmbAuth")
        $global:enableOutboundAuth   = ($null -ne $cmbAuth.SelectedItem -and $cmbAuth.SelectedItem.Content -eq "Enabled")
        $global:outboundProxyUser    = $d.FindName("txtUser").Text.Trim()
        $global:outboundProxyPass    = $d.FindName("txtPass").Text.Trim()
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
        $bc = New-Object System.Windows.Media.BrushConverter
        $textGreen = $bc.ConvertFromString("#68D391")
        $textRed   = $bc.ConvertFromString("#E53E3E")
        $textGray  = $bc.ConvertFromString("#A0AEC0")
        $lblWarn = $dlg.FindName("lblWarn"); $lblTor = $dlg.FindName("lblTor"); $borTor = $dlg.FindName("borTor")
        $btnTorTog = $dlg.FindName("btnTorTog"); $txtTorDoh = $dlg.FindName("txtTorDoh")
        $lblUp = $dlg.FindName("lblUp"); $borUp = $dlg.FindName("borUp")
        $btnUpTog = $dlg.FindName("btnUpTog"); $txtUpDoh = $dlg.FindName("txtUpDoh")
        $lblHint = $dlg.FindName("lblHint"); $btnOk = $dlg.FindName("btnOk"); $btnCancel = $dlg.FindName("btnCancel")
        $borderMain = $dlg.FindName("borderMain")
        $txtTorDoh.Text = $global:torDohUrl; $txtUpDoh.Text = $global:upstreamDohUrl
        $btnUpTog.Content   = if ($global:enableUpstreamDoh) { "ENABLED" } else { "DISABLED" }
        $btnUpTog.Foreground = if ($global:enableUpstreamDoh) { $textGreen } else { $textRed }
        if ($global:enableOutboundProxy) {
            $dlg.Height = 320; $borderMain.Height = 254
            $lblWarn.Visibility = "Visible"
            $lblTor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]55)
            $borTor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]75)
            $lblUp.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]110)
            $borUp.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]130)
            $lblHint.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]165)
            $btnOk.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]212)
            $btnCancel.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]212)
            $btnTorTog.Content = "DISABLED"; $btnTorTog.Foreground = $textGray
            $btnTorTog.IsEnabled = $false; $txtTorDoh.IsEnabled = $false
            $borTor.Opacity = 0.3; $lblTor.Opacity = 0.5
        } else {
            $btnTorTog.Content   = if ($global:enableTorDoh) { "ENABLED" } else { "DISABLED" }
            $btnTorTog.Foreground = if ($global:enableTorDoh) { $textGreen } else { $textRed }
            $btnTorTog.Add_Click({
                if ($this.Content -eq "DISABLED") { $this.Content = "ENABLED"; $this.Foreground = $textGreen } 
                else { $this.Content = "DISABLED"; $this.Foreground = $textRed }
            }.GetNewClosure())
        }
        $btnUpTog.Add_Click({
            if ($this.Content -eq "DISABLED") { $this.Content = "ENABLED"; $this.Foreground = $textGreen } 
            else { $this.Content = "DISABLED"; $this.Foreground = $textRed }
        }.GetNewClosure())
        $txtTorDoh.Focus() | Out-Null; $txtTorDoh.CaretIndex = $txtTorDoh.Text.Length
    }
    $onSave = {
        param($d)
        $global:enableTorDoh = ($d.FindName("btnTorTog").Content -eq "ENABLED")
        $tDoh = $d.FindName("txtTorDoh").Text
        if (-not [string]::IsNullOrWhiteSpace($tDoh)) { $global:torDohUrl = $tDoh.Trim() }
        $global:enableUpstreamDoh = ($d.FindName("btnUpTog").Content -eq "ENABLED")
        $uDoh = $d.FindName("txtUpDoh").Text
        if (-not [string]::IsNullOrWhiteSpace($uDoh)) { $global:upstreamDohUrl = $uDoh.Trim() }
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
        $cmbCountries = $d.FindName("cmbCountries")
        $countries = [ordered]@{ 
            "Argentina"="ar";"Australia"="au";"Austria"="at";"Brazil"="br";"Canada"="ca";
            "Finland"="fi";"France"="fr";"Germany"="de";"Hong Kong"="hk";
            "Iceland"="is";"India"="in";"Iran"="ir";"Italy"="it";"Japan"="jp";
            "Mexico"="mx";"Netherlands"="nl";"New Zealand"="nz";"Romania"="ro";
            "Singapore"="sg";"South Africa"="za";"South Korea"="kr";"Spain"="es";
            "Sweden"="se";"Switzerland"="ch";"United Arab Emirates"="ae";"United Kingdom"="uk";"United States"="us"
        }
        foreach ($c in $countries.Keys) { 
            $cbi = New-Object System.Windows.Controls.ComboBoxItem
            $cbi.Content = "$c ($($countries[$c].ToUpper()))"
            $cbi.Tag = $countries[$c]
            $cmbCountries.Items.Add($cbi) | Out-Null
        }
        foreach ($item in $cmbCountries.Items) {
            if ($item.Tag -eq $global:customExitCountry) { $cmbCountries.SelectedItem = $item; break }
        }
        if ($null -eq $cmbCountries.SelectedItem -and $cmbCountries.Items.Count -gt 0) { $cmbCountries.SelectedIndex = 0 }
    }
    $onSave = {
        param($d)
        $global:customExitCountry = $d.FindName("cmbCountries").SelectedItem.Tag.ToLower()
    }
    return Show-AppDialog -Title "CUSTOM EXIT-NODE ROUTING" -Width 420 -Height 210 -InnerXaml $ix -OnLoad $onLoad -OnSave $onSave
}

# CORE LOGIC
function Save-Config {
    $configData = [ordered]@{
        "AutoStart"            = [bool]$script:autoStart
        "LaunchOnBoot"         = [bool]$script:launchOnBoot
        "LastConfig"           = if ($comboConfig.SelectedItem) { $comboConfig.SelectedItem.Tag } else { $lastConfig }
        "SelectedBridge"       = $comboBridge.SelectedItem.Tag
        "InstanceCount"        = [int]$comboCount.SelectedItem.Tag
        "XrayMode"             = $global:lastXrayMode
        "ManualSplit"          = $global:lastManualSplit
        "AppSplit"             = $global:lastAppSplit
        "BlockSplit"           = $global:lastBlockSplit
        "EnableDirect"         = [bool]$global:enableDirect
        "CustomBridgeLine"     = $global:customBridgeLine
        "EnableV2rayChain"     = [bool]$global:enableV2rayChain
        "V2rayChainJson"       = $global:v2rayChainJson
        "EnableOutboundProxy"  = [bool]$global:enableOutboundProxy
        "OutboundProxyAddress" = $global:outboundProxyAddress
        "OutboundProxyPort"    = $global:outboundProxyPort
        "OutboundProxyType"    = $global:outboundProxyType
        "OutboundProxyUser"    = $global:outboundProxyUser
        "OutboundProxyPass"    = $global:outboundProxyPass
        "EnableOutboundAuth"   = [bool]$global:enableOutboundAuth
        "EnableTorDoh"         = [bool]$global:enableTorDoh
        "TorDohUrl"            = $global:torDohUrl
        "EnableUpstreamDoh"    = [bool]$global:enableUpstreamDoh
        "UpstreamDohUrl"       = $global:upstreamDohUrl
        "CustomExitCountry"    = $global:customExitCountry
        "MinimizeToTray"       = [bool]$global:minimizeToTray
        "EnableAdBlock"        = [bool]$global:enableAdBlock
    }
    try {
        $configData | ConvertTo-Json -Depth 10 | Set-Content -Path $cfgFile -Force
    } catch {
        Write-Host "Failed to save configuration: $($_.Exception.Message)"
    }
}

function Write-TorOutboundDohConfig {
    $dohUrl = $global:torDohUrl
    $dnsServer = if ($dohUrl.StartsWith("https://")) {
        try {
            $uri  = [uri]$dohUrl
            $host = $uri.Host
            $path = if ($uri.AbsolutePath -eq "/") { "/dns-query" } else { $uri.PathAndQuery }
            @{ address = "https://$host$path"; skipFallback = $true }
        } catch {
            @{ address = "https://cloudflare-dns.com/dns-query"; skipFallback = $true }
        }
    } else {
        @{ address = $dohUrl; skipFallback = $true }
    }

    $dohConfig = @{
        log      = @{ logLevel = "error" }
        dns      = @{ servers = @($dnsServer.address) }
        inbounds = @(
            @{
                listen   = "127.0.0.1"
                port     = 10820
                protocol = "socks"
                settings = @{ udp = $false }
            }
        )
        outbounds = @(
            @{ tag = "direct"; protocol = "freedom"; settings = @{} }
        )
        routing = @{
            domainStrategy = "UseIP"
            rules          = @( @{ type = "field"; network = "tcp,udp"; outboundTag = "direct" } )
        }
    }
    $dohConfig | ConvertTo-Json -Depth 10 | Set-Content (Get-AppPath "Data\Xray\tor-doh.json")
}

function Write-XrayConfig {
    $rules = @( 
        @{ type="field"; ip=@("127.0.0.0/8","::1","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16"); outboundTag="direct" } 
    )
    $blockDomains = @()
    if ($global:enableAdBlock) {
        $blockDomains += @("geosite:category-ads-all","domain:analytics.google.com","domain:google-analytics.com")
    }
    if ($global:enableDirect -and -not [string]::IsNullOrWhiteSpace($global:lastBlockSplit)) {
        $customBlocks = $global:lastBlockSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($bDomain in $customBlocks) { $blockDomains += "domain:$bDomain" }
    }
    if ($blockDomains.Count -gt 0) {
        $rules += @{ type="field"; domain=$blockDomains; outboundTag="block" }
    }
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
    $inboundArr = @( @{ 
        listen   = "0.0.0.0"; port = 10818; protocol = "mixed"
        settings = @{ udp = $true }
        sniffing = @{ enabled = $true; destOverride = @("http","tls","quic","fakedns") } 
    } )
    $outbounds = @()
    if ($global:enableV2rayChain -and -not [string]::IsNullOrWhiteSpace($global:v2rayChainJson)) {
        try {
            $v2rayParsed   = $global:v2rayChainJson | ConvertFrom-Json
            $v2rayOutbound = if ($null -ne $v2rayParsed.outbounds) { 
                $v2rayParsed.outbounds | Where-Object { $_.protocol -notin @("freedom","blackhole") } | Select-Object -First 1 
            } else { $v2rayParsed }
            $v2rayOutbound.tag = "proxy"
            if ($null -ne $v2rayOutbound.streamSettings -and $null -ne $v2rayOutbound.streamSettings.tlsSettings) {
                if (-not $v2rayOutbound.streamSettings.tlsSettings.psobject.properties.match('allowInsecure').Count) { 
                    $v2rayOutbound.streamSettings.tlsSettings | Add-Member -MemberType NoteProperty -Name "allowInsecure" -Value $true 
                } else { $v2rayOutbound.streamSettings.tlsSettings.allowInsecure = $true }
            }
            if (-not $v2rayOutbound.psobject.properties.match('proxySettings').Count) { 
                $v2rayOutbound | Add-Member -MemberType NoteProperty -Name "proxySettings" -Value @{ tag = "torProxy" } 
            } else { $v2rayOutbound.proxySettings = @{ tag = "torProxy" } }
            $outbounds += $v2rayOutbound
            $outbounds += @{ tag="torProxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } }
        } catch { 
            $outbounds += @{ tag="proxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } } 
        }
    } else { 
        $outbounds += @{ tag="proxy"; protocol="socks"; settings=@{ servers=@(@{ address="127.0.0.1"; port=10800 }) } } 
    }
    if ($global:enableAdBlock -or ($global:enableDirect -and -not [string]::IsNullOrWhiteSpace($global:lastBlockSplit))) {
        $outbounds += @{ tag="block"; protocol="blackhole"; settings=@{} }
    }
    $outbounds += @{ tag="direct"; protocol="freedom"; settings=@{} }
    $config = @{ 
        log      = @{ logLevel="info"; access="access.log"; error="error.log" }
        inbounds = $inboundArr
        outbounds = $outbounds
        routing  = @{ domainStrategy="AsIs"; rules=$rules } 
    }
    if ($global:enableUpstreamDoh -and -not [string]::IsNullOrWhiteSpace($global:upstreamDohUrl)) {
        $config.Add("dns", @{ servers = @($global:upstreamDohUrl) })
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content (Get-AppPath "Data\Xray\config.json")
}

function Write-SingboxConfig {
    $bypassApps = @("tor.exe","haproxy.exe","lyrebird.exe","obfs4proxy.exe","snowflake-client.exe","xray.exe","sing-box.exe")
    if ($global:enableDirect -and -not [string]::IsNullOrWhiteSpace($global:lastAppSplit)) {
        $customApps = $global:lastAppSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($app in $customApps) {
            $normalizedApp = if ($app -notmatch "\.exe$") { "$app.exe" } else { $app }
            $bypassApps += $normalizedApp.ToLower()
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
    if ($global:enableUpstreamDoh -and -not [string]::IsNullOrWhiteSpace($global:upstreamDohUrl)) {
        if ($global:upstreamDohUrl.StartsWith("https://")) {
            try {
                $sbUri  = [uri]$global:upstreamDohUrl
                $sbHost = $sbUri.Host
                $sbPath = if ($sbUri.AbsolutePath -eq "/") { "/dns-query" } else { $sbUri.PathAndQuery }
                $dnsServer = @{ tag="dns_proxy"; type="https"; server=$sbHost; path=$sbPath; detour="proxy" }
            } catch { $dnsServer = @{ tag="dns_proxy"; type="tcp"; server="1.1.1.1"; detour="proxy" } }
        } else {
            $dnsServer = @{ tag="dns_proxy"; type="tcp"; server=$global:upstreamDohUrl; detour="proxy" }
        }
    } else {
        $dnsServer = @{ tag="dns_proxy"; type="https"; server="cloudflare-dns.com"; path="/dns-query"; detour="proxy" }
    }
    $sbConfig = @{
        log      = @{ level="fatal" } 
        dns      = @{ servers=@($dnsServer); final="dns_proxy"; strategy="ipv4_only" }
        inbounds = @( @{ 
            type="tun"; tag="tun-in"; interface_name="singbox_tun"
            address=@("172.18.0.1/30"); mtu=9000; auto_route=$true; strict_route=$true; stack="gvisor" 
        } )
        outbounds = @( 
            @{ type="socks"; tag="proxy"; server="127.0.0.1"; server_port=10818 }, 
            @{ type="direct"; tag="direct" },
            @{ type="block"; tag="block" } 
        )
        route    = @{ auto_detect_interface=$true; rules=$sbRules; final="proxy" }
    }
    $sbConfig | ConvertTo-Json -Depth 10 | Set-Content (Get-AppPath "Data\sing_box\config.json")
}

function Set-SystemProxy($enable) {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($enable) { 
        Set-ItemProperty $path -Name "ProxyEnable" -Value 1
        Set-ItemProperty $path -Name "ProxyServer"  -Value "127.0.0.1:10818"
        $bypassList = "<local>"
        if ($global:enableDirect -and -not [string]::IsNullOrWhiteSpace($global:lastManualSplit) -and $global:lastXrayMode -eq "Proxy Mode") {
            $clean = $global:lastManualSplit.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            $bypassList = "$($clean -join ';');<local>"
        }
        Set-ItemProperty $path -Name "ProxyOverride" -Value $bypassList
    } else { 
        Set-ItemProperty $path -Name "ProxyEnable" -Value 0 
    }
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Restart-Xray($targetMode) {
    Get-Process sing-box, xray -ErrorAction SilentlyContinue | ForEach-Object { 
        try { 
            if ($null -ne $_.Path -and ($_.Path -eq (Get-AppPath "Data\Xray\xray.exe") -or $_.Path -eq (Get-AppPath "Data\sing_box\sing-box.exe"))) { 
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue 
            } 
        } catch {} 
    }
    if ($null -ne $global:cmdDebugPid)  { Stop-Process -Id $global:cmdDebugPid  -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid  = $null }
    if ($null -ne $global:cmdDebugPid2) { Stop-Process -Id $global:cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid2 = $null }
    if ($null -ne $global:xrayDohPid)   { Stop-Process -Id $global:xrayDohPid   -Force -ErrorAction SilentlyContinue; $global:xrayDohPid   = $null }
    Start-Sleep -Milliseconds 500
    Write-XrayConfig
    if ($script:debugMode) { 
        $p = Start-Process "cmd.exe" -ArgumentList "/c `"title XrayDebug & .\xray.exe run -c config.json || pause`"" -WorkingDirectory $xrayDir -WindowStyle Normal -PassThru
        $global:cmdDebugPid = $p.Id 
    } else { 
        Start-Process -FilePath (Get-AppPath "Data\Xray\xray.exe") -ArgumentList "run -c config.json" -WorkingDirectory $xrayDir -WindowStyle Hidden 
    }
    if ($targetMode -eq "VPN Mode") {
        Write-SingboxConfig
        if ($script:debugMode) { 
            $p2 = Start-Process "cmd.exe" -ArgumentList "/c `"title SingBoxDebug & .\sing-box.exe run -c config.json || pause`"" -WorkingDirectory $sbDir -WindowStyle Normal -PassThru
            $global:cmdDebugPid2 = $p2.Id 
        } else { 
            Start-Process -FilePath (Get-AppPath "Data\sing_box\sing-box.exe") -ArgumentList "run -c config.json" -WorkingDirectory $sbDir -WindowStyle Hidden 
        }
    } elseif ($targetMode -eq "Proxy Mode") { 
        Set-SystemProxy $true 
    }
    if ($targetMode -ne "Proxy Mode") { Set-SystemProxy $false }
    if ($global:isConnected) {
        if ($null -ne $global:pingTimer) { $global:pingTimer.Stop() } 
        $global:pingTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:pingTimer.Interval = [TimeSpan]::FromSeconds(1.5)
        $global:pingTimer.add_Tick({ $global:pingTimer.Stop(); Start-GeoPing })
        $global:pingTimer.Start()
    }
}

function Format-HAProxyConfig($activeCount) {
    $haPathCfg = Get-AppPath "Data\HAproxy\haproxy.cfg"
    if (Test-Path $haPathCfg) {
        $haData = Get-Content $haPathCfg
        $newHaData = @()
        $hasStats = $false
        foreach ($line in $haData) {
            if ($line -match "^listen stats") { $hasStats = $true }
            if ($line -match "^\s*#?\s*server\s+tor(\d+)") {
                if ([int]$matches[1] -le $activeCount) { 
                    $newHaData += ($line -replace "^\s*#+\s*", "    ")
                } else { 
                    if ($line -notmatch "^\s*#") { $newHaData += "    # $($line.TrimStart())" } 
                    else { $newHaData += $line } 
                }
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

# WAVE ENGINE
function Update-WaveAnimation {
    param([string]$State)
    if ($null -eq $wavePath1 -or $null -eq $waveTrans1 -or $null -eq $waveTrans2) { return }
    if ($null -eq $global:wavePhysicsTimer) {
        $global:waveX1 = 0.0; $global:waveX2 = -75.0
        $global:waveCurrentSpeed1 = 0.4; $global:waveCurrentSpeed2 = 0.5
        $global:waveTargetSpeed1  = 0.4; $global:waveTargetSpeed2  = 0.5
        $global:wavePhysicsTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:wavePhysicsTimer.Interval = [TimeSpan]::FromMilliseconds(25)
        $global:wavePhysicsTimer.add_Tick({
            $global:waveCurrentSpeed1 += ($global:waveTargetSpeed1 - $global:waveCurrentSpeed1) * 0.08
            $global:waveCurrentSpeed2 += ($global:waveTargetSpeed2 - $global:waveCurrentSpeed2) * 0.08
            $global:waveX1 -= $global:waveCurrentSpeed1
            $global:waveX2 -= $global:waveCurrentSpeed2
            if ($global:waveX1 -le -150.0) { $global:waveX1 += 150.0 }
            if ($global:waveX2 -le -225.0) { $global:waveX2 += 150.0 }
            $waveTrans1.X = $global:waveX1; $waveTrans2.X = $global:waveX2
        })
        $global:wavePhysicsTimer.Start()
    }
    if ($null -ne $global:waveHoldTimer) { $global:waveHoldTimer.Stop() }
    $colorHex = "#718096"
    switch ($State) {
        "Idle" {
            $colorHex = "#718096"
            $global:waveTargetSpeed1 = 0.4; $global:waveTargetSpeed2 = 0.5
        }
        "Connecting" {
            $colorHex = "#B78854"
            $global:waveCurrentSpeed1 = 5.5; $global:waveCurrentSpeed2 = 6.0
            $global:waveTargetSpeed1  = 5.5; $global:waveTargetSpeed2  = 6.0
            $global:waveHoldTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:waveHoldTimer.Interval = [TimeSpan]::FromMilliseconds(600)
            $global:waveHoldTimer.add_Tick({
                $global:waveHoldTimer.Stop()
                $global:waveTargetSpeed1 = 1.1; $global:waveTargetSpeed2 = 1.3
            }.GetNewClosure())
            $global:waveHoldTimer.Start()
        }
        "Connected" {
            $colorHex = "#68D391"
            $global:waveCurrentSpeed1 = 5.5; $global:waveCurrentSpeed2 = 6.0
            $global:waveTargetSpeed1  = 5.5; $global:waveTargetSpeed2  = 6.0
            $global:waveHoldTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:waveHoldTimer.Interval = [TimeSpan]::FromMilliseconds(600)
            $global:waveHoldTimer.add_Tick({
                $global:waveHoldTimer.Stop()
                $global:waveTargetSpeed1 = 0.4; $global:waveTargetSpeed2 = 0.5
            }.GetNewClosure())
            $global:waveHoldTimer.Start()
        }
    }
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

# GEO-IP TRACKER
function Start-GeoPing {
    if ($global:isGeoTracing) { return } 
    $global:isGeoTracing = $true
    $lblGeoData.Text = "Loc: TRACING...`nPing: --"; $lblGeoData.Foreground = "#68D391" 
    $geoClient = New-Object System.Net.WebClient
    $geoClient.Proxy = New-Object System.Net.WebProxy("http://127.0.0.1:10818")
    $global:geoSw = [System.Diagnostics.Stopwatch]::StartNew()
    $geoClient.Add_DownloadStringCompleted({
        param($sender, $e)
        $global:isGeoTracing = $false  
        $global:geoSw.Stop()
        $pingMs = $global:geoSw.ElapsedMilliseconds
        $form.Dispatcher.Invoke([System.Action]{
            if ($global:isConnected) {
                if (-not $e.Cancelled -and $null -eq $e.Error) {
                    try {
                        $data   = $e.Result | ConvertFrom-Json
                        $geoStr = ""
                        $selConfig = if ($comboConfig.SelectedItem.Tag -match "Custom") { "Custom" } else { "Optimized" }
                        if ($selConfig -eq "Custom" -or $global:enableV2rayChain) { 
                            $geoStr = $data.country 
                        } else {
                            $cMap = @{ "NA"="NORTH AMERICA";"EU"="EUROPE";"AS"="ASIA";"SA"="SOUTH AMERICA";"AF"="AFRICA";"OC"="OCEANIA";"AN"="ANTARCTICA" }
                            $geoStr = $cMap[$data.continent_code]
                            if (-not $geoStr) { $geoStr = $data.continent_code }
                        }
                        $lblGeoData.Text = "Loc: $($geoStr.ToUpper())`nPing: $($pingMs)ms"
                        $lblGeoData.Foreground = "#68D391" 
                    } catch { 
                        $lblGeoData.Text = "Loc: ERROR`nPing: --"; $lblGeoData.Foreground = "#8B4A4A" 
                    }
                } else { 
                    $lblGeoData.Text = "Loc: TIMEOUT`nPing: --"; $lblGeoData.Foreground = "#8B4A4A" 
                }
            }
        })
        $sender.Dispose()
    })
    try { $geoClient.DownloadStringAsync([uri]"https://get.geojs.io/v1/ip/geo.json") } 
    catch { 
        $global:isGeoTracing = $false
        $lblGeoData.Text = "Loc: ERROR`nPing: --"; $lblGeoData.Foreground = "#8B4A4A"
        $geoClient.Dispose()
    }
}

function Reset-ButtonText { 
    $btnActionMainText.Text = "CONNECT"; $btnActionSubText.Text = ""
    $btnActionMainText.Foreground = "#E2E8F0"
    Update-WaveAnimation -State "Idle"
}

function Stop-AllEngines($isClosing = $false) {
    $global:abortBoot = $true
    Set-SystemProxy $false
    $global:isEngineRunning = $false
    Get-Process tor, haproxy, xray, sing-box -ErrorAction SilentlyContinue | ForEach-Object { 
        try { 
            $p = $_.Path
            if ($null -ne $p -and (
                $p -eq (Get-AppPath "Data\Xray\xray.exe") -or 
                $p -eq (Get-AppPath "Data\HAproxy\haproxy.exe") -or 
                $p -eq (Get-AppPath "Data\sing_box\sing-box.exe") -or 
                $p -match "Data\\Tors\\Tor")) { 
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                $proc = Get-Process -Id $_.Id -ErrorAction SilentlyContinue
                if ($null -ne $proc) {
                    $null = $proc.WaitForExit(500) 
                }
            } 
        } catch {
            Write-Host "Error stopping process: $($_.Exception.Message)"
        }
    }
    if ($null -ne $global:cmdDebugPid)  { Stop-Process -Id $global:cmdDebugPid  -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid  = $null }
    if ($null -ne $global:cmdDebugPid2) { Stop-Process -Id $global:cmdDebugPid2 -Force -ErrorAction SilentlyContinue; $global:cmdDebugPid2 = $null }
    if ($null -ne $global:xrayDohPid)   { Stop-Process -Id $global:xrayDohPid   -Force -ErrorAction SilentlyContinue; $global:xrayDohPid   = $null }
    $global:isConnected       = $false
    $global:lastTotalBytes    = 0
    $global:sessionDataBytes  = 0
    $global:sessionStartTime  = $null
    
    if (-not $isClosing) {
        if ($null -ne $lblSessionTime) { $lblSessionTime.Text = "SESSION: OFFLINE"; $lblSessionTime.Foreground = $global:brushGray }
        Reset-ButtonText
        $btnAction.IsEnabled = $true
        $lblSocksTitle.Text = "MIXED PORT"
        $lblSocksDataIPs.Text = "Waiting for connection..."
        $lblSocksDataTags.Text = ""
        $lblStatsData.Text = "Speed: 0 KB/s`nTotal: 0 MB"
        $lblGeoData.Text = "Loc: --`nPing: --"; $lblGeoData.Foreground = "#68D391"
    }
}

function Start-Engines {
    try {
        if (Get-Process tor -ErrorAction SilentlyContinue) { 
            $btnActionSubText.Text = "Clearing old engines..."
            DoEvents; Stop-AllEngines; Start-Sleep -Seconds 1 
        }
        $global:abortBoot = $false
        $selBridge = $comboBridge.SelectedItem.Tag
        $selConfig = if ($comboConfig.SelectedItem.Tag -match "Custom") { "Custom" } else { "Optimized" }
        $selCount  = [int]($comboCount.SelectedItem.Tag)
        $mode      = $global:lastXrayMode
        $cfgFileTarget = "torrc"
        for ($i = 1; $i -le 8; $i++) {
            Remove-Item (Get-AppPath "Data\Tors\Tor$i\tor.log") -ErrorAction SilentlyContinue
            $lbl = $form.FindName("lblTor$i")
            $padded = $i.ToString().PadLeft(2, '0')
            if ($null -ne $lbl -and $i -le $selCount) { $lbl.Text = "Tor $padded`: Waiting..."; $lbl.Foreground = "#A0AEC0" } 
            elseif ($null -ne $lbl)                   { $lbl.Text = "Tor $padded`: Disabled";  $lbl.Foreground = "#4A5568" }
        }
        Remove-Item (Get-AppPath "Data\Xray\access.log")     -ErrorAction SilentlyContinue
        Remove-Item (Get-AppPath "Data\Xray\access.log.tmp") -ErrorAction SilentlyContinue
        if ($null -ne $txtXrayLogs) { $txtXrayLogs.Text = "" }
        $global:isEngineRunning = $true
        Save-Config
        $winStyle    = if ($script:debugMode) { "Normal" } else { "Hidden" }
        $btnActionMainText.Text     = "CONNECTING"
        $btnActionMainText.Foreground = "#F6AD55"
        $btnActionSubText.Foreground  = "#B78854"
        Update-WaveAnimation -State "Connecting"
        Format-HAProxyConfig $selCount
        $dynamicWait = 16 - $selCount
        if ($global:enableTorDoh -and -not $global:enableOutboundProxy) {
            Write-TorOutboundDohConfig
            $pDoH = Start-Process -FilePath (Get-AppPath "Data\Xray\xray.exe") -ArgumentList "run -c tor-doh.json" -WorkingDirectory $xrayDir -WindowStyle Hidden -PassThru
            $global:xrayDohPid = $pDoH.Id
        }
        for ($i = 1; $i -le $selCount; $i++) {
            if ($global:abortBoot) { break } 
            $padded = $i.ToString().PadLeft(2, '0')
            $btnActionSubText.Text = "Booting Tor $i of $selCount"
            if ($i % 2 -eq 0) { DoEvents } 
            $path = Get-AppPath "Data\Tors\Tor$i"
            if (Test-Path "$path\$cfgFileTarget") {
                $c = @(Get-Content "$path\$cfgFileTarget")
                $cleanConfig = @()
                foreach ($line in $c) {
                    if ($line -match "^# --- MANAGED BRIDGES ---") { break }
                    if ($line -notmatch "^UseBridges" -and $line -notmatch "^ClientTransportPlugin" -and $line -notmatch "^Bridge" -and 
                        $line -notmatch "^HTTPSProxy" -and $line -notmatch "^Socks5Proxy" -and $line -notmatch "^Socks5ProxyUsername" -and 
                        $line -notmatch "^Socks5ProxyPassword" -and $line -notmatch "^HTTPSProxyAuthenticator" -and $line -notmatch "^Log notice file" -and 
                        $line -notmatch "^MaxCircuitDirtiness" -and $line -notmatch "^ExitNodes" -and $line -notmatch "^StrictNodes" -and 
                        $line -notmatch "^CircuitBuildTimeout" -and $line -notmatch "^HardwareAccel" -and 
                        $line -notmatch "^KeepalivePeriod" -and $line -notmatch "^NewCircuitPeriod" -and 
                        $line -notmatch "^# --- DYNAMIC ROUTING ---") {
                        if ($line.Trim() -ne "") { $cleanConfig += $line.Trim() }
                    }
                }
                $cleanConfig += ""
                $cleanConfig += "# --- DYNAMIC ROUTING ---"
                switch ($selConfig) {
                    "Optimized" { 
                        $cleanConfig += "CircuitBuildTimeout 10"
                        $cleanConfig += "KeepalivePeriod 60"
                        $cleanConfig += "NewCircuitPeriod 120"
                        $cleanConfig += "HardwareAccel 1"
                        $cleanConfig += "ExitNodes {nl},{de},{it},{is},{fi},{au},{nz},{ch},{hk},{ae},{us}"
                        $cleanConfig += "StrictNodes 0" 
                    }
                    "Custom" { 
                        if (-not [string]::IsNullOrWhiteSpace($global:customExitCountry)) {
                            $cleanConfig += "ExitNodes {$($global:customExitCountry)}"; $cleanConfig += "StrictNodes 1"
                        }
                    }
                    default { 
                        $cleanConfig += "ExitNodes {nl},{de},{it},{is},{fi},{au},{nz},{ch},{hk},{ae},{us}"
                        $cleanConfig += "StrictNodes 0" 
                    }
                }
                $cleanConfig += ""; $cleanConfig += "# --- MANAGED BRIDGES ---"; $cleanConfig += "Log notice file tor.log"
                if ($global:enableOutboundProxy -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyAddress) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPort)) {
                    if ($global:outboundProxyType -eq "SOCKS5") {
                        $cleanConfig += "Socks5Proxy $($global:outboundProxyAddress):$($global:outboundProxyPort)"
                        if ($global:enableOutboundAuth -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyUser) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPass)) { 
                            $cleanConfig += "Socks5ProxyUsername $($global:outboundProxyUser)"
                            $cleanConfig += "Socks5ProxyPassword $($global:outboundProxyPass)" 
                        }
                    } elseif ($global:outboundProxyType -eq "HTTPS") {
                        $cleanConfig += "HTTPSProxy $($global:outboundProxyAddress):$global:outboundProxyPort"
                        if ($global:enableOutboundAuth -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyUser) -and -not [string]::IsNullOrWhiteSpace($global:outboundProxyPass)) { 
                            $cleanConfig += "HTTPSProxyAuthenticator $($global:outboundProxyUser):$($global:outboundProxyPass)" 
                        }
                    }
                } elseif ($global:enableTorDoh) {
                    $cleanConfig += "Socks5Proxy 127.0.0.1:10820"
                }
                if ($selBridge -eq "Custom" -and $global:customBridgeLine -ne "") { 
                    $cleanConfig += "UseBridges 1"
                    $cleanConfig += "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel,snowflake exec ..\..\PluggableTransports\lyrebird.exe"
                    $customLines = $global:customBridgeLine.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch "^ClientTransportPlugin" }
                    foreach ($cl in $customLines) { 
                        if ($cl -notmatch "^Bridge\s") { $cleanConfig += "Bridge $cl" } else { $cleanConfig += $cl } 
                    }
                } elseif ($selBridge -ne "Direct (None)") { 
                    $b = $bridgeData[$selBridge]
                    $cleanConfig += "UseBridges 1"; $cleanConfig += $b.plugin
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
            $btnActionSubText.Text = "Booting Core Engines"
            DoEvents
            $xrayLogPath = Get-AppPath "Data\Xray\access.log"
            if (Test-Path $xrayLogPath) { Remove-Item $xrayLogPath -ErrorAction SilentlyContinue }
            $xrayErrPath = Get-AppPath "Data\Xray\error.log"
            if (Test-Path $xrayErrPath) { Remove-Item $xrayErrPath -ErrorAction SilentlyContinue }
            if (Test-Path (Get-AppPath "Data\HAproxy\haproxy.exe")) { 
                Start-Process -FilePath (Get-AppPath "Data\HAproxy\haproxy.exe") -ArgumentList "-f haproxy.cfg" -WorkingDirectory $haPath -WindowStyle $winStyle 
            }
            Restart-Xray $mode
            $lblSocksTitle.Text   = "MIXED PORT"
            $lblSocksDataIPs.Text = "127.0.0.1:10818`n$lanIp`:10818"
            $lblSocksDataTags.Text = "(Local)`n(LAN)"
            $global:isConnected      = $true
            $global:sessionStartTime = Get-Date
            $btnActionMainText.Text  = "CONNECTED"
            $btnActionSubText.Text   = ""
            $btnActionMainText.Foreground = "#68D391"
            Start-GeoPing
            Update-WaveAnimation -State "Connected"
        } else { Reset-ButtonText }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("A startup error occurred:`n" + $_.Exception.Message, "Error", 0, 16)
        Reset-ButtonText
    }
}

$btnTitleUpdate.Add_Click({ Update-Application })

function Update-Application {
    $btnTitleUpdate.IsEnabled = $false
    $lblTitleText.Text = "CHECKING FOR UPDATES..."
    $manualUpdateClient = New-Object System.Net.WebClient
    $manualUpdateClient.Add_DownloadStringCompleted({
        param($sender, $e)
        $form.Dispatcher.Invoke([System.Action]{
            $btnTitleUpdate.IsEnabled = $true
            if (-not $e.Cancelled -and $null -eq $e.Error) {
                $remoteCode = $e.Result
                if ($remoteCode -match '\$global:currentVersion\s*=\s*"([^"]+)"') {
                    $remoteVer = $matches[1]
                    if ([version]$remoteVer -gt [version]$global:currentVersion) {
                        $lblTitleText.Text = "TOR MULTIPLEXER v$global:currentVersion - NEW UPDATE AVAILABLE ($remoteVer)"
                        $lblTitleText.Foreground = [System.Windows.Media.Brushes]::White
                        $msg = [System.Windows.Forms.MessageBox]::Show("Version $remoteVer is available! Update now?", "Update Available", 4, 64)
                        if ($msg -eq "Yes") {
                            Invoke-WebRequest -Uri $repoRawUrl -OutFile $global:scriptPath
                            Start-Process powershell.exe -ArgumentList "-STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$global:scriptPath`""
                            [Environment]::Exit(0)
                        }
                    } else {
                        $lblTitleText.Text = "TOR MULTIPLEXER v$global:currentVersion"
                        [System.Windows.Forms.MessageBox]::Show("You are already on the latest version!", "Up to Date", 0, 64)
                    }
                }
            } else {
                $lblTitleText.Text = "TOR MULTIPLEXER v$global:currentVersion"
                [System.Windows.Forms.MessageBox]::Show("Update check failed.", "Error", 0, 16)
            }
        }.GetNewClosure())
        $sender.Dispose()
    })
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { $manualUpdateClient.DownloadStringAsync([uri]$repoRawUrl) } 
    catch { 
        $btnTitleUpdate.IsEnabled = $true
        $lblTitleText.Text = "TOR MULTIPLEXER v$global:currentVersion" 
    }
}

function Check-UpdateSilent {
    $updateWebClient = New-Object System.Net.WebClient
    $updateWebClient.Add_DownloadStringCompleted({
        param($sender, $e)
        if (-not $e.Cancelled -and $null -eq $e.Error) {
            try {
                if ($e.Result -match '\$global:currentVersion\s*=\s*"([^"]+)"') {
                    if ([version]$matches[1] -gt [version]$global:currentVersion) {
                        $form.Dispatcher.Invoke([System.Action]{ 
                            if ($null -ne $lblTitleText) {
                                $lblTitleText.Text       = "TOR MULTIPLEXER v$global:currentVersion  —  UPDATE AVAILABLE"
                                $lblTitleText.Foreground = [System.Windows.Media.Brushes]::White
                            }
                        }.GetNewClosure())
                    }
                }
            } catch {}
        }
        $sender.Dispose()
    }.GetNewClosure())
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { $updateWebClient.DownloadStringAsync([uri]$repoRawUrl) } catch {}
}

function Update-BootShortcut {
    $taskName = "TorMultiplexer_AutoStart"
    if ($script:launchOnBoot) {
        try { 
            $action    = New-ScheduledTaskAction -Execute (Get-AppPath "Launch Multiplexer.exe") -WorkingDirectory $global:baseDir
            $trigger   = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        } catch { 
            [System.Windows.Forms.MessageBox]::Show("Failed to create Auto-Start task.`n$($_.Exception.Message)", "Error", 0, 16)
            $script:launchOnBoot = $false
            Set-WpfToggleState $btnBootTog $false
        }
    } else { 
        try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {} 
    }
    $oldShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) "TorMultiplexer.lnk"
    if (Test-Path $oldShortcut) { Remove-Item $oldShortcut -Force -ErrorAction SilentlyContinue }
}

function Disable-SystemProxy {
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        Set-ItemProperty $path -Name "ProxyEnable" -Value 0 -ErrorAction SilentlyContinue
        [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        [Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    } catch {}
}

# STATS ENGINE & SESSION TIME TICKER
$global:statsWebClient = New-Object System.Net.WebClient
$global:isFetchingStats = $false
$global:statsWebClient.Add_DownloadStringCompleted({
    param($sender, $e)
    if (-not $e.Cancelled -and $null -eq $e.Error) {
        try {
            $rows       = $e.Result -split "`n"
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
                $speedStr = if ($avgDiff -ge 1048576) { "$([Math]::Round($avgDiff/1048576, 2)) MB/s" } 
                            elseif ($avgDiff -ge 1024)   { "$([Math]::Round($avgDiff/1024, 1)) KB/s" } 
                            else                          { "$([int]$avgDiff) B/s" }
                $totStr   = if ($global:sessionDataBytes -ge 1073741824) { "$([Math]::Round($global:sessionDataBytes/1073741824, 2)) GB" } 
                            elseif ($global:sessionDataBytes -ge 1048576)  { "$([Math]::Round($global:sessionDataBytes/1048576, 1)) MB" } 
                            else                                            { "$([Math]::Round($global:sessionDataBytes/1024, 1)) KB" }
                $form.Dispatcher.Invoke([System.Action]{ 
                    if ($null -ne $lblStatsData) { $lblStatsData.Text = "Speed: $speedStr`nTotal: $totStr" }
                })
            }
            if ($currentBytes -gt 0) { $global:lastTotalBytes = $currentBytes }
        } catch {}
    }
    $global:isFetchingStats = $false
}.GetNewClosure())

$global:statsTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:statsTimer.Interval = [TimeSpan]::FromSeconds(1)
$global:statsTimer.add_Tick({
    if ($null -eq $form -or $form.Dispatcher.HasShutdownStarted) { $global:statsTimer.Stop(); return }
    if ($global:isConnected) {
        if ($null -ne $global:sessionStartTime) {
            $elapsed = (Get-Date) - $global:sessionStartTime
            if ($null -ne $lblSessionTime) {
                $lblSessionTime.Text       = "SESSION: " + $elapsed.ToString("hh\:mm\:ss")
                $lblSessionTime.Foreground = $global:brushGreen
            }
        }
        if (-not $global:isFetchingStats -and $null -ne $global:statsWebClient) {
            $global:isFetchingStats = $true
            try { $global:statsWebClient.DownloadStringAsync([uri]"http://127.0.0.1:10888/stats;csv") } 
            catch { $global:isFetchingStats = $false }
        }
    }
}.GetNewClosure())
$global:statsTimer.Start()

# WINDOW SIZING & ANIMATION STATE MACHINE
function Update-WindowSize {
    $ts = New-Object TimeSpan(0, 0, 0, 0, 300)
    $targetW  = if ($global:isLogsOpen -and $global:isAdvancedOpen) { 909.0  } else { 595.0 }
    $targetH  = if ($global:isAdvancedOpen -or $global:isLogsOpen)  { 534.0  } else { 345.0 }
    $panelTop = if ($global:isAdvancedOpen -or $global:isLogsOpen)  { 424.0  } else { 230.0 }
    if ($global:isAdvancedOpen -or $global:isLogsOpen) {
        $UnifiedPanel.CornerRadius    = New-Object System.Windows.CornerRadius(0, 0, 4, 4)
        $UnifiedPanel.BorderThickness = New-Object System.Windows.Thickness(1, 0, 1, 1)
    } else {
        $UnifiedPanel.CornerRadius    = New-Object System.Windows.CornerRadius(4)
        $UnifiedPanel.BorderThickness = New-Object System.Windows.Thickness(1)
    }
    if ($global:isAdvancedOpen) {
        $AdvancedBorder.CornerRadius = New-Object System.Windows.CornerRadius(4, 4, 0, 0)
        $AdvancedCanvas.Visibility = "Visible"
        $advOpac = 1.0
    } else { $advOpac = 0.0 }
    if ($global:isLogsOpen) {
        $LogsCanvas.Visibility = "Visible"; $logTimer.Start(); $logOpac = 1.0
        if ($global:isAdvancedOpen) {
            # MODE A: Side-Panel
            $LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(585.0,  $ts)))
            $LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,   $ts)))
            $LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(300.0,  $ts)))
            $LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,(New-Object System.Windows.Media.Animation.DoubleAnimation(474.0,  $ts)))
            $logBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
            $logBorder.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(300.0,  $ts)))
            $logBorder.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(474.0,  $ts)))
            $btnCloseLogs.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(272.0,  $ts)))
            $lblTor1.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(30.0,  $ts)))
            $lblTor2.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(48.0,  $ts)))
            $lblTor3.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(66.0,  $ts)))
            $lblTor4.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(84.0,  $ts)))
            $lblTor5.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(155.0, $ts)))
            $lblTor5.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(30.0,  $ts)))
            $lblTor6.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(155.0, $ts)))
            $lblTor6.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(48.0,  $ts)))
            $lblTor7.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(155.0, $ts)))
            $lblTor7.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(66.0,  $ts)))
            $lblTor8.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(155.0, $ts)))
            $lblTor8.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(84.0,  $ts)))
            $logSeparator.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $logSeparator.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(110.0, $ts)))
            $logSeparator.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(270.0, $ts)))
            $logSeparator.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,(New-Object System.Windows.Media.Animation.DoubleAnimation(1.0,   $ts)))
            $lblConnTitle.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblConnTitle.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(120.0, $ts)))
            $txtXrayLogs.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $txtXrayLogs.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(138.0, $ts)))
            $txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(270.0, $ts)))
            $txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(321.0, $ts)))
        } else {
            # MODE B: Bottom-Panel
            $LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(20.0,  $ts)))
            $LogsCanvas.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(230.0, $ts)))
            $LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(550.0, $ts)))
            $LogsCanvas.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,(New-Object System.Windows.Media.Animation.DoubleAnimation(194.0, $ts)))
            $logBorder.CornerRadius = New-Object System.Windows.CornerRadius(4, 4, 0, 0)
            $logBorder.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(550.0, $ts)))
            $logBorder.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(194.0, $ts)))
            $btnCloseLogs.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(522.0, $ts)))
            $lblTor1.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblTor1.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(31.0,  $ts)))
            $lblTor2.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblTor2.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(50.0,  $ts)))
            $lblTor3.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblTor3.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(69.0,  $ts)))
            $lblTor4.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblTor4.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(88.0,  $ts)))
            $lblTor5.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblTor5.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(107.0, $ts)))
            $lblTor6.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblTor6.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(126.0, $ts)))
            $lblTor7.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblTor7.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(145.0, $ts)))
            $lblTor8.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(15.0,  $ts)))
            $lblTor8.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(164.0, $ts)))
            $logSeparator.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(152.0, $ts)))
            $logSeparator.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(0.0,   $ts)))
            $logSeparator.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(1.0,   $ts)))
            $logSeparator.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty,(New-Object System.Windows.Media.Animation.DoubleAnimation(193.0, $ts)))
            $lblConnTitle.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,   (New-Object System.Windows.Media.Animation.DoubleAnimation(169.0, $ts)))
            $lblConnTitle.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(10.0,  $ts)))
            $txtXrayLogs.BeginAnimation([System.Windows.Controls.Canvas]::LeftProperty,    (New-Object System.Windows.Media.Animation.DoubleAnimation(169.0, $ts)))
            $txtXrayLogs.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation(30.0,  $ts)))
            $txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation(364.0, $ts)))
            $txtXrayLogs.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(150.0, $ts)))
        }
    } else { $logOpac = 0.0; $logTimer.Stop() }
    $form.BeginAnimation([System.Windows.Window]::WidthProperty,  (New-Object System.Windows.Media.Animation.DoubleAnimation($targetW, $ts)))
    $form.BeginAnimation([System.Windows.Window]::HeightProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($targetH, $ts)))
    $AdvancedCanvas.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($advOpac, $ts)))
    $LogsCanvas.BeginAnimation([System.Windows.UIElement]::OpacityProperty,     (New-Object System.Windows.Media.Animation.DoubleAnimation($logOpac, $ts)))
    $UnifiedPanel.BeginAnimation([System.Windows.Controls.Canvas]::TopProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($panelTop, $ts)))
    if (-not $global:isAdvancedOpen) {
        $global:hideAdvTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:hideAdvTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $global:hideAdvTimer.add_Tick({ $global:hideAdvTimer.Stop(); $AdvancedCanvas.Visibility = "Hidden" }.GetNewClosure())
        $global:hideAdvTimer.Start()
    }
    if (-not $global:isLogsOpen) {
        $global:hideLogTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:hideLogTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $global:hideLogTimer.add_Tick({ $global:hideLogTimer.Stop(); $LogsCanvas.Visibility = "Hidden" }.GetNewClosure())
        $global:hideLogTimer.Start()
    }
}

# LIVE LOGS PARSER ENGINE
$logTimer = New-Object System.Windows.Threading.DispatcherTimer
$logTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
$logTimer.add_Tick({
    try {
        if (-not $global:isLogsOpen -or $null -eq $comboCount.SelectedItem) { return }
        $selCount = [int]($comboCount.SelectedItem.Tag)
        if (-not $global:isEngineRunning) {
            for ($i = 1; $i -le 8; $i++) {
                $lbl = $form.FindName("lblTor$i")
                if ($null -ne $lbl) {
                    $padded = $i.ToString().PadLeft(2, '0')
                    if ($i -le $selCount) { $lbl.Text = "Tor $padded`: Offline"; $lbl.Foreground = "#4A5568" }
                    else                  { $lbl.Text = "Tor $padded`: Disabled"; $lbl.Foreground = "#4A5568" }
                }
            }
            if ($null -ne $txtXrayLogs) { $txtXrayLogs.Text = "" }
            return
        }
        for ($i = 1; $i -le 8; $i++) {
            $lbl = $form.FindName("lblTor$i")
            if ($null -eq $lbl) { continue }
            $padded = $i.ToString().PadLeft(2, '0')
            if ($i -gt $selCount) { $lbl.Text = "Tor $padded`: Disabled"; $lbl.Foreground = "#4A5568"; continue }
            $logPath = Get-AppPath "Data\Tors\Tor$i\tor.log"
            if (Test-Path $logPath) {
                try {
                    $fs = New-Object System.IO.FileStream($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $sr = New-Object System.IO.StreamReader($fs)
                    $content = $sr.ReadToEnd()
                    $sr.Close(); $fs.Close()
                    $pctMatches = [regex]::Matches($content, 'Bootstrapped (\d+)%')
                    if ($pctMatches.Count -gt 0) {
                        $pct = $pctMatches[$pctMatches.Count - 1].Groups[1].Value
                        $lbl.Text = "Tor $padded`: $pct%"
                        $lbl.Foreground = if ($pct -eq "100") { "#68D391" } else { "#F6AD55" }
                    } else { $lbl.Text = "Tor $padded`: Booting..."; $lbl.Foreground = "#A0AEC0" }
                } catch {}
            } else { $lbl.Text = "Tor $padded`: Waiting..."; $lbl.Foreground = "#A0AEC0" }
        }
        $xrayLogPath = Get-AppPath "Data\Xray\access.log"
        if (Test-Path $xrayLogPath) {
            try {
                $fs = New-Object System.IO.FileStream($xrayLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $sr = New-Object System.IO.StreamReader($fs)
                $content = $sr.ReadToEnd()
                $sr.Close(); $fs.Close()
                $lines   = $content -split "`r?`n" | Where-Object { $_ -match "accepted" -or $_ -match "proxy" }
                $tail    = $lines | Select-Object -Last 15
                $cleaned = $tail | ForEach-Object { $_ -replace "^.*?\s\d{2}:\d{2}:\d{2}\s+(127\.0\.0\.1:\d+\s+)?", "" }
                if ($null -ne $txtXrayLogs) {
                    $txtXrayLogs.Text = $cleaned -join "`n"
                    $txtXrayLogs.ScrollToEnd()
                }
            } catch {}
        }
    } catch {}
})

# LOG AUTO-CLEANER
$logClearTimer = New-Object System.Windows.Threading.DispatcherTimer
$logClearTimer.Interval = [TimeSpan]::FromHours(2)
$logClearTimer.add_Tick({
    try {
        foreach ($logFile in @("Data\Xray\access.log", "Data\Xray\error.log")) {
            $fullPath = Get-AppPath $logFile
            if (Test-Path $fullPath) { 
                $fs = New-Object System.IO.FileStream($fullPath, [System.IO.FileMode]::Truncate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                $fs.Close()
            }
        }
    } catch {
        Clear-Content (Get-AppPath "Data\Xray\access.log") -ErrorAction SilentlyContinue
        Clear-Content (Get-AppPath "Data\Xray\error.log")  -ErrorAction SilentlyContinue
    }
})
$logClearTimer.Start()

# EVENT BINDINGS
if (Test-Path (Get-AppPath "icon.ico")) {
    $global:sysTrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $global:sysTrayIcon.Icon    = New-Object System.Drawing.Icon((Get-AppPath "icon.ico"))
    $global:sysTrayIcon.Text    = "Tor Multiplexer"
    $global:sysTrayIcon.Visible = $true
    $restoreAppAction = {
        $form.Dispatcher.Invoke([System.Action]{
            $form.ShowInTaskbar = $true
            $form.WindowState   = [System.Windows.WindowState]::Normal
            $form.Activate() | Out-Null
        })
    }
    $global:sysTrayIcon.add_DoubleClick($restoreAppAction)
    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $trayMenu.Items.Add("Show Window").add_Click($restoreAppAction)
    $trayMenu.Items.Add("Exit Application").add_Click({ $form.Dispatcher.Invoke([System.Action]{ $form.Close() }) })
    $global:sysTrayIcon.ContextMenuStrip = $trayMenu
}
$form.add_StateChanged({
    if ($form.WindowState -eq [System.Windows.WindowState]::Minimized) { $form.ShowInTaskbar = -not $global:minimizeToTray }
})

# COMBO BOXES
$comboBridge.add_SelectionChanged({
    if ($global:ignoreComboChange) { return }
    if ($comboBridge.SelectedItem.Tag -eq "Custom") { 
        $global:ignoreComboChange = $true
        if (-not (Show-CustomBridgeDialog)) { Set-ComboSelectedTag $comboBridge $global:previousBridge } 
        else { $global:previousBridge = "Custom" } 
        $global:ignoreComboChange = $false
    } else { $global:previousBridge = $comboBridge.SelectedItem.Tag }
    Save-Config
})
$comboConfig.add_SelectionChanged({ 
    if ($global:ignoreComboChange) { return }
    if ($comboConfig.SelectedItem.Tag -eq "Custom") { 
        $global:ignoreComboChange = $true
        if (-not (Show-ExitNodeDialog)) { Set-ComboSelectedTag $comboConfig $global:previousConfig } 
        else { $global:previousConfig = "Custom" } 
        $global:ignoreComboChange = $false
    } else { $global:previousConfig = $comboConfig.SelectedItem.Tag }
    Save-Config 
})
$comboCount.add_SelectionChanged({ Save-Config })

# BUTTON ACTIONS
$btnStatsPanel.add_Click({ if ($global:isConnected) { Start-GeoPing } })
$btnAction.add_Click({ if ($global:isConnected -or $btnActionMainText.Text -eq "CONNECTING") { Stop-AllEngines } else { Start-Engines } })

if ($null -ne $btnAutoStartMain) {
    $btnAutoStartMain.Add_Click({
        $script:autoStart = -not $script:autoStart
        Set-AutoConnectState $script:autoStart $true
        Save-Config
    })
}
if ($null -ne $btnAdvMain) {
    $btnAdvMain.Add_Click({
        $global:isAdvancedOpen = -not $global:isAdvancedOpen
        Set-AdvState $global:isAdvancedOpen
        Update-WindowSize
    })
}
$btnDesktop.Add_Click({
    try {
        $WshShell  = New-Object -ComObject WScript.Shell
        $Shortcut  = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\TorMultiplexer.lnk")
        $Shortcut.TargetPath      = Get-AppPath "Launch Multiplexer.exe"
        $Shortcut.WorkingDirectory = $global:baseDir
        $Shortcut.Save()
        [System.Windows.Forms.MessageBox]::Show("Desktop shortcut created successfully!", "Success")
    } catch { 
        [System.Windows.Forms.MessageBox]::Show("Failed to create Desktop shortcut: $($_.Exception.Message)", "Error") 
    }
})
$btnCloseLogs.add_Click({
    if ($global:isLogsOpen) {
        $global:isLogsOpen = $false
        Set-WpfToggleState $btnLogsTog $global:isLogsOpen "HIDE" "SHOW"
        Update-WindowSize
        Save-Config
    }
})
$toggleAction = {
    param($mode)
    if ($global:lastXrayMode -ne $mode) {
        $global:lastXrayMode = $mode
        Update-RoutingToggle; Save-Config
        if ($global:isConnected) { Restart-Xray $mode }
    }
}
$btnProxyMode.add_Click({ & $toggleAction "Proxy Mode"  })
$btnClearProxy.add_Click({ & $toggleAction "Clear Proxy" })
$btnVpnMode.add_Click({ & $toggleAction "VPN Mode"   })

$btnV2rayTog.Add_Click({
    if (-not $global:enableV2rayChain -and [string]::IsNullOrWhiteSpace($global:v2rayChainJson)) {
        if (-not (Show-V2rayDialog)) { return }
    }
    $global:enableV2rayChain = -not $global:enableV2rayChain
    Set-WpfToggleState $btnV2rayTog $global:enableV2rayChain
    Save-Config
    if ($global:isConnected) { Restart-Xray $global:lastXrayMode }
})
$btnV2rayLbl.Add_Click({
    Show-V2rayDialog | Out-Null
    Set-WpfToggleState $btnV2rayTog $global:enableV2rayChain
})
$btnDirectTog.Add_Click({
    $newState = -not $global:enableDirect
    if ($newState) {
        $hasRules = -not [string]::IsNullOrWhiteSpace($global:lastManualSplit) -or -not [string]::IsNullOrWhiteSpace($global:lastAppSplit)
        if (-not $hasRules) { if (-not (Show-DirectRulesDialog)) { return } }
    }
    $global:enableDirect = $newState
    Set-WpfToggleState $btnDirectTog $global:enableDirect
    Save-Config
    if ($global:isConnected) { Restart-Xray $global:lastXrayMode }
})
$btnDirectLbl.Add_Click({ Show-DirectRulesDialog | Out-Null })
$btnOutboundTog.Add_Click({
    if ($global:isConnected) { 
        [System.Windows.Forms.MessageBox]::Show("Disconnect first.", "Action Denied", 0, 48); return 
    }
    $newState = -not $global:enableOutboundProxy
    if ($newState -and [string]::IsNullOrWhiteSpace($global:outboundProxyAddress)) {
        if (-not (Show-OutboundProxyDialog)) { return }
    }
    $global:enableOutboundProxy = $newState
    Set-WpfToggleState $btnOutboundTog $global:enableOutboundProxy
    Save-Config
})
$btnOutboundLbl.Add_Click({ 
    Show-OutboundProxyDialog | Out-Null
    Set-WpfToggleState $btnOutboundTog $global:enableOutboundProxy
})
$btnDohTog.Add_Click({
    if ($global:isConnected) { [System.Windows.Forms.MessageBox]::Show("Disconnect first.", "Action Denied", 0, 48); return }
    if ($global:enableTorDoh -or $global:enableUpstreamDoh) {
        $global:enableTorDoh = $false; $global:enableUpstreamDoh = $false
        Set-WpfToggleState $btnDohTog $false; Save-Config; Evaluate-ProxyExclusivity
    } else {
        if (-not (Show-DohDialog)) { Set-WpfToggleState $btnDohTog $false } 
        else { Set-WpfToggleState $btnDohTog ($global:enableTorDoh -or $global:enableUpstreamDoh); Save-Config; Evaluate-ProxyExclusivity }
    }
})
$btnDohLbl.Add_Click({ $btnDohTog.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

# SIMPLE TOGGLE BINDINGS
$btnBootTog.Add_Click({    $script:launchOnBoot = -not $script:launchOnBoot; Set-WpfToggleState $btnBootTog $script:launchOnBoot; Update-BootShortcut; Save-Config })
$btnDebugTog.Add_Click({   $script:debugMode    = -not $script:debugMode;    Set-WpfToggleState $btnDebugTog $script:debugMode })
$btnTrayTog.Add_Click({    $global:minimizeToTray = -not $global:minimizeToTray; Set-WpfToggleState $btnTrayTog $global:minimizeToTray; Save-Config })
$btnLogsTog.Add_Click({    $global:isLogsOpen   = -not $global:isLogsOpen;   Set-WpfToggleState $btnLogsTog $global:isLogsOpen "HIDE" "SHOW"; Update-WindowSize; Save-Config })
$btnAdBlockTog.Add_Click({ $global:enableAdBlock = -not $global:enableAdBlock; Set-WpfToggleState $btnAdBlockTog $global:enableAdBlock; Save-Config; if ($global:isConnected) { Restart-Xray $global:lastXrayMode } })
$btnBootLbl.Add_Click({    $btnBootTog.RaiseEvent(    (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$btnDebugLbl.Add_Click({   $btnDebugTog.RaiseEvent(   (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$btnTrayLbl.Add_Click({    $btnTrayTog.RaiseEvent(    (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$btnLogsLbl.Add_Click({    $btnLogsTog.RaiseEvent(    (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$btnAdBlockLbl.Add_Click({ $btnAdBlockTog.RaiseEvent( (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

# EXIT & AUTO-BOOT TRIGGERS
$form.add_Closing({ 
    $statsTimer.Stop()
    $logTimer.Stop()
    $logClearTimer.Stop()
    if ($null -ne $global:wavePhysicsTimer) { $global:wavePhysicsTimer.Stop() }
    if ($null -ne $global:hideAdvTimer)     { $global:hideAdvTimer.Stop() }
    if ($null -ne $global:hideLogTimer)     { $global:hideLogTimer.Stop() }
    if ($null -ne $global:pingTimer)        { $global:pingTimer.Stop() }
    Stop-AllEngines $true 
    if ($global:sysTrayIcon) { $global:sysTrayIcon.Visible = $false; $global:sysTrayIcon.Dispose() }
})
$form.add_Closed({ [Environment]::Exit(0) })

$form.add_ContentRendered({ 
    try {
        if ($global:appInitialized) { return }
        $global:appInitialized = $true
        Check-UpdateSilent

        if ($script:autoStart) {
            $animTimer = New-Object System.Windows.Threading.DispatcherTimer
            $animTimer.Interval = [TimeSpan]::FromMilliseconds(150)
            $animTimer.add_Tick({
                $animTimer.Stop()
                Set-AutoConnectState $true $true
            }.GetNewClosure())
            $animTimer.Start()
        }

        # MISSING CORE COMPONENT CHECK
        if (-not (Test-Path (Get-AppPath "Launch Multiplexer.exe"))) {
            $ix = @"
                <TextBlock Text="Your installation is missing 'Launch Multiplexer.exe'.&#x0a;&#x0a;This usually happens if you updated the script but didn't download the full package. Please download the latest full release from GitHub." Canvas.Left="15" Canvas.Top="35" Width="350" TextWrapping="Wrap" FontSize="11" Foreground="{StaticResource TextMain}"/>
                <Button Name="btnGit" Content="Open GitHub" Canvas.Left="15" Canvas.Top="132" Width="130" Height="25" Style="{StaticResource SaveButton}"/>
                <Button Name="btnCancel" Content="Close" Canvas.Left="275" Canvas.Top="132" Width="90" Height="25" IsCancel="True"/>
"@
            $onLoad = {
                param($d)
                $d.FindName("btnGit").Add_Click({ Start-Process "https://github.com/RichTiTAN/Tor-Multiplexer"; $d.Close() }.GetNewClosure())
            }
            Show-AppDialog -Title "MISSING CORE COMPONENT" -Width 420 -Height 240 -InnerXaml $ix -OnLoad $onLoad | Out-Null
        }

        # AUTO-START LOGIC
        if ($script:autoStart -and -not $isFirstLaunch) { 
            $bootTimer = New-Object System.Windows.Threading.DispatcherTimer
            $bootTimer.Interval = [TimeSpan]::FromMilliseconds(500)
            $bootTimer.add_Tick({
                $bootTimer.Stop()
                if (-not $global:abortBoot) { Start-Engines }
            }.GetNewClosure())
            $bootTimer.Start()
        }
    } catch {
        $msg = "Error: $($_.Exception.Message)`nStack: $($_.ScriptStackTrace)"
        $msg | Out-File (Get-AppPath "debug_log.txt") -Append
        [System.Windows.MessageBox]::Show($msg, "CRASH DETAIL")
    }
})

Update-WaveAnimation -State "Idle"

if ($null -ne $form) {
    try {
        $form.ShowDialog() | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Final ShowDialog failed: $($_.Exception.Message)")
    }
} else {
    [System.Windows.Forms.MessageBox]::Show("Main Form is NULL. XAML parsing failed earlier.")
}