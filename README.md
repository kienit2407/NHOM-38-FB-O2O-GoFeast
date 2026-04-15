# FaB-O2O Super App
# Nhóm 38
## Thành Viên:
- Võ Trung Kiên
- Tống Thị Hồng Liên
- Nguyễn Quang Vinh

Nền tảng O2O gồm 5 ứng dụng chạy cùng một backend:
- `api`: NestJS modular monolith
- `merchant-web`: cổng quản trị cho Merchant
- `admin-web`: cổng quản trị hệ thống
- `customer`: app Flutter cho khách hàng
- `driver`: app Flutter cho tài xế

## 1) Kiến trúc tổng quan

```text
FaB-O2O/
├─ apps/
│  ├─ api/            # NestJS + MongoDB + Redis
│  ├─ merchant-web/   # React + Vite (port 8080)
│  ├─ admin-web/      # React + Vite (port 8088)
│  ├─ customer/       # Flutter app khách hàng
│  └─ driver/         # Flutter app tài xế
└─ README.md
```

### Backend module map (apps/api/src/modules)

`admin`, `ai`, `auth`, `benefits`, `carts`, `customers`, `dinein`, `drivers`, `favorites`, `feed`, `geo`, `merchants`, `notifications`, `orders`, `payments`, `promotions`, `realtime`, `reviews`, `search`, `system-config`, `users`.

### Port mặc định local

| Service | Port |
|---|---|
| API (NestJS) | `4000` |
| Merchant Web (Vite) | `8080` |
| Admin Web (Vite) | `8088` |
| Realtime Socket Namespace | `/realtime` (qua API `:4000`) |

## 2) Tech stack

| Layer | Công nghệ |
|---|---|
| Backend | NestJS 11, TypeScript, Mongoose, Redis cache, Socket.IO |
| Database | MongoDB |
| Web | React 18, Vite 5, TypeScript, TanStack Query, Zustand, Tailwind/shadcn |
| Mobile | Flutter (Riverpod, Dio, Firebase, Socket.IO client) |

## 3) Yêu cầu môi trường

- Node.js `>= 20`
- npm `>= 9`
- Flutter SDK `>= 3.9.2`
- MongoDB `>= 6`
- Redis `>= 6` (backend dùng cache store Redis)

## 4) Cài đặt nhanh

Mỗi app đang quản lý dependency độc lập.

```bash
# API
cd apps/api
npm install

# Merchant Web
cd ../merchant-web
npm install

# Admin Web
cd ../admin-web
npm install

# Customer app
cd ../customer
flutter pub get

# Driver app
cd ../driver
flutter pub get
```

## 5) Chạy hệ thống local

Mở 5 terminal:

```bash
# Terminal 1 - API
cd apps/api
npm run start:dev
```

```bash
# Terminal 2 - Merchant Web
cd apps/merchant-web
npm run dev
```

```bash
# Terminal 3 - Admin Web
cd apps/admin-web
npm run dev
```

```bash
# Terminal 4 - Customer
cd apps/customer
flutter run
```

```bash
# Terminal 5 - Driver
cd apps/driver
flutter run
```

## 6) Biến môi trường

### API (`apps/api/.env`)

Tối thiểu cần:

```env
PORT=4000
NODE_ENV=development
MONGO_URI=mongodb://localhost:27017/fabo2o
JWT_SECRET=change_me
JWT_REFRESH_SECRET=change_me_too
REDIS_HOST=localhost
REDIS_PORT=6379
```

Ngoài ra dự án có tích hợp OAuth, Cloudinary, email, Kafka, cổng thanh toán (VNPAY/MoMo), TrackAsia.

### Merchant Web (`apps/merchant-web/.env`)

```env
VITE_API_URL=http://localhost:4000
VITE_TRACKASIA_STYLE_URL=<your-trackasia-style-url>
```

### Admin Web

Không bắt buộc `.env`, mặc định fallback về `http://localhost:4000` trong mã nguồn.

### Mobile (Customer/Driver)

Hiện đang hardcode base URL trong:
- `apps/customer/lib/core/shared/contants/url_config.dart`
- `apps/driver/lib/core/shared/contants/url_config.dart`

Mặc định: `http://localhost:4000`.

## 7) Scripts chính

### API (`apps/api/package.json`)

- `npm run start:dev`: chạy dev mode (watch)
- `npm run build`: build production
- `npm run start:prod`: chạy bản build
- `npm run test`: unit test
- `npm run test:e2e`: e2e test

### Merchant Web / Admin Web

- `npm run dev`: chạy local
- `npm run build`: build production
- `npm run test`: chạy test bằng Vitest

### Customer / Driver

- `flutter run`: chạy app
- `flutter test`: chạy test

## 8) Luồng truy cập

- Merchant Web gọi API bằng cookie + access token, có refresh token flow.
- Admin Web có auth guard tương tự, endpoint riêng cho admin.
- Mobile Customer/Driver gọi API qua Dio, có Firebase Messaging và realtime socket.
- Backend mở CORS cho:
  - `http://localhost:8080` (merchant-web)
  - `http://localhost:8088` (admin-web)

## 9) Troubleshooting nhanh

- Mobile chạy emulator Android không truy cập được `localhost`:
  - đổi `backendBaseUrl` sang `http://10.0.2.2:4000`.
- Merchant/Admin báo lỗi CORS hoặc 401:
  - kiểm tra API có chạy `:4000` chưa.
  - kiểm tra `VITE_API_URL` (merchant) hoặc base URL fallback.
- API không kết nối được MongoDB/Redis:
  - kiểm tra service local và giá trị trong `apps/api/.env`.

## 10) Bảo mật

- Không commit secret thật vào repo.
- Ưu tiên tạo `*.env.example` và quản lý bí mật qua secret manager/CI variables.

## License

Private - All rights reserved.
