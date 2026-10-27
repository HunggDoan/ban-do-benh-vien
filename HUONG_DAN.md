# Hướng dẫn vận hành bản đồ bệnh viện

## 1. Cách hệ thống chạy

```
Người vận hành (CNTT)                 GitHub (kho chứa code)              Netlify (trang web)
  mở /quantri/ → sửa → bấm Lưu  ──►   lưu map_data.json + lịch sử   ──►   tự đăng lại sau 1–2 phút
                                                                           │
                                       Người bệnh quét QR  ◄───────────────┘
```

- **Trang người bệnh** `…netlify.app/`: trang nhẹ, mở ngay khi quét QR.
- **Trang quản trị** `…netlify.app/quantri/`: sửa khoa phòng, tòa nhà, cửa, đường đi trên bản đồ, kiểm tra lỗi, thử chỉ đường, rồi lưu.
- **App Flutter** `…netlify.app/app/`: bản đầy đủ. Khi mở, app tự tải dữ liệu mới nhất, nên không cần build lại khi chỉ đổi dữ liệu.
- **Mã QR cho IT**: `…netlify.app/#qr`.

Mọi dữ liệu nằm trong **một file duy nhất**: `public/map_data.json`.

## 2. Cấu trúc dự án

```
ten_du_an/
├── pubspec.yaml
├── netlify.toml               ← cấu hình Netlify (đăng thư mục public)
├── build_flutter.bat / .sh    ← chỉ chạy khi sửa code Flutter
├── HUONG_DAN.md
├── lib/                       ← code Flutter (8 file .dart)
└── public/                    ← toàn bộ trang web, Netlify đăng thư mục này
    ├── index.html             ← trang người bệnh
    ├── map_data.json          ← DỮ LIỆU DUY NHẤT
    ├── quantri/index.html     ← trang quản trị
    └── app/                   ← app Flutter đã build (tạo bởi build_flutter)
```

## 3. Chuyển sang cấu trúc mới (làm một lần)

1. Chép `public/`, `lib/`, `netlify.toml`, `build_flutter.bat`, `build_flutter.sh`, `HUONG_DAN.md` vào thư mục gốc dự án, cùng cấp với `pubspec.yaml`.
2. Xóa các file cũ không dùng nữa: thư mục `trang_benh_nhan/`, thư mục `netlify_out/`, file `assets/map_data.json`, `build_netlify.bat`, `build_netlify.sh`.
3. Trong `pubspec.yaml`, sửa phần assets thành:
   ```yaml
   flutter:
     assets:
       - public/map_data.json
   ```
4. Mở terminal ở thư mục gốc dự án và chạy `./build_flutter.sh` (Windows: `.\build_flutter.bat`) để tạo `public/app`.
5. Xem thử trên máy:
   ```
   cd public
   python3 -m http.server 8080
   ```
   Mở http://localhost:8080 (trang người bệnh), http://localhost:8080/quantri/ (quản trị) và http://localhost:8080/app/ (app Flutter). Bấm `Ctrl+C` để dừng.

## 4. Đưa dự án lên GitHub (làm một lần)

### 4.1. Tạo tài khoản và kho

1. Đăng ký tài khoản tại https://github.com. Nên tạo một **Organization** đứng tên bệnh viện (miễn phí), để kho không phụ thuộc tài khoản cá nhân khi có người nghỉ việc.
2. Tạo kho mới (**New repository**), ví dụ tên `ban-do-benh-vien`. Chọn **Private**. Không tích thêm README hay .gitignore, vì dự án đã có sẵn.

### 4.2. Đẩy code lên

**Cách dễ nhất, dùng VS Code:** mở thẻ **Source Control** (biểu tượng nhánh cây bên trái) → **Publish to GitHub** → chọn **private** → chọn tổ chức và tên kho.

**Hoặc dùng terminal**, ở thư mục gốc dự án:
```
git init
git add .
git commit -m "Bản đồ bệnh viện"
git branch -M main
git remote add origin https://github.com/<tên-tổ-chức>/ban-do-benh-vien.git
git push -u origin main
```

Kiểm tra trên GitHub: kho phải có `public/map_data.json`, `public/index.html`, `public/quantri/index.html` và `public/app/`.

> `public/app/` **phải** được đẩy lên, vì Netlify không build Flutter. File `.gitignore` của Flutter chỉ bỏ qua `build/`, không bỏ qua `public/app/`, nên không cần sửa gì. Nên thêm 2 dòng sau vào cuối `.gitignore`:
> ```
> netlify_out/
> ._*
> ```

### 4.3. Nối Netlify với GitHub

1. Vào trang quản lý site `bando-sannhinghean` trên Netlify.
2. Mở **Site configuration → Build & deploy → Continuous deployment**.
3. Bấm **Link repository** (nếu site đã nối kho khác: **Manage repository → Link to a different repository**). Chọn GitHub, cho phép Netlify truy cập kho `ban-do-benh-vien`.
4. Netlify tự đọc `netlify.toml` (thư mục đăng: `public`, không có lệnh build). Để trống ô **Build command**, nhánh chọn `main`.
5. Bấm **Deploy**. Từ nay, mỗi lần có thay đổi trên nhánh `main`, Netlify tự đăng lại. **Không còn phải kéo thả thư mục nữa.**

