@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM ChameleonSkeleton (CLAP plugin) - Multi-Target Library Build
REM Adapted from the fpc-lazarus-multiplatform-template for a
REM LIBRARY target (no CLI/GUI, no installer). Produces a .clap
REM artifact per target under dist\<target>\.
REM
REM Targets: win64, linux-x64, linux-arm, macos-intel, macos-aarch64
REM ============================================================

set "ROOT=%CD%"
set "ORIG_PATH=%PATH%"

REM --- Toolchain paths (override via environment variables if needed) ---
if not defined FPC_DIR set "FPC_DIR=C:\fpcupdeluxe\fpc\bin\i386-win32"
if not defined CROSS_BIN_DIR set "CROSS_BIN_DIR=C:\fpcupdeluxe\cross\bin"
set "FPC=%FPC_DIR%\fpc.exe"
set "OUT_ROOT=%ROOT%\dist"

REM --- Project name from NAME file (fallback to clap_skeleton) ---
set "LIB_NAME=clap_skeleton"
if exist "%ROOT%\NAME" set /p LIB_NAME=< "%ROOT%\NAME"
set "LPR_FILE=%LIB_NAME%.lpr"

REM --- Version (Assets/version.txt, patch bumps each build) ---
set "MAJOR=1"
set "MINOR=0"
set "PATCH=0"
if exist "%ROOT%\Assets\version.txt" (
    for /f "usebackq tokens=1,2,3 delims=." %%a in ("%ROOT%\Assets\version.txt") do (
        set "MAJOR=%%a"
        set "MINOR=%%b"
        set "PATCH=%%c"
    )
)
if not defined NO_VERSION_BUMP set /a PATCH=%PATCH% + 1
set "DETECTED_VERSION=!MAJOR!.!MINOR!.!PATCH!"
if not defined NO_VERSION_BUMP if not exist "%ROOT%\Assets" mkdir "%ROOT%\Assets"
if not defined NO_VERSION_BUMP echo !MAJOR!.!MINOR!.!PATCH!>"%ROOT%\Assets\version.txt"
echo Build version: !DETECTED_VERSION!

REM --- Clean previous output ---
if exist "%ROOT%\dist" rmdir /s /q "%ROOT%\dist"
del /q "%ROOT%\*.o" "%ROOT%\*.ppu" "%ROOT%\*.dll" "%ROOT%\*.so" "%ROOT%\*.dylib" 2>nul

REM --- Verify toolchain ---
call :verify_tools
if errorlevel 1 exit /b 1

if /i "%~1"=="--check" (
    echo.
    echo All required tools found - ready to build.
    exit /b 0
)

if not exist "%OUT_ROOT%" mkdir "%OUT_ROOT%"

REM ============================================================
REM Target definitions: NAME|OS|CPU|EXTRA_FLAGS|XP_PREFIX
REM COMPILER is always "cross" (ppcross*) except win64 native.
REM ============================================================
call :do_target "win64"        "win64"  "x86_64"  ""           ""
call :do_target "linux-x64"    "linux"  "x86_64"  ""           "-XPx86_64-linux-gnu-"
call :do_target "macos-intel"  "darwin" "x86_64"  ""           "-XPx86_64-apple-darwin19-"
call :do_target "macos-aarch64" "darwin" "aarch64" ""          "-XPaarch64-apple-darwin19-"

call :deploy

call :wrap

echo.
echo ==================================================
echo  ALL BUILD ATTEMPTS COMPLETE
echo ==================================================
echo Output root: %OUT_ROOT%
call :print_summary
echo.
if !SUMMARY_FAIL! GTR 0 (
    echo Build finished with !SUMMARY_FAIL! failed target^(s^).
    exit /b 1
)
exit /b 0

REM ============================================================
:do_target
set "T_NAME=%~1"
set "T_OS=%~2"
set "T_CPU=%~3"
set "EXTRA_FLAGS=%~4"
set "XP_PREFIX=%~5"
set "TD=%OUT_ROOT%\%T_NAME%"
if not exist "%TD%" mkdir "%TD%"

echo.
echo ==================================================
echo  Target: %T_NAME%  (%T_OS% %T_CPU%)
echo ==================================================

REM --- Select compiler ---
if "%T_OS%"=="win64" (
    set "CC=%FPC%"
    set "CC_FLAGS=-O2"
) else (
    if "%T_CPU%"=="x86_64" (
        set "CC=%FPC_DIR%\ppcrossx64.exe"
    ) else if "%T_CPU%"=="aarch64" (
        set "CC=%FPC_DIR%\ppcrossa64.exe"
    ) else if "%T_CPU%"=="arm" (
        set "CC=%FPC_DIR%\ppcrossarm.exe"
    ) else (
        set "CC=%FPC_DIR%\ppcross%T_CPU%.exe"
    )
    set "CC_FLAGS=-T%T_OS% -P%T_CPU% -O2 %XP_PREFIX% %EXTRA_FLAGS%"
    if "%T_OS%"=="darwin" set "PATH=%CROSS_BIN_DIR%\all-apple\bin;%PATH%"
    if "%T_OS%"=="linux" set "PATH=%CROSS_BIN_DIR%\%T_OS%-%T_CPU%;%PATH%"
)

