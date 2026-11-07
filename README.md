# GoodbyeDPI Steam & PUBG Vietnam Toolkit (FPT / VNPT / Viettel / MobiFone)

Bộ công cụ vượt chặn **Steam** và sửa lỗi treo **`INITIALIZING...` trên PUBG** cho các nhà mạng Việt Nam (**FPT Telecom**, **VNPT**, **Viettel**, **MobiFone 4G/5G Hotspot & USB Tethering**) trên Windows 10/11 (64-bit).

---

## Các cải tiến trong bản v2.5 (Patch-Proof Self-Healing + Intel Iris Xe Optimizer)

1. **Cài đặt 1-Click & Điều khiển thủ công hiển thị trạng thái trực tiếp (`CAI_DAT_1_CLICK.cmd`)**
   - Chép bộ công cụ vào `C:\Tools\goodbyedpi-0.2.3rc3-2` và tạo 2 nút ngoài Desktop gồm **`GoodbyeDPI BAT`** và **`GoodbyeDPI TAT`** (giữ chế độ `DEMAND_START` để người dùng chủ động bật/tắt bằng tay, cửa sổ giữ nguyên hiển thị trạng thái `Service`, `WinDivert`, `Lobby CDN IP` cho tới khi nhấn `Enter`).
   - Nhận diện mọi card mạng vật lý và card phát sóng di động (`WiFi`, `Wi-Fi`, `Ethernet`, `Remote NDIS / USB Tethering`) và bỏ qua các card VPN ảo (`Tailscale`, `WireGuard`, `ZeroTier`, `Hyper-V`).
2. **Phân mảnh TLS 2-Byte thuận chiều (`--native-frag --allow-no-sni --max-payload 1200`) cho Steam Chromium 126**
   - Chạy cấu hình `-p -r -s -f 2 -k 2 -n -e 2 --native-frag --allow-no-sni --max-payload 1200` để cắt gói `TLS 1.3 ClientHello` tại byte thứ 2 sau `0x16 0x03` theo thứ tự thuận, không tiêm gói giả sai checksum hay lệch sequence (tương thích với cả lớp NAT kép trên Hotspot và CGNAT MobiFone 4G/5G).
   - Cờ `--max-payload 1200` giữ nguyên bộ lọc cho mọi gói bắt tay TLS nhưng cho phép các gói tải dữ liệu lớn (`1460 byte` `TLS Application Data 0x17`) đi thẳng qua nhân `WinDivert`.
3. **Google DNS (`8.8.8.8` / `8.8.4.4`) giữ nguyên EDNS Client Subnet (ECS) + Windows 11 DoH + Chống treo IPv6 RDNSS**
   - Dùng **Google Public DNS (`8.8.8.8` / `8.8.4.4`)** kết hợp **Windows 11 DoH Auto-Upgrade** để giữ nguyên thông tin **EDNS Client Subnet (ECS)** tại Việt Nam mà không dùng `--dns-addr`/`--dnsv6-addr` ép qua OpenDNS. Nhờ đó, `prod-live-front.playbattlegrounds.com` phân giải thẳng về cụm **Amazon CloudFront TP.HCM `SGN50` (`3.162.66.x`)** tải gói sảnh `4.83 MB` trong `1.03 giây`.
   - Tự động xóa IPv6 RDNSS chết trên card mạng chỉ có Link-Local (`fe80::`) và đặt `DisabledComponents = 0x20` (ưu tiên IPv4), cắt giảm thời gian chờ truy vấn `AAAA` từ `7.258 ms` xuống `138 ms`.
