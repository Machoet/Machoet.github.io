@echo off
setlocal
cd /d "%~dp0"

rem ---------------------------------------------------------------
rem  TypeScript dev environment one-click setup
rem  Pure ASCII on purpose: avoids cmd codepage issues entirely.
rem  Pinned Node.js LTS version for the portable fallback download.
rem ---------------------------------------------------------------
set "NODE_VERSION=v22.14.0"
set "NODE_PKG=node-%NODE_VERSION%-win-x64"
set "NODE_URL_MIRROR=https://npmmirror.com/mirrors/node/%NODE_VERSION%/%NODE_PKG%.zip"
set "NODE_URL_OFFICIAL=https://nodejs.org/dist/%NODE_VERSION%/%NODE_PKG%.zip"
set "NODE_DIR=%~dp0Tools\node"
set "NODE_ZIP=%TEMP%\%NODE_PKG%.zip"
rem Extract on the same drive as the project: "move" cannot move a
rem directory across volumes (fails with Access denied).
set "EXTRACT_DIR=%~dp0Tools\_node_extract_tmp"

echo ================================================
echo   TypeScript Dev Environment Setup
echo ================================================
echo.

echo [1/3] Checking Node.js ...
where node >nul 2>nul
if not errorlevel 1 (
    echo     Node.js already installed. Version:
    node -v
    goto step2
)

if exist "%NODE_DIR%\node.exe" (
    echo     Found portable Node.js in Tools\node. Version:
    set "PATH=%NODE_DIR%;%PATH%"
    node -v
    goto step2
)

echo     Node.js not found. Checking winget ...
where winget >nul 2>nul
if errorlevel 1 (
    echo     winget not available. Falling back to portable Node.js download.
    goto portable_node
)

echo     Installing Node.js LTS via winget, please wait ...
winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
if errorlevel 1 (
    echo     winget install failed. Falling back to portable Node.js download.
    goto portable_node
)

if exist "%ProgramFiles%\nodejs\node.exe" set "PATH=%ProgramFiles%\nodejs;%PATH%"
where node >nul 2>nul
if errorlevel 1 (
    echo     winget finished but node is not usable in this session.
    echo     Falling back to portable Node.js download.
    goto portable_node
)
echo     Node.js installed via winget. Version:
node -v
goto step2

rem ---------------------------------------------------------------
rem  Portable Node.js fallback: download ZIP, extract to Tools\node
rem  No admin rights required.
rem ---------------------------------------------------------------
:portable_node
echo.
echo     Downloading portable Node.js %NODE_VERSION% win-x64 ...
if exist "%NODE_ZIP%" del /q "%NODE_ZIP%" >nul 2>nul

echo     Trying mirror: %NODE_URL_MIRROR%
call :download "%NODE_URL_MIRROR%"
if not exist "%NODE_ZIP%" (
    echo     Mirror failed. Trying official: %NODE_URL_OFFICIAL%
    call :download "%NODE_URL_OFFICIAL%"
)
if not exist "%NODE_ZIP%" (
    echo     [ERROR] Download failed from both mirror and official source.
    goto manual_install
)

echo     Extracting ZIP ...
if not exist "%~dp0Tools" mkdir "%~dp0Tools"
if exist "%EXTRACT_DIR%" rd /s /q "%EXTRACT_DIR%" >nul 2>nul
mkdir "%EXTRACT_DIR%" >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%NODE_ZIP%' -DestinationPath '%EXTRACT_DIR%' -Force" >nul 2>nul
if not exist "%EXTRACT_DIR%\%NODE_PKG%\node.exe" (
    rem Expand-Archive failed, retry with built-in tar.exe
    tar -xf "%NODE_ZIP%" -C "%EXTRACT_DIR%" >nul 2>nul
)
del /q "%NODE_ZIP%" >nul 2>nul
if not exist "%EXTRACT_DIR%\%NODE_PKG%\node.exe" (
    echo     [ERROR] Failed to extract the downloaded ZIP.
    goto manual_install
)

rem Flatten: rename the inner versioned folder to Tools\node (same volume)
if exist "%NODE_DIR%" rd /s /q "%NODE_DIR%" >nul 2>nul
move "%EXTRACT_DIR%\%NODE_PKG%" "%NODE_DIR%" >nul
rd /s /q "%EXTRACT_DIR%" >nul 2>nul
if not exist "%NODE_DIR%\node.exe" (
    echo     [ERROR] node.exe not found after extraction.
    goto manual_install
)

