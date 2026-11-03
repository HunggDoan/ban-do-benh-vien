# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Dự án là bản đồ chỉ đường trong bệnh viện (tiếng Việt). Chi tiết vận hành đầy đủ nằm trong [HUONG_DAN.md](HUONG_DAN.md); giao diện và nội dung hiển thị đều bằng tiếng Việt.

## Kiến trúc

Ba giao diện cùng đọc **một file dữ liệu duy nhất**: `public/map_data.json` (khoa phòng, tòa nhà, điểm/cửa/ngã rẽ, đoạn đường, mã QR cũ, cấu hình giao diện trang chủ, thông báo...).

- `public/index.html` — trang người bệnh (HTML/JS tĩnh, mở khi quét QR, có bản đồ 3D, quét QR bằng camera, tìm kiếm, chỉ đường).
- `public/quantri/index.html` — trang quản trị (HTML/JS tĩnh): vẽ bản đồ, sửa khoa phòng/giao diện, kiểm tra lỗi, thử chỉ đường. Nút **Lưu** ghi `map_data.json` (và ảnh vào `public/img/`) thẳng lên GitHub qua API bằng token lưu ở trình duyệt; chặn lưu khi dữ liệu còn lỗi.
- `public/app/` — app Flutter web **đã build** (được commit; Netlify không build Flutter). Không sửa tay.
- `lib/` — nguồn Flutter: `map_models.dart`/`map_data.dart` (mô hình + tải dữ liệu), `path_finder.dart` (tìm đường), `directions.dart` (sinh câu chỉ dẫn rẽ trái/phải), `search.dart`, `qr.dart`, `map3d_view.dart`, `main.dart`. Logic tìm đường/chỉ dẫn tồn tại ở cả Dart và JS trong các trang HTML — sửa một nơi thì kiểm tra nơi kia.

Luồng triển khai: quản trị lưu → commit lên GitHub nhánh `main` → Netlify tự đăng thư mục `public` (xem [netlify.toml](netlify.toml), không có build command). Vì quản trị commit trực tiếp vào `main`, nên `git pull` trước khi sửa/push để không ghi đè `map_data.json` bằng bản cũ.

## Lệnh thường dùng

- Xem thử các trang web trên máy: `cd public && python3 -m http.server 8080` → `/`, `/quantri/`, `/app/`.
- Chạy Flutter khi dev: `flutter run -d chrome` (đọc `public/map_data.json`, khai báo trong asset của `pubspec.yaml`).
- Build Flutter vào `public/app/`: `./build_flutter.sh` (Windows: `build_flutter.bat`) — chỉ cần khi sửa `lib/`; sau đó commit cả `public/app`.
- Lint: `flutter analyze`. Test: `flutter test` (một file: `flutter test test/widget_test.dart`; hiện chỉ có test mặc định).

## Lưu ý

- Chỉ sửa dữ liệu thì không cần build lại Flutter; app tự tải dữ liệu mới.
- Mã (id) của cửa được in trên mã QR; đổi/xóa phải giữ ánh xạ sang mã mới qua danh sách "Mã QR cũ" để QR đã in vẫn dùng được.
- Thư mục `ios_backup/`, `.dart_tool/`, `build/` và các file `._*` (metadata macOS) không phải mã nguồn.
