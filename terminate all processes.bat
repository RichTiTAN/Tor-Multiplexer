@echo off
cd /d "%~dp0"

echo =========================================
echo      MULTIPLEXER EMERGENCY SHUTDOWN
echo =========================================
echo.

echo Stopping all Tor Engines...
taskkill /F /IM tor.exe /T >nul 2>&1

echo Stopping HAProxy Load Balancer...
taskkill /F /IM haproxy.exe /T >nul 2>&1

echo Stopping xray...
taskkill /F /IM xray.exe /T >nul 2>&1

echo Stopping v2rayN...
taskkill /F /IM v2rayN.exe /T >nul 2>&1

echo.
echo =========================================
echo   All processes successfully terminated!
echo =========================================
timeout /t 3 /nobreak >nul
exit