@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: --- DEBUG MODE ---
:: Set to "Normal" to see all console windows, or "Hidden" to run invisibly.
set "WINDOW_STYLE=Normal"

:: --- ISOLATED MEMORY SYSTEM ---
set "SETTINGS_FILE=cmd_settings.ini"

if exist "%SETTINGS_FILE%" (
    echo Loading isolated CMD configuration...
    for /f "usebackq delims=" %%A in ("%SETTINGS_FILE%") do set "%%A"
    goto :START_ROUTINE
)

:: Set absolute defaults for a fresh launch
set "PROXY_MODE=1"
set "INSTANCE_COUNT=6"

:CONFIG_SELECT
cls
echo =========================================
echo        TOR MULTIPLEXER - BOOT MENU
echo =========================================
echo.
echo   [1] STABLE CONFIGURATION (torrc)
echo   [2] FAST CONFIGURATION (torrc2)
echo.
echo =========================================
choice /C 12 /N /M "Select Boot Mode (1-2): "

if errorlevel 2 goto :SET_FAST
if errorlevel 1 goto :SET_STABLE

:SET_FAST
set "TOR_CFG=torrc2"
set "MODE_NAME=FAST_EU_LOCKED"
goto :BRIDGE_SELECT

:SET_STABLE
set "TOR_CFG=torrc"
set "MODE_NAME=STABLE_GLOBAL"
goto :BRIDGE_SELECT

:BRIDGE_SELECT
cls
echo =========================================
echo       TOR MULTIPLEXER - BRIDGE
echo =========================================
echo.
echo   [1] Direct (None)
echo   [2] meek_lite (default)
echo   [3] obfs4
echo   [4] snowflake
echo.
echo =========================================
choice /C 1234 /N /M "Select Bridge (1-4): "

if errorlevel 4 set "BRIDGE_CHOICE=snowflake" & goto :SAVE_SETTINGS
if errorlevel 3 set "BRIDGE_CHOICE=obfs4" & goto :SAVE_SETTINGS
if errorlevel 2 set "BRIDGE_CHOICE=meek_lite" & goto :SAVE_SETTINGS
if errorlevel 1 set "BRIDGE_CHOICE=Direct" & goto :SAVE_SETTINGS

:SAVE_SETTINGS
echo TOR_CFG=!TOR_CFG!> "%SETTINGS_FILE%"
echo MODE_NAME=!MODE_NAME!>> "%SETTINGS_FILE%"
echo BRIDGE_CHOICE=!BRIDGE_CHOICE!>> "%SETTINGS_FILE%"
echo PROXY_MODE=!PROXY_MODE!>> "%SETTINGS_FILE%"
echo INSTANCE_COUNT=!INSTANCE_COUNT!>> "%SETTINGS_FILE%"

:START_ROUTINE
cls
echo =========================================
echo   STARTING TOR MULTIPLEXER [%MODE_NAME%]
echo   BRIDGE: [%BRIDGE_CHOICE%]
echo   DEBUG MODE: ENABLED
echo =========================================
echo.