REM --- Compile the library ---
echo [Lib] Compiling %LPR_FILE%...
pushd "%ROOT%"
if errorlevel 1 goto :target_failed
"%CC%" %CC_FLAGS% -Fu"%ROOT%" -FE"%ROOT%" %LPR_FILE%
if errorlevel 1 (
    echo   ERROR: %T_NAME% library build failed
    popd
    goto :target_failed
)
popd
echo   OK

REM --- Locate the produced binary and package as .clap ---
if "%T_OS%"=="darwin" (
    call :package_clap_bundle "%T_NAME%"
) else (
    call :package_clap_flat "%T_NAME%"
)
if errorlevel 1 goto :target_failed

echo [%T_NAME%] complete.
set "RESULT_%T_NAME%=OK"
goto :eof

:target_failed
echo.
echo *** TARGET %T_NAME% FAILED ***
set "RESULT_%T_NAME%=FAIL"
popd 2>nul
goto :eof

REM ============================================================
REM :package_clap_flat - Windows/Linux: rename the DLL/SO to .clap
REM %1 = target name
REM ============================================================
:package_clap_flat
set "TD=%OUT_ROOT%\%~1"
set "SRC="
if exist "%ROOT%\%LIB_NAME%.dll" set "SRC=%ROOT%\%LIB_NAME%.dll"
if exist "%ROOT%\%LIB_NAME%.so" set "SRC=%ROOT%\%LIB_NAME%.so"
if exist "%ROOT%\lib%LIB_NAME%.so" set "SRC=%ROOT%\lib%LIB_NAME%.so"
if not defined SRC (
    echo   ERROR: no library binary produced for %~1
    exit /b 1
)
copy /y "!SRC!" "%TD%\%LIB_NAME%.clap" >nul
if errorlevel 1 (
    echo   ERROR: failed to stage .clap
    exit /b 1
)
echo   OK: %LIB_NAME%.clap
exit /b 0

REM ============================================================
REM :package_clap_bundle - macOS: build a .clap bundle
REM %1 = target name
REM ============================================================
:package_clap_bundle
set "TD=%OUT_ROOT%\%~1"
set "SRC="
if exist "%ROOT%\lib%LIB_NAME%.dylib" set "SRC=%ROOT%\lib%LIB_NAME%.dylib"
if exist "%ROOT%\%LIB_NAME%.dylib" set "SRC=%ROOT%\%LIB_NAME%.dylib"
if not defined SRC (
    echo   ERROR: no dylib produced for %~1
    exit /b 1
)
set "BUNDLE=%TD%\%LIB_NAME%.clap"
if exist "!BUNDLE!" rmdir /s /q "!BUNDLE!"
mkdir "!BUNDLE!\Contents\MacOS" 2>nul
mkdir "!BUNDLE!\Contents\Resources" 2>nul
copy /y "!SRC!" "!BUNDLE!\Contents\MacOS\%LIB_NAME%" >nul
echo   OK: %LIB_NAME%.clap bundle
exit /b 0

REM ============================================================
REM :deploy - copy version-stamped artifacts to Deploy\ (like the template)
REM ============================================================
:deploy
echo.
echo [Deploy] Copying version-stamped artifacts to Deploy...
if not exist "%ROOT%\Deploy" mkdir "%ROOT%\Deploy"

if exist "%OUT_ROOT%\win64\%LIB_NAME%.clap" (
    copy /y "%OUT_ROOT%\win64\%LIB_NAME%.clap" "%ROOT%\Deploy\!LIB_NAME!-!DETECTED_VERSION!-win64.clap" >nul
    echo   OK: !LIB_NAME!-!DETECTED_VERSION!-win64.clap
)
if exist "%OUT_ROOT%\linux-x64\%LIB_NAME%.clap" (
    copy /y "%OUT_ROOT%\linux-x64\%LIB_NAME%.clap" "%ROOT%\Deploy\!LIB_NAME!-!DETECTED_VERSION!-linux-x64.clap" >nul
    echo   OK: !LIB_NAME!-!DETECTED_VERSION!-linux-x64.clap
)
if exist "%OUT_ROOT%\macos-intel\%LIB_NAME%.clap" (
    python "%ROOT%\tools\zip_app.py" "%OUT_ROOT%\macos-intel\%LIB_NAME%.clap" "%ROOT%\Deploy\!LIB_NAME!-!DETECTED_VERSION!-macos-intel.zip"
    echo   OK: !LIB_NAME!-!DETECTED_VERSION!-macos-intel.zip
)
if exist "%OUT_ROOT%\macos-aarch64\%LIB_NAME%.clap" (
    python "%ROOT%\tools\zip_app.py" "%OUT_ROOT%\macos-aarch64\%LIB_NAME%.clap" "%ROOT%\Deploy\!LIB_NAME!-!DETECTED_VERSION!-macos-aarch64.zip"
    echo   OK: !LIB_NAME!-!DETECTED_VERSION!-macos-aarch64.zip
)
exit /b 0

