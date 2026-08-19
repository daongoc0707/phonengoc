# Báo cáo bản vá phoneME iOS 0.3.4 build 6

Ngày kiểm tra: 2026-08-19

## Đầu vào đã kiểm tra

- IPA gốc: `phoneME-unsigned.ipa`
- Source gốc: `phoneME-iOS-0.3.4-build5.zip`
- Bundle ID của IPA gốc: `dev.phoneme.emulator`
- Phiên bản IPA gốc: `0.3.4` build `5`
- Kiến trúc IPA gốc: arm64
- Minimum iOS của IPA gốc: iOS 15.0
- IPA gốc đã khai báo background mode `audio` và `location`.

Bản source đã vá giữ marketing version `0.3.4` và tăng build number lên `6`.

## Nội dung đã sửa

### Chạy khi khóa màn hình hoặc ẩn ứng dụng

- Thay bộ giữ nền bằng Core Location của build 5 bằng một `AVAudioEngine` chạy vòng lặp âm thanh gần như im lặng.
- Chỉ bật bộ giữ nền khi có ít nhất một ứng dụng J2ME đang chạy.
- Khi app iOS vào nền, dừng polling/render phía giao diện nhưng không dừng VM, luồng Java, timer, socket hay MMAPI của game.
- Bảo vệ phiên `AVAudioSession` dùng chung để thao tác reset/suspend MMAPI không vô tình tắt bộ giữ nền.
- Tự khởi động lại bộ giữ nền sau audio interruption, route change hoặc media services reset.
- Bỏ background mode `location` và toàn bộ chuỗi xin quyền vị trí.
- Tùy chọn **Run in Background** bật mặc định cho cài đặt mới; lựa chọn đã lưu của người dùng vẫn được giữ nguyên.

### IP/port riêng cho từng game

- Thêm ba trường tùy chọn vào `GameProfile`, tương thích JSON build 5:
  - bật/tắt override;
  - IP/hostname;
  - port.
- Thêm mục **Network** trong màn hình chỉnh cấu hình riêng của game.
- Chuyển hướng các kết nối TCP `SocketConnection` và UDP `DatagramConnection` đi ra của đúng MIDlet đó.
- Không sửa listener/server socket, HTTP hoặc HTTPS.
- Endpoint của mỗi game được giữ trong `Machine`/`ConnectionRegistry` riêng, không dùng biến toàn cục.
- Khi đổi endpoint của một game đang chạy, app hủy VM của riêng game đó rồi tạo lại với app ID mới, nhờ đó socket cũ được đóng trước khi route mới có hiệu lực.
- Thêm C API `phoneme_configure_app_network_endpoint` và tăng ABI từ 1.2.0 lên 1.3.0.

## Kiểm thử đã chạy

### Core C++

- Cấu hình và build toàn bộ target `phoneMECore` bằng CMake/Ninja trên Linux: **ĐẠT**.
- Archive tạo được: `/mnt/data/phoneME-build-linux/libphoneMECore.a`.
- Symbol public mới có trong archive:

```text
T phoneme_configure_app_network_endpoint
```

- Test endpoint biên dịch với C++23 và các cờ nghiêm ngặt:

```text
-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow
```

Kết quả: **ĐẠT**.

Các trường hợp đã kiểm tra:

- TCP của game A đổi sang host/port cấu hình;
- UDP của game A đổi sang host/port cấu hình;
- game B vẫn dùng endpoint gốc, không bị ảnh hưởng bởi game A;
- server socket vẫn bind port do game yêu cầu;
- HTTP giữ nguyên URL đích;
- host sai và port 0 bị từ chối;
- tắt override khôi phục endpoint do game cung cấp;
- tất cả native handle được đóng sau test.

- Public C header/ABI test ở chế độ C11: **ĐẠT**.
- `CoreTests.cpp` kiểm tra cú pháp đầy đủ: **ĐẠT**; chỉ có các cảnh báo initializer đã tồn tại từ source gốc.
- `git diff --check`: **ĐẠT**.

### Swift và tài nguyên iOS

- `swiftc -parse` cho toàn bộ tệp Swift đã sửa: **ĐẠT**.
- Test thực thi riêng cho `GameProfile`: **ĐẠT**.

Các trường hợp đã kiểm tra:

- chuẩn hóa `socket://[IPv6]` thành host IPv6;
- từ chối host có khoảng trắng;
- từ chối port lớn hơn 65535 thay vì tự ép giá trị;
- tắt override trả về endpoint rỗng;
- JSON mô phỏng build 5 không có ba khóa mạng mới vẫn giải mã được.

- `plutil -lint` cho `Info-iOS.plist`, EN strings và VI strings: **ĐẠT**.
- Không có khóa localization trùng lặp.
- `bash -n` cho script build IPA và các script test/verify đã sửa: **ĐẠT**.

## Môi trường kiểm thử

```text
Linux x86_64
Swift 6.2.1
CMake 3.31.6
Ninja 1.12.1
GCC/G++ 14.2.0
```

## Giới hạn build IPA trong môi trường này

Môi trường hiện tại là Linux và không có `xcodebuild`, `xcrun`, Xcode hoặc iPhoneOS SDK. Lần chạy script build iOS dừng ngay với:

```text
Required command not found: xcodebuild
```

Vì vậy chưa có binary iPhone mới để đóng gói thành IPA thật. Không thể sửa chức năng chỉ bằng cách thay file trong IPA gốc, vì các thay đổi nằm trong Swift, Objective-C và thư viện C++ phải được biên dịch/link lại bằng Apple toolchain.

Source có script build unsigned một lệnh trên macOS:

```bash
bash Scripts/build-unsigned-ipa.sh --clean
```

Kết quả mặc định:

```text
Artifacts/phoneME-0.3.4-build6-fixed-unsigned.ipa
```

## Lưu ý khi sử dụng

- iOS vẫn có quyền chấm dứt tiến trình khi người dùng vuốt tắt app, thiết bị thiếu bộ nhớ, quá nhiệt hoặc hệ thống thu hồi tài nguyên. Bản vá không thể tự hồi sinh một tiến trình đã bị terminate.
- Bộ giữ nền âm thanh gần như im lặng là giải pháp dành cho sideload/private build. Việc dùng background audio chỉ để giữ một emulator chạy có nguy cơ không đạt App Review vì background mode phải được dùng đúng mục đích.
- Cần kiểm thử IPA build 6 trên thiết bị thật, đặc biệt qua các tình huống khóa màn hình, chuyển app, cuộc gọi/audio interruption, Wi-Fi sang cellular và chạy nhiều game đồng thời.