set "PATH=%NODE_DIR%;%PATH%"
echo     Portable Node.js ready. Version:
node -v

echo     Adding Tools\node to user-level PATH ...
call :add_user_path
goto step2

:step2
echo.
echo [2/3] Installing npm dependencies: npm install ...
call npm install
if errorlevel 1 (
    echo.
    echo     [ERROR] npm install failed. Check your network and rerun this script.
    echo.
    pause
    exit /b 1
)
echo     Dependencies installed.

echo.
echo [3/3] Verifying TypeScript compiler: npx tsc --version ...
call npx tsc --version
if errorlevel 1 (
    echo.
    echo     [ERROR] tsc verification failed. Check that step 2 succeeded.
    echo.
    pause
    exit /b 1
)
echo     TypeScript compiler is ready.
echo     Note: run Puerts.Gen from the UE editor console once to generate
echo     Typing declarations before npm run build:ts can succeed.

echo.
echo ================================================
echo   TS environment setup complete. Next steps:
echo   1. Build C++ once: open Ditchday.sln in Visual Studio.
echo   2. UE editor console: run Puerts.Gen.
echo   3. VS Code: Ctrl+Shift+B builds TS, F5 attaches debugger.
echo   See README.md for details.
echo ================================================
echo.
pause
exit /b 0

rem ---------------------------------------------------------------
rem  :download <url>
rem  Try Windows built-in curl.exe first, then PowerShell fallback.
rem  Success = "%NODE_ZIP%" exists on return.
rem ---------------------------------------------------------------
:download
where curl.exe >nul 2>nul
if not errorlevel 1 (
    curl.exe -L -f --retry 2 --connect-timeout 15 -o "%NODE_ZIP%" "%~1"
    if not errorlevel 1 if exist "%NODE_ZIP%" exit /b 0
    del /q "%NODE_ZIP%" >nul 2>nul
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%~1' -OutFile '%NODE_ZIP%' -UseBasicParsing"
if errorlevel 1 del /q "%NODE_ZIP%" >nul 2>nul
exit /b 0

rem ---------------------------------------------------------------
rem  :add_user_path
rem  Append NODE_DIR to user-level PATH so new terminals and VS Code
rem  can find node after restart. Uses PowerShell SetEnvironmentVariable
rem  instead of setx to avoid the 1024-char truncation; falls back to
rem  reg add if PowerShell is restricted. Skips if already present.
rem ---------------------------------------------------------------
:add_user_path
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d='%NODE_DIR%'; $p=[Environment]::GetEnvironmentVariable('Path','User'); if($null -eq $p){$p=''}; if(($p -split ';') -notcontains $d){[Environment]::SetEnvironmentVariable('Path', (($p.TrimEnd(';') + ';' + $d).Trim(';')), 'User')}" >nul 2>nul
reg query HKCU\Environment /v Path 2>nul | find /i "%NODE_DIR%" >nul
if not errorlevel 1 (
    echo     User PATH now contains Tools\node.
    exit /b 0
)
rem PowerShell path failed, e.g. constrained language mode: use registry.
setlocal enabledelayedexpansion
set "CUR_USER_PATH="
for /f "tokens=1,2,*" %%a in ('reg query HKCU\Environment /v Path 2^>nul') do if /i "%%a"=="Path" set "CUR_USER_PATH=%%c"
if defined CUR_USER_PATH (
    reg add HKCU\Environment /v Path /t REG_EXPAND_SZ /d "!CUR_USER_PATH!;%NODE_DIR%" /f >nul
) else (
    reg add HKCU\Environment /v Path /t REG_EXPAND_SZ /d "%NODE_DIR%" /f >nul
)
endlocal
reg query HKCU\Environment /v Path 2>nul | find /i "%NODE_DIR%" >nul
if not errorlevel 1 (
    echo     User PATH updated via registry.
) else (
    echo     [WARN] Could not update user PATH. Add manually: %NODE_DIR%
)
exit /b 0

:manual_install
echo.
echo     [ERROR] Automatic Node.js install failed.
echo     Please install Node.js LTS manually from https://nodejs.org
echo     then run this script again.
echo.
pause
exit /b 1