Tên miền `bando-sannhinghean.netlify.app` giữ nguyên, nên mọi mã QR đã in vẫn dùng được.

### 4.4. Cấp quyền cho người vận hành

Mỗi người ở phòng CNTT dùng tài khoản GitHub riêng, để lịch sử ghi đúng ai sửa gì.

1. Người quản lý tổ chức thêm từng người vào kho: kho → **Settings → Collaborators and teams → Add people**, quyền **Write**.
2. Mỗi người tự tạo mã truy cập (token):
   - GitHub → ảnh đại diện → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**.
   - **Resource owner**: chọn tổ chức của bệnh viện.
   - **Repository access**: Only select repositories → chọn `ban-do-benh-vien`.
   - **Permissions → Repository permissions → Contents**: chọn **Read and write**.
   - **Expiration**: nên đặt 1 năm và ghi lịch gia hạn.
   - Bấm **Generate token** và chép mã `github_pat_…` ngay. GitHub chỉ hiện mã này một lần.
   - Nếu tổ chức bật duyệt token, người quản lý phải duyệt trong **Organization settings → Personal access tokens** thì token mới dùng được.
3. Mở `…netlify.app/quantri/` → **Cài đặt GitHub**, nhập: tài khoản là **tên tổ chức**, tên kho, nhánh `main`, đường dẫn `public/map_data.json`, token, tên người sửa → **Kiểm tra kết nối** → **Lưu cài đặt**.

Token chỉ lưu trên trình duyệt của máy đó. Ai mở trang quản trị mà không có token thì chỉ xem được, **không lưu được**. Khi nghỉ việc: xóa người đó khỏi kho, token của họ lập tức hết tác dụng.

## 5. Dùng trang quản trị

### 5.1. Bố cục

- **Bên trái**: công cụ vẽ.
- **Giữa**: bản đồ nhìn từ trên xuống, để đặt điểm chính xác.
- **Bên phải**: các thẻ:
  - **Đối tượng**: sửa thứ đang chọn trên bản đồ.
  - **Khoa phòng**: điểm đến và danh sách khoa theo tầng.
  - **Danh sách**: tìm mọi điểm, tòa, điểm đến.
  - **Kiểm tra**: lỗi, cảnh báo và **thử chỉ đường**.
  - **Khác**: cấu hình, nút tìm nhanh, mã QR cũ, hướng nhìn, khung cổng, chữ trên bản đồ, sửa JSON trực tiếp.
  - **Lịch sử**: các lần lưu, mở lại bản cũ.

### 5.2. Công cụ và phím tắt

| Phím | Công cụ | Cách dùng |
|---|---|---|
| `V` | Chọn | Bấm để chọn. Kéo điểm hoặc tòa nhà để di chuyển, kéo 4 góc tòa để đổi kích thước. Kéo chỗ trống để kéo bản đồ |
| `D` | Thêm cửa | Bấm chỗ trống để đặt cửa. Bấm lên đoạn đường để chèn cửa vào giữa đoạn |
| `J` | Thêm ngã rẽ | Giống thêm cửa. Dùng ở chỗ đường giao nhau hoặc gấp khúc |
| `G` | Thêm cổng | Đặt điểm cổng ra vào |
| `C` | Nối đường | Bấm điểm đầu, rồi bấm lần lượt các điểm tiếp theo. Bấm chỗ trống để tạo ngã rẽ mới ngay tại đó. `Esc` hoặc chuột phải để dừng |
| `B` | Vẽ tòa nhà | Kéo từ góc này sang góc đối diện |
| `X` | Xóa | Bấm vào thứ cần xóa |
| `Ctrl+Z` / `Ctrl+Y` | | Hoàn tác / làm lại |
| `Ctrl+S` | | Lưu lên GitHub |
| `F` / `I` | | Xem toàn bộ / hiện mã điểm |
| `Space` | | Giữ để kéo bản đồ khi đang dùng công cụ khác |
| `Alt` | | Giữ để tắt tự gióng thẳng hàng |

Khi đặt hoặc kéo điểm, trang **tự gióng thẳng hàng** với các điểm khác (đường nét đứt màu xanh hiện ra). Nhờ vậy đoạn đường thẳng, và câu chỉ dẫn rẽ trái/phải mới đúng.

### 5.3. Việc thường gặp

**Đổi, thêm, xóa khoa phòng.** Thẻ **Khoa phòng** → chọn tòa → sửa trong bảng. Mỗi dòng gồm tầng, tên khoa và từ khóa không dấu (tên gọi tắt, tên người bệnh hay gõ). Để trống ô tầng nếu chưa rõ. Dùng nút ↑ ↓ hoặc **Sắp xếp theo tầng** để đổi thứ tự.

