# GoodbyeDPI Steam & PUBG Vietnam Toolkit (FPT / VNPT / Viettel / MobiFone)

Bộ công cụ vượt chặn **Steam** và sửa lỗi treo **`INITIALIZING...` trên PUBG** cho các nhà mạng Việt Nam (**FPT Telecom**, **VNPT**, **Viettel**, **MobiFone 4G/5G Hotspot & USB Tethering**) trên Windows 10/11 (64-bit).

---

## Các cải tiến trong bản v2.3

1. **Cài đặt 1-Click trên mọi máy tính (`CAI_DAT_1_CLICK.cmd`)**
   - Chép bộ công cụ vào `C:\Tools\goodbyedpi-0.2.3rc3-2` và tạo 2 nút ngoài Desktop gồm **`GoodbyeDPI BAT`** và **`GoodbyeDPI TAT`** (bấm trực tiếp không hiện bảng hỏi quyền UAC, chạy trên cả nguồn pin laptop, truyền đường dẫn an toàn qua `$env:GDPI_SELF`).
   - Nhận diện mọi card mạng vật lý và card phát sóng di động (`WiFi`, `Wi-Fi`, `Ethernet`, `Remote NDIS / USB Tethering`) và bỏ qua các card VPN ảo (`Tailscale`, `WireGuard`, `ZeroTier`, `Hyper-V`).
2. **Phân mảnh TLS 2-Byte thuận chiều (`--native-frag --allow-no-sni --max-payload 1200`) cho Steam Chromium 126**
   - Chạy cấu hình `-p -r -s -f 2 -k 2 -n -e 2 --native-frag --allow-no-sni --max-payload 1200` để cắt gói `TLS 1.3 ClientHello` tại byte thứ 2 sau `0x16 0x03` theo thứ tự thuận, không tiêm gói giả sai checksum hay lệch sequence (tương thích với cả lớp NAT kép trên Hotspot và CGNAT MobiFone 4G/5G).
   - Cờ `--max-payload 1200` giữ nguyên bộ lọc cho mọi gói bắt tay TLS nhưng cho phép các gói tải dữ liệu lớn (`1460 byte` `TLS Application Data 0x17`) đi thẳng qua nhân `WinDivert`.
   - Chặn lỗi **`ERR_CONNECTION_RESET` (`net_error -101`)** trên `steamwebhelper.exe` (Chromium 126) khi gói `TLS 1.3 ClientHello` chứa khóa hậu lượng tử `X25519Kyber768Draft00` (~1.650 byte, tách làm 2 phân đoạn TCP và đẩy trường SNI sang phân đoạn thứ 2).
3. **Google DNS (`8.8.8.8` / `8.8.4.4`) giữ nguyên EDNS Client Subnet (ECS) + Windows 11 DoH + `OpenDNS:5353`**
   - Dùng **Google Public DNS (`8.8.8.8` / `8.8.4.4`)** kết hợp **Windows 11 DoH Auto-Upgrade** để mã hóa truy vấn DNS qua HTTPS cổng 443 và giữ nguyên thông tin **EDNS Client Subnet (ECS)**. Nhờ đó, `store.steampowered.com` và `steamcommunity.com` phân giải về cụm máy chủ đệm Akamai đặt trong mạng nội địa Việt Nam (`42.119.186.x` / `42.119.184.x`) thay vì bị đẩy sang Akamai Mỹ (`104.83.x.x`).
   - Gỡ bỏ địa chỉ lặp `::1` gây nghẽn thời gian chờ IPv6 DNS (`WSAECONNREFUSED`) và đọc trực tiếp `.NET Registry` (`< 30 ms`) để bỏ qua bước cấu hình lại khi DNS đã khớp.
   - Chuyển hướng các truy vấn DNS UDP cổng 53 sang cổng phi chuẩn **`208.67.222.222:5353`** (`2620:119:35::35:5353` cho IPv6).
