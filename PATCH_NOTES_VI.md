# phoneME iOS 0.3.4 build 6 — ghi chú bản vá

## Chức năng đã thêm

### 1. Tiếp tục chạy khi khóa màn hình hoặc ẩn ứng dụng

- Giữ tiến trình iOS hoạt động bằng phiên âm thanh nền gần như im lặng.
- Khi ứng dụng ở nền, phoneME dừng việc lấy và hiển thị khung hình để giảm tải.
- Luồng Java, `Timer`, `Thread.sleep`, socket, UDP và MMAPI của game vẫn tiếp tục chạy.
- Tùy chọn **Run in Background** được bật mặc định cho cài đặt mới và vẫn có thể tắt trong Settings.
- Không còn yêu cầu quyền vị trí nền.

Lưu ý: iOS vẫn có thể chấm dứt tiến trình khi người dùng vuốt tắt ứng dụng, thiết bị thiếu bộ nhớ, quá nhiệt hoặc hệ thống cần thu hồi tài nguyên. Đây không phải cơ chế tự khởi chạy lại sau khi tiến trình đã bị chấm dứt.

### 2. IP/port riêng cho từng game

Trong màn hình chỉnh cấu hình của game, mở mục **Network** rồi bật **Use custom game server**.

- Nhập IP hoặc hostname.
- Nhập port từ 1 đến 65535.
- Các kết nối TCP `SocketConnection` và UDP `DatagramConnection` mới của riêng game đó được chuyển sang endpoint đã nhập.
- `ServerSocketConnection`, HTTP và HTTPS không bị thay đổi.
- Thay đổi endpoint khi game đang chạy sẽ khởi động lại riêng game đó để đóng các socket cũ.

## Build IPA unsigned trên macOS

Yêu cầu Xcode và iOS SDK:

```bash
bash Scripts/build-unsigned-ipa.sh --clean
```

Kết quả mặc định:

```text
Artifacts/phoneME-0.3.4-build6-fixed-unsigned.ipa
```

IPA này chưa được ký. Có thể ký bằng chứng chỉ Apple của bạn hoặc cài qua quy trình sideload/TrollStore phù hợp. Bộ giữ nền âm thanh gần như im lặng được thiết kế cho bản sideload/private; cách dùng này có nguy cơ không đạt App Review vì background mode phải phục vụ đúng mục đích. Script TrollStore có sẵn trong source:

```bash
bash Scripts/build-trollstore-tipa.sh --clean
```

## Kiểm thử đã thực hiện trong môi trường hiện tại

- Build toàn bộ thư viện C++ `phoneMECore`: đạt.
- Test TCP/UDP endpoint override, server socket, HTTP và dọn handle: đạt.
- Biên dịch public C API ở chế độ C11: đạt.
- Kiểm tra cú pháp các tệp Swift đã sửa: đạt.
- Kiểm tra `Info-iOS.plist` và bản dịch EN/VI: đạt.

Việc build ứng dụng iOS cuối cùng cần `xcodebuild` và iPhoneOS SDK trên macOS.