:: --- GENERATE BRIDGE INJECTIONS & XRAY CONFIG ---
echo Generating runtime configurations...
echo $bridge = '!BRIDGE_CHOICE!' > "%~dp0boot_setup.ps1"
echo $cfg = '!TOR_CFG!' >> "%~dp0boot_setup.ps1"
echo $base = '%~dp0' >> "%~dp0boot_setup.ps1"
echo $ptPath = Join-Path $base 'Data\PluggableTransports\lyrebird.exe' >> "%~dp0boot_setup.ps1"
echo $lines = @() >> "%~dp0boot_setup.ps1"
echo if ($bridge -eq 'Direct') { $lines += 'UseBridges 0' } >> "%~dp0boot_setup.ps1"
echo if ($bridge -eq 'meek_lite') { >> "%~dp0boot_setup.ps1"
echo     $lines += 'UseBridges 1' >> "%~dp0boot_setup.ps1"
echo     $lines += "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec $ptPath" >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN' >> "%~dp0boot_setup.ps1"
echo } >> "%~dp0boot_setup.ps1"
echo if ($bridge -eq 'obfs4') { >> "%~dp0boot_setup.ps1"
echo     $lines += 'UseBridges 1' >> "%~dp0boot_setup.ps1"
echo     $lines += "ClientTransportPlugin meek_lite,obfs2,obfs3,obfs4,scramblesuit,webtunnel exec $ptPath" >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0' >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0' >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0' >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0' >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0' >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1' >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1' >> "%~dp0boot_setup.ps1"
echo } >> "%~dp0boot_setup.ps1"
echo if ($bridge -eq 'snowflake') { >> "%~dp0boot_setup.ps1"
echo     $lines += 'UseBridges 1' >> "%~dp0boot_setup.ps1"
echo     $lines += "ClientTransportPlugin snowflake exec $ptPath" >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn' >> "%~dp0boot_setup.ps1"
echo     $lines += 'Bridge snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=app.datapacket.com,www.datapacket.com ice=stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.telnyx.com:3478,stun:stun.hot-chilli.net:3478,stun:stun.fitauto.ru:3478,stun:stun.m-online.net:3478 utls-imitate=hellorandomizedalpn' >> "%~dp0boot_setup.ps1"
echo } >> "%~dp0boot_setup.ps1"
echo foreach($i in 1..$env:INSTANCE_COUNT) { >> "%~dp0boot_setup.ps1"
echo     $p = Join-Path $base "Data\Tors\Tor$i\$cfg" >> "%~dp0boot_setup.ps1"
echo     if (Test-Path $p) { >> "%~dp0boot_setup.ps1"
echo         $c = Get-Content $p ^| Where-Object { $_ -notmatch '^^UseBridges' -and $_ -notmatch '^^Bridge' -and $_ -notmatch '^^ClientTransportPlugin' } >> "%~dp0boot_setup.ps1"
echo         $c += $lines >> "%~dp0boot_setup.ps1"
echo         $c ^| Set-Content $p >> "%~dp0boot_setup.ps1"
echo     } >> "%~dp0boot_setup.ps1"
echo } >> "%~dp0boot_setup.ps1"
echo $xrayDir = Join-Path $base 'Data\Xray' >> "%~dp0boot_setup.ps1"
echo $rules = @( @{ type='field'; ip=@('127.0.0.0/8', '::1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'); outboundTag='direct' } ) >> "%~dp0boot_setup.ps1"
echo $xConfig = @{ log=@{ logLevel='warning' }; inbounds=@(@{ listen='127.0.0.1'; port=10818; protocol='mixed'; settings=@{ udp=$true } }); outbounds=@( @{ tag='proxy'; protocol='socks'; settings=@{ servers=@(@{ address='127.0.0.1'; port=10800 }) } }, @{ tag='direct'; protocol='freedom'; settings=@{} } ); routing=@{ domainStrategy='AsIs'; rules=$rules } } >> "%~dp0boot_setup.ps1"
echo $xConfig ^| ConvertTo-Json -Depth 10 ^| Set-Content (Join-Path $xrayDir 'config.json') >> "%~dp0boot_setup.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0boot_setup.ps1"
del "%~dp0boot_setup.ps1" >nul 2>&1
echo.

:: Loop through and launch exactly the amount of engines
for /L %%i in (1,1,!INSTANCE_COUNT!) do call :LAUNCH_ENGINE %%i

echo.
echo Starting HAProxy Load Balancer...
powershell.exe -Command "Start-Process -FilePath '%~dp0Data\HAproxy\haproxy.exe' -ArgumentList '-f haproxy.cfg' -WorkingDirectory '%~dp0Data\HAproxy' -WindowStyle %WINDOW_STYLE%"

echo Starting Xray Engine...
powershell.exe -Command "Start-Process -FilePath '%~dp0Data\Xray\xray.exe' -ArgumentList 'run -c config.json' -WorkingDirectory '%~dp0Data\Xray' -WindowStyle %WINDOW_STYLE%"
timeout /t 5 /nobreak >nul

if "!PROXY_MODE!"=="1" (
    echo Applying System-Wide Proxy...
    call :SET_SYSTEM_PROXY 1
) else (
    echo System-Wide Proxy remains disabled...
    call :SET_SYSTEM_PROXY 0
)

:: --- IP EXTRACTION ---
set "LOCAL_IP=UNKNOWN"
for /f "tokens=2 delims=:" %%f in ('ipconfig ^| findstr /i "IPv4"') do (
    set "LOCAL_IP=%%f"
)
set "LOCAL_IP=%LOCAL_IP: =%"

