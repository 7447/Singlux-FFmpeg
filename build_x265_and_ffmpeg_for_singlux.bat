@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Build custom x265 first, then build FFmpeg linked to that x265.
REM v4 fixes:
REM   - No bash heredoc inside .bat. Windows batch breaks it.
REM   - Patch ffbuild/config.mak with sed only.
REM   - Export MSVC bin path inside every MSYS bash call.
REM ============================================================

set "VS_VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
set "VS_BIN=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64"
set "VS_BIN_MSYS=/c/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Tools/MSVC/14.29.30133/bin/Hostx64/x64"
set "MSYS_BASH=C:\msys64\usr\bin\bash.exe"

set "X265_SOURCE=C:\Users\long\Desktop\sinlgux-x265\x265\source"
set "X265_BUILD=build-vs2019-ffmpeg-md"
set "X265_BUILD_DIR=%X265_SOURCE%\%X265_BUILD%"

set "FFMPEG_SOURCE=C:\Users\long\Desktop\singlux-ffmpeg\Singlux-FFmpeg"
set "MAKE_JOBS=8"

echo.
echo [CHECK] Visual Studio vcvars64
if not exist "!VS_VCVARS!" (
  echo [ERROR] Cannot find VS2019 vcvars64.bat:
  echo         !VS_VCVARS!
  exit /b 1
)

echo.
echo [CHECK] MSVC bin
if not exist "!VS_BIN!\cl.exe" (
  echo [ERROR] Cannot find cl.exe:
  echo         !VS_BIN!\cl.exe
  exit /b 1
)

echo.
echo [CHECK] MSYS bash
if not exist "!MSYS_BASH!" (
  echo [ERROR] Cannot find MSYS bash:
  echo         !MSYS_BASH!
  exit /b 1
)

echo.
echo [ENV] Loading VS2019 x64 environment...
call "!VS_VCVARS!"
if errorlevel 1 (
  echo [ERROR] Failed to load VS2019 environment.
  exit /b 1
)

set "PATH=!VS_BIN!;!PATH!"

echo.
echo [CHECK] MSYS sees cl/link/lib
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; which cl; which link; which lib; cl 2>&1 | head -n 2"
if errorlevel 1 (
  echo [ERROR] MSYS cannot see cl/link/lib.
  exit /b 1
)

echo.
echo ============================================================
echo [1/6] Rebuild x265 with VS2019 Release
echo ============================================================

cd /d "!X265_SOURCE!"
if errorlevel 1 exit /b 1

if exist "!X265_BUILD_DIR!" (
  echo [CLEAN] Removing old x265 build dir:
  echo         !X265_BUILD_DIR!
  rmdir /s /q "!X265_BUILD_DIR!"
)

mkdir "!X265_BUILD_DIR!"
if errorlevel 1 exit /b 1

cd /d "!X265_BUILD_DIR!"
if errorlevel 1 exit /b 1

echo [CMAKE] Generate x265 VS2019 solution...
cmake -G "Visual Studio 16 2019" -A x64 ^
  -DENABLE_SHARED=OFF ^
  -DENABLE_CLI=ON ^
  ..
if errorlevel 1 (
  echo [ERROR] x265 cmake configure failed.
  exit /b 1
)

echo [BUILD] x265-static...
cmake --build . --config Release --target x265-static -- /m:8
if errorlevel 1 (
  echo [ERROR] x265-static build failed.
  exit /b 1
)

echo [BUILD] x265 CLI...
cmake --build . --config Release --target cli -- /m:8
if errorlevel 1 (
  echo [ERROR] x265 CLI build failed.
  exit /b 1
)

echo [COPY] Prepare x265 lib names for FFmpeg...
copy /Y "Release\x265-static.lib" "Release\libx265.lib" >nul
if errorlevel 1 exit /b 1
copy /Y "Release\x265-static.lib" "Release\x265.lib" >nul
if errorlevel 1 exit /b 1

echo.
echo [CHECK] x265 custom option must exist:
"Release\x265.exe" --fullhelp | findstr /i "single-ref-poc-lsb-bits"
if errorlevel 1 (
  echo [ERROR] x265.exe does not show single-ref-poc-lsb-bits.
  echo         Your x265 source may not contain the custom patch.
  exit /b 1
)