REM ============================================================
REM :wrap - OPTIONAL: build a native VST3 from the CLAP via clap-wrapper.
REM Skips cleanly unless all of these are set/present:
REM   CLAP_WRAPPER_DIR  - path to a clap-wrapper checkout (has CMakeLists.txt)
REM   CLAP_SDK_ROOT     - path to the CLAP SDK
REM   VST3_SDK_ROOT     - path to the VST3 SDK
REM   cmake             - on PATH
REM macOS AU / Linux VST3 must be built with the same command on those OSes.
REM AAX needs the Avid AAX SDK + PACE signing (not handled here).
REM ============================================================
:wrap
echo.
echo [Wrap] clap-wrapper (native VST3)...
set "PATH=%ORIG_PATH%"
for /f "delims=" %%G in ('where gcc') do set "NATIVE_CC=%%G"
for /f "delims=" %%G in ('where g++') do set "NATIVE_CXX=%%G"
if not defined CLAP_WRAPPER_DIR set "CLAP_WRAPPER_DIR=%ROOT%\deps\clap-wrapper"
if not defined CLAP_SDK_ROOT set "CLAP_SDK_ROOT=%ROOT%\deps\clap"
if not defined VST3_SDK_ROOT set "VST3_SDK_ROOT=%ROOT%\deps\vst3sdk"
if not exist "%CLAP_WRAPPER_DIR%\CMakeLists.txt" ( echo   SKIP: clap-wrapper not found ^(clone into deps\ or set CLAP_WRAPPER_DIR^) & exit /b 0 )
where cmake >nul 2>&1
if errorlevel 1 ( echo   SKIP: cmake not found & exit /b 0 )

set "WRAP_BUILD=%OUT_ROOT%\wrapper"
if exist "!WRAP_BUILD!" rmdir /s /q "!WRAP_BUILD!"
cmake -B "!WRAP_BUILD!" -S "%CLAP_WRAPPER_DIR%" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=-Wno-deprecated-declarations -DCMAKE_C_COMPILER="!NATIVE_CC!" -DCMAKE_CXX_COMPILER="!NATIVE_CXX!" -DCLAP_SDK_ROOT="%CLAP_SDK_ROOT%" -DVST3_SDK_ROOT="%VST3_SDK_ROOT%" -DCLAP_WRAPPER_OUTPUT_NAME="clap_skeleton"
if errorlevel 1 ( echo   ERROR: cmake configure failed & exit /b 1 )
cmake --build "!WRAP_BUILD!"
if errorlevel 1 ( echo   ERROR: wrapper build failed & exit /b 1 )

set "VST3_FOUND="
for /r "!WRAP_BUILD!" %%F in (*.vst3) do set "VST3_FOUND=%%F"
if not defined VST3_FOUND ( echo   WARNING: no .vst3 produced & exit /b 0 )
if not exist "%OUT_ROOT%\win64" mkdir "%OUT_ROOT%\win64"
copy /y "!VST3_FOUND!" "%OUT_ROOT%\win64\clap_skeleton.vst3" >nul
if errorlevel 1 ( echo   ERROR: failed to stage VST3 from "!VST3_FOUND!" & exit /b 1 )
echo   OK: win64 VST3
if not exist "%ROOT%\Deploy" mkdir "%ROOT%\Deploy"
copy /y "%OUT_ROOT%\win64\clap_skeleton.vst3" "%ROOT%\Deploy\!LIB_NAME!-!DETECTED_VERSION!-win64.vst3" >nul
echo   OK: Deploy VST3
exit /b 0

REM ============================================================
:verify_tools
echo [Check] Verifying toolchain...
if not exist "%FPC%" (
    echo   ERROR: fpc not found: %FPC%
    exit /b 1
)
if not exist "%CROSS_BIN_DIR%" (
    echo   ERROR: cross bin dir not found: %CROSS_BIN_DIR%
    exit /b 1
)
echo   OK
exit /b 0

REM ============================================================
:print_summary
echo.
echo ==================================================
echo  BUILD SUMMARY
echo ==================================================
set "SUMMARY_FAIL=0"
for %%T in (win64 linux-x64 macos-intel macos-aarch64) do (
    if "!RESULT_%%T!"=="OK" (
        echo   [OK]   %%T
    ) else if "!RESULT_%%T!"=="FAIL" (
        echo   [FAIL] %%T
        set /a SUMMARY_FAIL+=1
    ) else (
        echo   [SKIP] %%T
    )
)
exit /b 0