4. **Tự phục hồi sau mỗi bản cập nhật PUBG (`pubg_autofix.ps1` & `pubg_wireless_and_hz_guard.ps1`)**
   - **Đồng bộ `IntegrityCheckHistory.csv` (`559/559` file `< 50 ms`)**: Ngăn `TslGame.exe` đọc và băm SHA-1 lại `4.10 GB` mỗi lần mở game sau khi cập nhật bản vá mới.
   - **Chặn dải IP `43.*` (Tencent COS chuyển hướng sang `.com.cn`) & Tự động làm ấm `CohCache`**: Kiểm tra giao thức kép trên cả `/?provider=steam` và `/index.html`, dọn sạch file `Server: Lego Server`, tự động tải trước (pre-warm) toàn bộ `.js`/`.css` của bản vá mới và gia hạn TTL 24 giờ cho các tài nguyên bất biến (`80/80` local cache hit, pha nạp sảnh `LL = 12.60 giây`).
   - **Nạp trước `TslGame.exe` vào RAM Page Cache & `IFEO` High Priority tại `t = 0 ms`**: Giảm thời gian đọc lặp 12 lần (`2.78 GB`) của `BEService.exe`, tự động đổi tên `Content\Movies\*.mp4 -> *.mp4.bak` khi Steam cập nhật và dọn thư mục `Saved\Demos` quá 14 ngày.
5. **Bộ tối ưu chuyên biệt cho Laptop Intel Iris Xe (`TOI_UU_PUBG_IRIS_XE.cmd` & `pubg_iris_xe_boost.ps1`)**
   - Thiết kế riêng cho laptop văn phòng dùng iGPU chia sẻ RAM (như **Dell Latitude 3450 `i7-1355U + Intel Iris Xe 96 EU + 16GB DDR5`**).
   - Tích hợp bảng Menu chọn nhanh 5 chế độ độ phân giải (`[1] NativeCrisp` Full HD `1080p/1200p @ 70% Scale` + `Texture Low` tâm ngắm nét `1:1`; `[2] HighClarity` `1080p/1200p @ 80% Scale`; `[3] BalancedPlus` `1600x900 @ 85%`; `[4] PerfSharp` `720p @ 100%`; `[5] UltraPerf` `720p @ 80%`), tạo gói nguồn `PUBG Iris Xe Boost` giới hạn nhân P `3700 MHz` / nhân E `2800 MHz` để nhường `10–12 W` điện cho iGPU giữ xung `1200–1300 MHz`.
   - Áp dụng kỹ thuật mã nguồn mở từ `System Informer`, `EnergyStar`, `TimerResolution`, `MemReduct` và `pse-powertuner`: bật `EcoQoS` (`0x5`) + ghim 8 nhân E (`0xFF0`) cho ứng dụng nền, giữ xung đồng hồ hệ thống `0.5 ms` (`NtSetTimerResolution`), xả `Modified + Standby RAM` trước trận, tắt `QuickEdit` chống đứng màn hình và **tự động khôi phục 100% về gói nguồn `Balanced` văn phòng ngay khi đóng game**.

---

## Hướng dẫn sử dụng

### Cách 1 (Nhanh nhất - Bấm `Windows + R`, dán 1 dòng lệnh là tự cài và bật luôn)
1. Nhấn tổ hợp phím **`Windows + R`** trên bàn phím để mở hộp thoại **Run**.
2. Dán dòng lệnh dưới đây vào và nhấn **Enter** (sau đó bấm **Yes** khi Windows hỏi quyền Admin).

```text
powershell -c "irm https://github.com/nguyendoanhcmut/goodbyedpi-steam-pubg-vn/raw/main/install.ps1|iex"
```

*(Hoặc nếu đang mở sẵn cửa sổ **PowerShell**, chỉ cần dán `irm https://github.com/nguyendoanhcmut/goodbyedpi-steam-pubg-vn/raw/main/install.ps1 | iex` rồi nhấn **Enter**).*

### Cách 2 (Tải file `.zip` thủ công)
1. Tải bản đóng gói `.zip` trong mục **Releases** (hoặc clone repo này về máy) và giải nén ra thư mục bất kỳ.
2. Nhấp chuột phải vào **`CAI_DAT_1_CLICK.cmd`** và chọn **Run as administrator** (Chạy với quyền quản trị).
3. Trên Desktop sẽ xuất hiện 2 nút bấm.
   - **`GoodbyeDPI BAT`** dùng để bật dịch vụ ngầm, cấu hình DNS/DoH, đua tốc độ song song CDN sảnh PUBG và in bảng kiểm tra kết nối (`HTTP 200`/`206`).
   - **`GoodbyeDPI TAT`** dùng để dừng dịch vụ ngầm (không tự bật lại khi khởi động máy), trả DNS về DHCP cho cả IPv4/IPv6 (kể cả trên các card mạng vừa rút dây), dọn khóa Registry DoH và gỡ dòng ghim trong `hosts`.

