@echo off
setlocal EnableDelayedExpansion
set "DIR=%~dp0"
set "PYTHONUTF8=1"
set "WHERE=%SystemRoot%\System32\where.exe"
set "FINDSTR=%SystemRoot%\System32\findstr.exe"
set "MORE=%SystemRoot%\System32\more.com"
if defined TOKENECONOMIZER_HOME (
    set "UV_ENV=%TOKENECONOMIZER_HOME%\uv-venv"
) else (
    set "UV_ENV=%USERPROFILE%\.tokeneconomizer\uv-venv"
)
set "UV_PY=%UV_ENV%\Scripts\python.exe"

:: 1. TE_PYTHON is the person's own choice: it runs as named when it is there, as a file or as
::    a command on PATH. One that is not there is passed over for the probes below, as the sh
::    launchers do, so a stale setting cannot keep the hook from answering. The name is read with
::    delayed expansion and run in quotes: a path with spaces or parentheses
::    ("C:\Program Files (x86)\...") stays one word and cannot end an `if` block early.
if not defined TE_PYTHON goto :probe
set "TE_PY=%TE_PYTHON:"=%"
for %%n in ("!TE_PY!") do set "TE_PY_NAME=%%~nxn"
if exist "!TE_PY!" (
    if /i "!TE_PY_NAME!"=="uv.exe" call :make_uv_venv "!TE_PY!" & if defined RUN_PY goto :run_hook
    if /i "!TE_PY_NAME!"=="uv.cmd" call :make_uv_venv "!TE_PY!" & if defined RUN_PY goto :run_hook
    if /i "!TE_PY_NAME!"=="uv" call :make_uv_venv "!TE_PY!" & if defined RUN_PY goto :run_hook
    if /i "!TE_PY_NAME!"=="uv" goto :probe
    if /i "!TE_PY_NAME!"=="uv.exe" goto :probe
    if /i "!TE_PY_NAME!"=="uv.cmd" goto :probe
    set "RUN_PY="!TE_PY!""
    goto :run_hook
)
"%WHERE%" /q "!TE_PY!" >nul 2>&1
if !ERRORLEVEL! equ 0 (
    if /i "!TE_PY_NAME!"=="uv.exe" call :make_uv_venv "!TE_PY!" & if defined RUN_PY goto :run_hook
    if /i "!TE_PY_NAME!"=="uv.cmd" call :make_uv_venv "!TE_PY!" & if defined RUN_PY goto :run_hook
    if /i "!TE_PY_NAME!"=="uv" call :make_uv_venv "!TE_PY!" & if defined RUN_PY goto :run_hook
    if /i "!TE_PY_NAME!"=="uv" goto :probe
    if /i "!TE_PY_NAME!"=="uv.exe" goto :probe
    if /i "!TE_PY_NAME!"=="uv.cmd" goto :probe
    set "RUN_PY="!TE_PY!""
    goto :run_hook
)

:probe

:: Probe script: exits 0 if >= 3.10, exits 1 if older
set "PROBE=import sys; sys.exit(sys.version_info < (3, 10))"
set "OLD_PY="

:: 2. Probe py.exe (-3 launcher)
"%WHERE%" py.exe >nul 2>&1
if !ERRORLEVEL! equ 0 (
    py -3 -E -S -c "%PROBE%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "RUN_PY=py -3"
        goto :run_hook
    ) else if !ERRORLEVEL! equ 1 (
        if not defined OLD_PY set "OLD_PY=py -3"
    )
)

:: 3. Probe python.exe on PATH, skipping WindowsApps store alias
for /f "tokens=*" %%i in ('"%WHERE%" python 2^>nul') do (
    echo %%~fi | "%FINDSTR%" /i /c:"WindowsApps" >nul
    if errorlevel 1 (
        call "%%~fi" -E -S -c "%PROBE%" >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            set "RUN_PY="%%~fi""
            goto :run_hook
        ) else if !ERRORLEVEL! equ 1 (
            if not defined OLD_PY set "OLD_PY="%%~fi""
        )
    )
)

:: 4. Probe python3.exe on PATH, skipping WindowsApps store alias
for /f "tokens=*" %%i in ('"%WHERE%" python3 2^>nul') do (
    echo %%~fi | "%FINDSTR%" /i /c:"WindowsApps" >nul
    if errorlevel 1 (
        call "%%~fi" -E -S -c "%PROBE%" >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            set "RUN_PY="%%~fi""
            goto :run_hook
        ) else if !ERRORLEVEL! equ 1 (
            if not defined OLD_PY set "OLD_PY="%%~fi""
        )
    )
)

:: 5. uv supplies a persistent virtual environment without requiring Python on PATH.
if exist "!UV_PY!" (
    "!UV_PY!" -E -S -c "%PROBE%" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "RUN_PY="!UV_PY!""
        goto :run_hook
    )
)
for /f "tokens=*" %%i in ('"%WHERE%" uv 2^>nul') do (
    call :make_uv_venv "%%~fi"
    if defined RUN_PY goto :run_hook
)

:: 6. Last-resort Windows Store aliases must be probed without starting a failed alias first
::    when a real interpreter is available.
for %%c in (python python3) do for /f "tokens=*" %%i in ('"%WHERE%" %%c 2^>nul') do (
    echo %%~fi | "%FINDSTR%" /i /c:"WindowsApps" >nul
    if not errorlevel 1 (
        call "%%~fi" -E -S -c pass >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            call "%%~fi" -E -S -c "%PROBE%" >nul 2>&1
            if !ERRORLEVEL! equ 0 (
                set "RUN_PY="%%~fi""
                goto :run_hook
            ) else if !ERRORLEVEL! equ 1 (
                if not defined OLD_PY set "OLD_PY="%%~fi""
            )
        )
    )
)

:: 7. If only older Python was found, hand off to it so bootstrap fails open
if defined OLD_PY (
    set "RUN_PY=%OLD_PY%"
    goto :run_hook
)

:: 8. Fail open: drain stdin and output empty JSON
for /f "tokens=*" %%a in ('"%MORE%" 2^>nul') do rem
if defined TOKENECONOMIZER_HOME (
    set "TE_STATE_ROOT=%TOKENECONOMIZER_HOME%"
) else (
    set "TE_STATE_ROOT=%USERPROFILE%\.tokeneconomizer"
)
if not exist "!TE_STATE_ROOT!" mkdir "!TE_STATE_ROOT!" 2>nul
>>"!TE_STATE_ROOT!\errors.log" echo te: no Python on PATH ^(set TE_PYTHON or install uv^)
echo {}
exit /b 0

:make_uv_venv
if not exist "!UV_PY!" (
    call "%~1" venv --allow-existing --no-project --python 3.10 "!UV_ENV!" >nul 2>&1
)
if exist "!UV_PY!" (
    "!UV_PY!" -E -S -c "%PROBE%" >nul 2>&1
    if !ERRORLEVEL! equ 0 set "RUN_PY="!UV_PY!""
)
exit /b 0

:run_hook
call %RUN_PY% "%DIR%te_bootstrap.py" hook %*
exit /b !ERRORLEVEL!