:CONTROL_PANEL
if "!PROXY_MODE!"=="1" (
    set "PROXY_TEXT=Disable System-Wide Proxy"
) else (
    set "PROXY_TEXT=Enable System-Wide Proxy"
)

cls
echo =========================================
echo    SYSTEMS ACTIVE [%MODE_NAME%]
echo =========================================
echo.
echo    Proxy Gateway: 127.0.0.1:10800
echo    LAN Address:   %LOCAL_IP%:10800
echo.
echo =========================================
echo    [1] !PROXY_TEXT!
echo    [2] Restart / Switch Config
echo    [3] Shutdown Everything and Exit
echo =========================================
choice /C 123 /N /M "Option: "

if errorlevel 3 goto :SHUTDOWN
if errorlevel 2 goto :REBOOT_CLEAN
if errorlevel 1 goto :TOGGLE_PROXY

:TOGGLE_PROXY
if "!PROXY_MODE!"=="1" (
    set "PROXY_MODE=0"
    call :SET_SYSTEM_PROXY 0
) else (
    set "PROXY_MODE=1"
    call :SET_SYSTEM_PROXY 1
)
:: Save the proxy toggle to the isolated ini file
goto :SAVE_SETTINGS_AND_RETURN

:SAVE_SETTINGS_AND_RETURN
echo TOR_CFG=!TOR_CFG!> "%SETTINGS_FILE%"
echo MODE_NAME=!MODE_NAME!>> "%SETTINGS_FILE%"
echo BRIDGE_CHOICE=!BRIDGE_CHOICE!>> "%SETTINGS_FILE%"
echo PROXY_MODE=!PROXY_MODE!>> "%SETTINGS_FILE%"
echo INSTANCE_COUNT=!INSTANCE_COUNT!>> "%SETTINGS_FILE%"
goto :CONTROL_PANEL

:REBOOT_CLEAN
echo Cleaning up and clearing saved settings...
taskkill /F /IM tor.exe /T >nul 2>&1
taskkill /F /IM haproxy.exe /T >nul 2>&1
taskkill /F /IM xray.exe /T >nul 2>&1
del "%SETTINGS_FILE%" >nul 2>&1
timeout /t 2 >nul
goto :CONFIG_SELECT

:SHUTDOWN
cls
echo Clearing System Proxy and shutting down engines...
call :SET_SYSTEM_PROXY 0
taskkill /F /IM tor.exe /T >nul 2>&1
taskkill /F /IM haproxy.exe /T >nul 2>&1
taskkill /F /IM xray.exe /T >nul 2>&1
echo Done.
timeout /t 2 >nul
exit

:: --- HELPER FUNCTIONS ---
:LAUNCH_ENGINE
set "ID=%1"
set /a "ETA=(INSTANCE_COUNT - ID + 1) * 8"
echo Launching Tor Engine %ID% of %INSTANCE_COUNT%... [ETA: %ETA%s]
powershell.exe -Command "Start-Process -FilePath '%~dp0Data\Tors\Tor%ID%\tor.exe' -ArgumentList '-f %TOR_CFG%' -WorkingDirectory '%~dp0Data\Tors\Tor%ID%' -WindowStyle %WINDOW_STYLE%"
timeout /t 8 /nobreak >nul
exit /b

:SET_SYSTEM_PROXY
if "%~1"=="1" (
    powershell.exe -NoProfile -Command "$p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'; Set-ItemProperty $p -Name ProxyEnable -Value 1; Set-ItemProperty $p -Name ProxyServer -Value '127.0.0.1:10818'; $code='[DllImport(`\"wininet.dll`\")] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);'; $w=Add-Type -MemberDefinition $code -Name W -Namespace W32 -PassThru; $w::InternetSetOption(0,39,0,0); $w::InternetSetOption(0,37,0,0);"
) else (
    powershell.exe -NoProfile -Command "$p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'; Set-ItemProperty $p -Name ProxyEnable -Value 0; $code='[DllImport(`\"wininet.dll`\")] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);'; $w=Add-Type -MemberDefinition $code -Name W -Namespace W32 -PassThru; $w::InternetSetOption(0,39,0,0); $w::InternetSetOption(0,37,0,0);"
)
exit /b