### Cách 3 (Dành riêng cho Laptop Intel Iris Xe - Dell Latitude 3450 `i7-1355U`)
- Nhấp đúp vào **`C:\Tools\goodbyedpi-0.2.3rc3-2\TOI_UU_PUBG_IRIS_XE.cmd`** trước khi mở PUBG để kích hoạt chế độ tối ưu iGPU (giữ cửa sổ `[SESSION GUARD]` mở trong lúc chơi; khi đóng game hoặc tắt cửa sổ, máy tự động trả lại gói nguồn `Balanced` văn phòng trong `< 0.5 giây`).
- Để hoàn tác toàn bộ cấu hình `.ini` và Registry về mặc định bất cứ lúc nào: chạy `TOI_UU_PUBG_IRIS_XE.cmd -Restore` (hoặc chạy kiểm thử không ghi file bằng `TOI_UU_PUBG_IRIS_XE.cmd -DryRun`).

### Cách 4 (Gỡ cài đặt GoodbyeDPI)
- Nhấp chuột phải vào **`service_remove.cmd`** và chọn **Run as administrator** để xóa dịch vụ `GoodbyeDPI`, driver `WinDivert`, tác vụ tự động, 2 nút ngoài Desktop, khôi phục DNS DHCP và trả lại file `hosts` nguyên bản.

---

## Cấu trúc thư mục

| File | Chức năng |
| :--- | :--- |
| `CAI_DAT_1_CLICK.cmd` / `setup_two_buttons.cmd` | Trình cài đặt tự động 1-click cho Windows 10/11 |
| `goodbyedpi_on.cmd` | Khởi động dịch vụ `GoodbyeDPI` (`--native-frag --allow-no-sni --max-payload 1200`), gọi `pubg_autofix.ps1` và giữ cửa sổ trạng thái |
| `goodbyedpi_off.cmd` | Dừng dịch vụ `GoodbyeDPI`, đặt chế độ thủ công (`demand`), trả DNS về DHCP, dọn khóa DoH, dọn `hosts` và giữ cửa sổ trạng thái |
| `pubg_autofix.ps1` | Đồng bộ `IntegrityCheckHistory.csv`, tối ưu DNS/DoH + IPv6 RDNSS, làm ấm `CohCache`, đua tốc độ CloudFront SGN50 và nạp trước `TslGame.exe` vào RAM |
| `pubg_wireless_and_hz_guard.ps1` | Tiến trình canh ngầm Wi-Fi / 144Hz / tự động phục hồi sau mỗi bản cập nhật PUBG |
| `TOI_UU_PUBG_IRIS_XE.cmd` & `pubg_iris_xe_boost.ps1` | Trình khởi chạy & điều phối tối ưu PUBG có tự động hoàn nguyên (`Session Guard`) cho laptop `i7-1355U + Intel Iris Xe` |
| `iris_xe_lib_native_diag.ps1` / `ue4_cache.ps1` / `power_os.ps1` | Bộ 3 thư viện C# P/Invoke (`EcoQoS`, `0.5ms Timer`, `Standby RAM Purge`, `powrprof.dll`, `.ini` & `iFlip` toàn màn hình) |
| `steam-blacklist.txt` | Danh sách 33 tên miền gốc của Steam, Akamai, Fastly, PUBG, Krafton, BattlEye, Vivox áp dụng vượt chặn DPI |
| `service_remove.cmd` | Gỡ cài đặt dịch vụ, tác vụ tự động, khôi phục DNS/DoH và xóa nút bấm ngoài Desktop |
| `x86_64/` & `x86/` | Bộ thực thi mã nguồn mở `goodbyedpi.exe` (v0.2.3rc3-2 của ValdikSS) và `WinDivert` |

---

## Bảo mật & Quyền riêng tư
Bộ công cụ này không lưu trữ dữ liệu cá nhân, tài khoản hay thông tin định danh máy. Kho lưu trữ chỉ gồm tệp thực thi mã nguồn mở gốc từ [ValdikSS/GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) và các kịch bản Batch/PowerShell.