**Thêm tòa nhà mới (ví dụ Tòa G).**
1. Bấm `B`, kéo khung tòa trên bản đồ. Ở thẻ Đối tượng, sửa chữ trên mái (`G`), số tầng và loại.
2. Bấm `D`, đặt cửa ở mép tòa. Ở thẻ Đối tượng, đổi tên ("Cửa Tòa G") và mã (`cua_g`).
3. Bấm `C`, bấm vào cửa vừa đặt, rồi bấm lên lối đi gần nhất. Trang tự chèn ngã rẽ vào lối đi và nối tới cửa. Bấm `Esc` để dừng. Chọn ngã rẽ vừa tạo, đặt **tên mốc** như "ngã ba trước Tòa G".
4. Chọn lại tòa nhà → **Tạo điểm đến cho tòa này** → thêm cửa (`cua_g`) và các khoa theo tầng.
5. Thẻ **Kiểm tra** → **Thử chỉ đường** từ Cổng chính tới một khoa của tòa G, đọc câu chỉ dẫn.
6. Bấm **Xem thử trang người bệnh** để xem trên bản đồ 3D thật, khi chưa lưu.
7. Bấm **Lưu lên GitHub**.

**Đánh dấu hành lang có mái che.** Chọn đoạn đường → tích **Có mái che**. Bản đồ 3D tự vẽ mái, câu chỉ dẫn ghi "đi theo hành lang có mái che".

**Đoạn đi xuyên trong nhà.** Chọn đoạn đường → tích **Đi xuyên trong nhà** → ghi tên chỗ đi qua (ví dụ "sảnh tầng 1 Tòa A1").

**Tòa bị đập hoặc ngừng dùng.** Xóa tòa, các cửa và điểm đến của tòa. Khi xóa một cửa đã từng có, trang **tự đưa mã của cửa vào danh sách "Mã QR cũ"**. Người quét QR cũ sẽ được báo và đưa về Cổng chính; có thể đổi sang chuyển tới cửa khác ở thẻ Khác.

**Đổi mã một cửa.** Mã là thứ in trên QR. Khi đổi, giữ tích "tự chuyển mã cũ sang mã mới" để QR đã in vẫn đúng.

**In mã QR cho cửa mới.** Mở `…netlify.app/#qr`, chọn mũi tên hướng người đứng quét đang nhìn, bấm **Xem thử trên bản đồ**, rồi in.

### 5.4. Lưu, nháp và lịch sử

- **Tự lưu nháp.** Mọi thay đổi chưa lưu được giữ trên máy. Lỡ tắt trình duyệt, lần sau mở lại sẽ có thanh vàng "Có bản nháp chưa lưu".
- **Không lưu được khi còn lỗi.** Ví dụ cửa chưa nối đường, điểm đến chưa có cửa, mã trùng. Trang người bệnh vì vậy không bao giờ bị hỏng do sửa nhầm. Cảnh báo (màu vàng) thì vẫn lưu được.
- **Hai người cùng sửa.** Nếu trong lúc bạn sửa có người khác đã lưu, trang sẽ báo trước khi ghi đè. Bạn có thể tải file của mình về để giữ lại.
- **Khôi phục bản cũ.** Thẻ **Lịch sử** → **Mở bản này** → kiểm tra → **Lưu**. Mỗi lần lưu đều ghi người sửa, giờ sửa và mô tả.
- **Không có mạng tới GitHub.** Bấm **Tải file** để tải `map_data.json` về, chép vào `public/` trong dự án, rồi commit và push.

## 6. Khi sửa code Flutter

1. Sửa code trong `lib/`, chạy thử bằng `flutter run -d chrome`. Bản chạy thử đọc dữ liệu từ `public/map_data.json` trên máy.
2. Chạy `./build_flutter.sh` (Windows: `.\build_flutter.bat`).
3. Commit và push lên GitHub. Netlify tự đăng.

Trước khi sửa code, nên chạy `git pull` (hoặc nút đồng bộ trong VS Code) để lấy `map_data.json` mới nhất mà trang quản trị đã lưu. Nếu không, lần push sau có thể ghi đè dữ liệu cũ lên.

## 7. Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| Quản trị báo "Token sai hoặc đã hết hạn" | Tạo token mới (mục 4.4) và nhập lại trong Cài đặt GitHub |
| Báo "Token không có quyền với kho này" | Token phải chọn đúng kho và có quyền Contents: Read and write; tổ chức có thể cần duyệt token |
| Báo "Không kết nối được tới GitHub" | Mạng bệnh viện có thể chặn `api.github.com`. Nhờ quản trị mạng mở, hoặc dùng mạng khác |
| Đã lưu nhưng trang người bệnh chưa đổi | Chờ 1–2 phút. Xem tab **Deploys** trên Netlify có lần đăng mới chưa. Tải lại trang |
| Netlify đăng lỗi | Kiểm tra Netlify đang đọc `netlify.toml` (thư mục đăng `public`) và ô Build command để trống |
| `/app/` không mở được | Chưa chạy `build_flutter`, hoặc chưa push thư mục `public/app` |
| `flutter run` báo không đọc được dữ liệu | Kiểm tra `pubspec.yaml` có dòng `- public/map_data.json` |
