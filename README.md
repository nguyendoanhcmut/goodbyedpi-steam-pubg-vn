# GoodbyeDPI Steam & PUBG Vietnam Toolkit (FPT / VNPT / Viettel)

Bộ công cụ vượt chặn **Steam** và sửa lỗi treo **`INITIALIZING...` trên PUBG** dành cho các nhà mạng Việt Nam (**FPT Telecom**, **VNPT**, **Viettel**) trên Windows 10/11 (64-bit).

---

## Tính năng nổi bật (v2.0)

1. **Cài đặt 1-Click cho mọi máy tính (`CAI_DAT_1_CLICK.cmd`):**
   - Tự động chép bộ công cụ vào `C:\Tools\goodbyedpi-0.2.3rc3-2` và tạo 2 nút ngoài Desktop: **`GoodbyeDPI BAT`** và **`GoodbyeDPI TAT`** (bấm trực tiếp không hiện bảng hỏi quyền UAC).
   - Tự động nhận diện mọi card mạng vật lý đang hoạt động (`WiFi`, `Wi-Fi`, `Ethernet`, ...) và **bỏ qua các card VPN ảo** (`Tailscale`, `WireGuard`, `ZeroTier`, `Hyper-V`).
2. **Mã hóa DNS-over-HTTPS (Windows 11 Native DoH) + Cổng dự phòng `OpenDNS:5353`:**
   - Tự động bật **Windows 11 DoH Auto-Upgrade** (`1.1.1.1` / `8.8.8.8` qua HTTPS cổng 443) để chống nhà mạng bắt gói tin UDP cổng 53.
   - Chuyển hướng các truy vấn DNS UDP cổ điển sang cổng phi chuẩn **`208.67.222.222:5353`**, vừa vượt qua bộ lọc cổng 53 vừa giữ nguyên định tuyến máy chủ tải game Steam tại Đông Nam Á (`lancache.steamcontent.com` Singapore/Hong Kong).
3. **Đua tốc độ đa vùng 512 KB cho Sảnh PUBG (`pubg_autofix.ps1`):**
   - Khắc phục triệt để lỗi PUBG treo ở màn hình **`INITIALIZING...`** do trình duyệt Coherent GT bị nghẽn băng thông khi tải gói giao diện `main.<hash>.js` (~4.8 MB không nén) từ cụm Akamai Mỹ.
   - Tự động dò đường dẫn phiên bản sảnh mới nhất và đua tốc độ tải thực tế **512 KB (`HTTP 206 Byte-Range`)** giữa các máy chủ CDN Châu Á (Hong Kong `43.175.115.189`, Singapore `43.174.32.194`, `43.168.152.146`, Akamai SEA `104.69.151.226`), ghim máy chủ nhanh nhất vào `hosts` (tải xong 4.8 MB trong ~2 giây).
   - **Không ảnh hưởng (0%) đến ping bắn trong trận:** File `hosts` và `GoodbyeDPI` chỉ xử lý giao diện web của sảnh chờ (TCP/HTTPS), không can thiệp vào luồng dữ liệu trận đấu (UDP).
4. **Tự động kiểm tra và sửa lỗi bộ nhớ đệm sảnh PUBG (`CohCache` Validator):**
   - Quét thư mục `%LOCALAPPDATA%\TslGame\Saved\CohCache` trong `<40 ms`, đối chiếu kích thước file `.ctx` với header `.hdr` và tự động xóa các file tải dở dang/lỗi gây kẹt sảnh.
5. **Tự động phát hiện tên miền mới bị chặn DPI & Tự chuyển chế độ (`-8` -> `-5`):**
   - Sử dụng `--frag-by-sni` (cắt gói tin TLS ngay trước trường SNI) và tự động chuyển từ `-8` (`--wrong-chksum`) sang `-5` (`--auto-ttl`) nếu modem/ONT nhà mạng lọc gói tin sai checksum.
   - Quét nhật ký DNS Windows để phát hiện các tên miền Steam/PUBG/Krafton mới bị cắt kết nối TLS (`curl exitcode 35/56`) và tự động bổ sung vào `steam-blacklist.txt`.

---

## Hướng dẫn sử dụng nhanh

### Cách 1: Cài đặt mới (hoặc gửi cho bạn bè)
1. Tải bản đóng gói `.zip` trong mục **Releases** (hoặc clone repo này về máy) và giải nén ra bất kỳ đâu.
2. Nhấp chuột phải vào **`CAI_DAT_1_CLICK.cmd`** -> chọn **Run as administrator** (Chạy với quyền quản trị).
3. Trên Desktop sẽ xuất hiện 2 nút:
   - **`GoodbyeDPI BAT`**: Bật dịch vụ ngầm, tự động tối ưu DNS/DoH, đua tốc độ CDN sảnh PUBG và hiển thị bảng kiểm tra kết nối trực tiếp (`HTTP 200`).
   - **`GoodbyeDPI TAT`**: Tắt hoàn toàn dịch vụ ngầm (không tự bật lại khi khởi động lại máy) và gỡ dòng ghim trong `hosts`.

### Cách 2: Gỡ cài đặt hoàn toàn
- Nhấp chuột phải vào **`service_remove.cmd`** -> chọn **Run as administrator** để xóa dịch vụ `GoodbyeDPI`, driver `WinDivert`, 2 nút ngoài Desktop và khôi phục file `hosts` nguyên bản.

---

## Cấu trúc thư mục

| File | Chức năng |
| :--- | :--- |
| `CAI_DAT_1_CLICK.cmd` / `setup_two_buttons.cmd` | Trình cài đặt tự động 1-click cho mọi máy tính Windows 10/11 |
| `goodbyedpi_on.cmd` | Khởi động dịch vụ `GoodbyeDPI`, gọi `pubg_autofix.ps1` và kiểm tra kết nối |
| `goodbyedpi_off.cmd` | Dừng dịch vụ `GoodbyeDPI`, đặt chế độ thủ công (`demand`) và dọn file `hosts` |
| `pubg_autofix.ps1` | Kích hoạt DoH, sửa lỗi `CohCache`, đua tốc độ 512 KB CDN Châu Á và tự quét tên miền bị chặn |
| `steam-blacklist.txt` | Danh sách tên miền Steam, PUBG, Krafton, BattlEye, Vivox áp dụng vượt chặn DPI |
| `service_remove.cmd` | Gỡ cài đặt toàn bộ dịch vụ, tác vụ tự động và nút bấm ngoài Desktop |
| `x86_64/` & `x86/` | Bộ thực thi mã nguồn mở `goodbyedpi.exe` (v0.2.3rc3-2 của ValdikSS) và `WinDivert` |

---

## Bảo mật & Quyền riêng tư
Bộ công cụ này **không chứa bất kỳ dữ liệu cá nhân, tài khoản hay thông tin định danh máy nào**. Chỉ bao gồm tệp thực thi mã nguồn mở chính gốc từ [ValdikSS/GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) và các kịch bản Batch/PowerShell minh bạch.
