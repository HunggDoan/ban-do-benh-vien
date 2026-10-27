#!/usr/bin/env bash
# ===============================================================
#  Build app Flutter web và chép vào public/app.
#  Chỉ cần chạy khi SỬA CODE FLUTTER. Sửa dữ liệu thì dùng trang quản trị.
#  Sau khi chạy xong: commit và push lên GitHub, Netlify tự đăng lại.
# ===============================================================
set -e
cd "$(dirname "$0")"
flutter build web --release --base-href /app/
rm -rf public/app
cp -R build/web public/app
cat <<'MSG'

XONG. App Flutter đã nằm trong public/app.
Bước tiếp theo: đẩy lên GitHub
  git add .
  git commit -m "Cập nhật app Flutter"
  git push
(hoặc dùng thẻ Source Control trong VS Code). Netlify sẽ tự đăng sau 1–2 phút.

Xem thử trên máy trước:  cd public && python3 -m http.server 8080
rồi mở http://localhost:8080 (trang người bệnh), /quantri/ (quản trị), /app/ (app Flutter)
MSG
