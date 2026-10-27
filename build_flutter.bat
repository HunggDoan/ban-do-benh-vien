@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
REM ===============================================================
REM  Build app Flutter web va chep vao public\app.
REM  Chi can chay khi SUA CODE FLUTTER. Sua du lieu thi dung trang quan tri.
REM  Sau khi chay xong: commit va push len GitHub, Netlify tu dang lai.
REM ===============================================================
call flutter build web --release --base-href /app/
if errorlevel 1 (
  echo.
  echo LOI: flutter build web khong thanh cong. Xem thong bao phia tren.
  exit /b 1
)
if exist public\app rmdir /s /q public\app
xcopy /e /i /q /y build\web public\app >nul
echo.
echo XONG. App Flutter da nam trong public\app.
echo Buoc tiep theo: day len GitHub
echo   git add .
echo   git commit -m "Cap nhat app Flutter"
echo   git push
echo (hoac dung the Source Control trong VS Code). Netlify tu dang sau 1-2 phut.
endlocal
