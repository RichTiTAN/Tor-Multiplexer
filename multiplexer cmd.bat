@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:CONFIG_SELECT
cls
echo =========================================
echo       TOR MULTIPLEXER - BOOT MENU
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
goto :START_ROUTINE

:SET_STABLE
set "TOR_CFG=torrc"
set "MODE_NAME=STABLE_GLOBAL"
goto :START_ROUTINE

:START_ROUTINE
cls
echo =========================================
echo   STARTING TOR MULTIPLEXER [%MODE_NAME%]
echo =========================================
echo.

:: Loop through and launch all 8 engines safely
for /L %%i in (1,1,8) do call :LAUNCH_ENGINE %%i

echo.
echo Starting HAProxy Load Balancer (Hidden)...
powershell.exe -Command "Start-Process -FilePath '%~dp0Data\HAproxy\haproxy.exe' -ArgumentList '-f haproxy.cfg' -WorkingDirectory '%~dp0Data\HAproxy' -WindowStyle Hidden"
timeout /t 5 /nobreak >nul

:: --- IP EXTRACTION ---
set "LOCAL_IP=UNKNOWN"
for /f "tokens=2 delims=:" %%f in ('ipconfig ^| findstr /i "IPv4"') do (
    set "LOCAL_IP=%%f"
)
set "LOCAL_IP=%LOCAL_IP: =%"

:CONTROL_PANEL
cls
echo =========================================
echo   SYSTEMS ACTIVE [%MODE_NAME%]
echo =========================================
echo.
echo   Proxy Gateway: 127.0.0.1:10800
echo   LAN Address:   %LOCAL_IP%:10800
echo.
echo =========================================
echo   [1] Launch v2rayN
echo   [2] Restart / Switch Config
echo   [3] Shutdown Everything and Exit
echo =========================================
choice /C 123 /N /M "Option: "

if errorlevel 3 goto :SHUTDOWN
if errorlevel 2 goto :REBOOT_CLEAN
if errorlevel 1 goto :LAUNCH_V2RAY

:LAUNCH_V2RAY
start "" "%~dp0Data\v2rayN\v2rayN.exe"
goto :CONTROL_PANEL

:REBOOT_CLEAN
echo Cleaning up...
taskkill /F /IM tor.exe /T >nul 2>&1
taskkill /F /IM haproxy.exe /T >nul 2>&1
timeout /t 2 >nul
goto :CONFIG_SELECT

:SHUTDOWN
cls
echo Shutting down all engines...
taskkill /F /IM tor.exe /T >nul 2>&1
taskkill /F /IM haproxy.exe /T >nul 2>&1
echo Done.
timeout /t 2 >nul
exit

:: --- HELPER LABEL TO LAUNCH ENGINES ---
:LAUNCH_ENGINE
set "ID=%1"
set /a "WAIT=ID * 8"
set /a "ETA=72 - WAIT"
echo Launching Tor Engine %ID% (Hidden)... [ETA: %ETA%s]

:: Launching Tor invisibly
powershell.exe -Command "Start-Process -FilePath '%~dp0Data\Tors\Tor%ID%\tor.exe' -ArgumentList '-f %TOR_CFG%' -WorkingDirectory '%~dp0Data\Tors\Tor%ID%' -WindowStyle Hidden"

timeout /t 8 /nobreak >nul
exit /b