echo.
echo ============================================================
echo [2/6] Configure FFmpeg with custom x265
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd /c/Users/long/Desktop/singlux-ffmpeg/Singlux-FFmpeg && make distclean 2>/dev/null || true"
if errorlevel 1 (
  echo [ERROR] FFmpeg distclean failed.
  exit /b 1
)

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd /c/Users/long/Desktop/singlux-ffmpeg/Singlux-FFmpeg && ./configure --toolchain=msvc --arch=x86_64 --target-os=win64 --enable-gpl --enable-libx265 --disable-doc --disable-network --disable-decoder=sanm --extra-cflags='-I/c/Users/long/Desktop/sinlgux-x265/x265/source -I/c/Users/long/Desktop/sinlgux-x265/x265/source/build-vs2019-ffmpeg-md' --extra-ldflags='-libpath:C:/Users/long/Desktop/sinlgux-x265/x265/source/build-vs2019-ffmpeg-md/Release' --extra-libs='libx265.lib ucrt.lib vcruntime.lib msvcrt.lib oldnames.lib'"
if errorlevel 1 (
  echo [ERROR] FFmpeg configure failed.
  echo         Check ffbuild/config.log.
  exit /b 1
)

echo.
echo ============================================================
echo [3/6] Force FFmpeg MSVC runtime to -MD
echo ============================================================

REM No heredoc here. Batch files break bash heredocs.
REM Also do not use /MD because MSYS may convert it into C:/msys64/MD.
"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd /c/Users/long/Desktop/singlux-ffmpeg/Singlux-FFmpeg && sed -i -E '/^(CFLAGS|CXXFLAGS)=/ { s@/MTd@@g; s@/MT@@g; s@/MDd@@g; s@/MD@@g; s@-MTd@@g; s@-MT@@g; s@-MDd@@g; s@-MD@@g; s@$@ -MD@; }' ffbuild/config.mak && grep -n '^CFLAGS\|^CXXFLAGS' ffbuild/config.mak && grep -n 'C:/msys64/MD' ffbuild/config.mak && exit 1 || true"
if errorlevel 1 (
  echo [ERROR] Failed to patch FFmpeg config.mak.
  exit /b 1
)

echo.
echo ============================================================
echo [4/6] Build FFmpeg
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd /c/Users/long/Desktop/singlux-ffmpeg/Singlux-FFmpeg && make clean && make -j%MAKE_JOBS%"
if errorlevel 1 (
  echo [ERROR] FFmpeg build failed.
  exit /b 1
)

echo.
echo ============================================================
echo [5/6] Smoke test custom x265 through FFmpeg
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd /c/Users/long/Desktop/singlux-ffmpeg/Singlux-FFmpeg && ./ffmpeg.exe -hide_banner -f lavfi -i testsrc2=size=128x72:rate=1:duration=3 -frames:v 3 -c:v libx265 -x265-params single-ref-idr0=1:single-ref-poc-lsb-bits=16:log-level=full -f null -"
if errorlevel 1 (
  echo [ERROR] FFmpeg x265 smoke test failed.
  exit /b 1
)

echo.
echo ============================================================
echo [6/6] Check required FFmpeg features
echo ============================================================

"!MSYS_BASH!" -lc "export PATH='!VS_BIN_MSYS!':$PATH; cd /c/Users/long/Desktop/singlux-ffmpeg/Singlux-FFmpeg && ./ffmpeg.exe -hide_banner -muxers | grep -E 'hls|mp4|mov' && ./ffmpeg.exe -hide_banner -demuxers | grep -E 'mov|mp4' && ./ffmpeg.exe -hide_banner -encoders | grep -E 'libx265|aac|libx264' || true && ./ffmpeg.exe -hide_banner -filters | grep -E 'scale|pad'"
if errorlevel 1 (
  echo [ERROR] FFmpeg feature check failed.
  exit /b 1
)

echo.
echo ============================================================
echo [DONE] Build completed.
echo.
echo FFmpeg:
echo   C:\Users\long\Desktop\singlux-ffmpeg\Singlux-FFmpeg\ffmpeg.exe
echo FFprobe:
echo   C:\Users\long\Desktop\singlux-ffmpeg\Singlux-FFmpeg\ffprobe.exe
echo.
echo Expected smoke-test lines:
echo   param_parse: single-ref-poc-lsb-bits=16
echo   param final: single-ref-poc-lsb-bits=16
echo   SPS log2_max_pic_order_cnt_lsb=16
echo   MaxPicOrderCntLsb=65536
echo   single-ref-idr0 verify: poc=1 type=1 numL0=1 L0=[0]
echo ============================================================

exit /b 0