4. **Đua tốc độ song song 512 KB trên 7 cụm CDN Châu Á & Gộp kiểm tra `curl -Z` (`pubg_autofix.ps1`)**
   - Xử lý lỗi PUBG treo ở màn hình **`INITIALIZING...`** khi trình duyệt Coherent GT bị nghẽn băng thông lúc tải gói giao diện `main.<hash>.js` (~4.8 MB).
   - Đua tốc độ đồng thời gói **512 KB (`HTTP 206 Byte-Range`)** trên 7 cụm máy chủ CDN Châu Á (Singapore `43.174.32.224`, `43.152.143.98`, `43.168.152.146`, `43.174.32.194`, Hong Kong `43.175.115.189`, Akamai SEA `23.66.150.216`, `104.69.151.226`) kết hợp biên độ chống nhảy IP `40 ms` và kiểm tra đồng thời 3 cổng Steam trong 1 tiến trình `curl.exe -Z` duy nhất.
   - Đồng bộ hóa đa tiến trình bằng khóa `Global\GoodbyeDPI_Toolkit_Mutex`, tự động đóng các cửa sổ trạng thái cũ qua `[wmisearcher]`, giữ nguyên tiến trình `goodbyedpi.exe` khi dịch vụ đang chạy đúng cấu hình, và hoàn tất toàn bộ quá trình trong **`~1.1–1.4 giây`**.
   - File `hosts` và `GoodbyeDPI` chỉ xử lý giao diện web của sảnh chờ (TCP/HTTPS), không can thiệp vào luồng dữ liệu trận đấu (UDP) nên không làm đổi ping trong trận.
5. **Kiểm tra và dọn bộ nhớ đệm sảnh PUBG (`CohCache` Validator)**
   - Quét thư mục `%LOCALAPPDATA%\TslGame\Saved\CohCache` trong `< 50 ms` song song với quá trình kiểm tra mạng, đối chiếu kích thước file `.ctx` với header `.hdr` và xóa chính xác các cặp file tải dở dang hoặc mồ côi gây kẹt sảnh.

---

## Hướng dẫn sử dụng

### Cách 1 (Cài đặt mới hoặc gửi cho bạn bè)
1. Tải bản đóng gói `.zip` trong mục **Releases** (hoặc clone repo này về máy) và giải nén ra thư mục bất kỳ.
2. Nhấp chuột phải vào **`CAI_DAT_1_CLICK.cmd`** và chọn **Run as administrator** (Chạy với quyền quản trị).
3. Trên Desktop sẽ xuất hiện 2 nút bấm.
   - **`GoodbyeDPI BAT`** dùng để bật dịch vụ ngầm, cấu hình DNS/DoH, đua tốc độ song song CDN sảnh PUBG và in bảng kiểm tra kết nối (`HTTP 200`/`206`).
   - **`GoodbyeDPI TAT`** dùng để dừng dịch vụ ngầm (không tự bật lại khi khởi động máy), trả DNS về DHCP cho cả IPv4/IPv6 (kể cả trên các card mạng vừa rút dây), dọn khóa Registry DoH và gỡ dòng ghim trong `hosts`.

### Cách 2 (Gỡ cài đặt)
- Nhấp chuột phải vào **`service_remove.cmd`** và chọn **Run as administrator** để xóa dịch vụ `GoodbyeDPI`, driver `WinDivert`, tác vụ tự động, 2 nút ngoài Desktop, khôi phục DNS DHCP và trả lại file `hosts` nguyên bản.

---

## Cấu trúc thư mục

| File | Chức năng |
| :--- | :--- |
| `CAI_DAT_1_CLICK.cmd` / `setup_two_buttons.cmd` | Trình cài đặt tự động 1-click cho Windows 10/11 |
| `goodbyedpi_on.cmd` | Khởi động dịch vụ `GoodbyeDPI` (`--native-frag --allow-no-sni --max-payload 1200`) và gọi `pubg_autofix.ps1` |
| `goodbyedpi_off.cmd` | Dừng dịch vụ `GoodbyeDPI`, đặt chế độ thủ công (`demand`), trả DNS về DHCP, dọn khóa DoH và dọn file `hosts` |
| `pubg_autofix.ps1` | Cấu hình Google DNS/DoH (ECS), kiểm tra `CohCache`, đua tốc độ 512 KB CDN Châu Á song song và kiểm tra `curl -Z` |
| `steam-blacklist.txt` | Danh sách 30 tên miền gốc của Steam, Akamai, Fastly, PUBG, Krafton, BattlEye, Vivox áp dụng vượt chặn DPI |
| `service_remove.cmd` | Gỡ cài đặt dịch vụ, tác vụ tự động, khôi phục DNS/DoH và xóa nút bấm ngoài Desktop |
| `x86_64/` & `x86/` | Bộ thực thi mã nguồn mở `goodbyedpi.exe` (v0.2.3rc3-2 của ValdikSS) và `WinDivert` |

---

## Bảo mật & Quyền riêng tư
Bộ công cụ này không lưu trữ dữ liệu cá nhân, tài khoản hay thông tin định danh máy. Kho lưu trữ chỉ gồm tệp thực thi mã nguồn mở gốc từ [ValdikSS/GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) và các kịch bản Batch/PowerShell.
