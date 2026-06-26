@echo off
setlocal enabledelayedexpansion

echo Detecting Host IP address...

:: We use PowerShell to quickly grab the Wi-Fi or Ethernet IP, skipping virtual adapters
for /f "usebackq tokens=*" %%I in (`powershell -NoProfile -Command "$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match 'Wi-Fi' -and $_.InterfaceAlias -notmatch 'Virtual' }).IPAddress; if (-not $ip) { $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Virtual|vEthernet|Loopback' } | Select-Object -First 1).IPAddress }; Write-Output $ip"`) do (
    set "HOST_IP=%%I"
)

if "%HOST_IP%"=="" (
    echo [!] Could not detect Host IP. Running with default...
    flutter run
) else (
    echo ^>^>^> Detected Host IP: %HOST_IP%
    echo ^>^>^> Launching Flutter app...
    flutter run --dart-define=HOST_IP=%HOST_IP%
)
