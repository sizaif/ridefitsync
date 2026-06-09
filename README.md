# RideFitSync

自动从运动平台获取 FIT 文件并同步到多个目标平台。

> 🚴 作者：长安四季骑行俱乐部 #小悟空 | GitHub: [sizaif/ridefitsync](https://github.com/sizaif/ridefitsync)

## 正式版 (2026-08)

首个稳定正式版本，重大更新：

- 🏛️ **长安四季骑行俱乐部介绍页** — 设置页「长安四季#小悟空」入口，可查看俱乐部介绍、加入方式
- 🔐 **Strava 登录两步流程** — 先保存 API 凭证，再授权；失败不再静默，明确提示错误
- 🔗 **Deep link 去重** — 修复 Strava 回调重复触发导致 token 交换失败的问题
- ⏱️ **Strava token 请求超时** — 20s 超时 + 明确网络/VPN 错误提示
- 🚫 **佳明平台标灰** — 标记"即将上线"，暂不可操作
- 🎨 **捐赠页 GitHub 链接** — 欢迎 Star ⭐ & Fork 🍴
- 📋 **俱乐部介绍页全选复制** — 微信号等重点突出可复制

## 支持平台

| 平台 | 数据源 | 上传目标 | 认证方式 | 状态 |
|------|:------:|:----:|----------|:----:|
| 顽鹿 OTM | ✓ | ✓ | 密码 / 验证码 (WebView + 滑块) | ✅ |
| iGPSPORT | ✓ | ✓ | 密码 / 验证码 + HMAC-SHA256 | ✅ |
| 行者 | ✓ | ✓ | 密码 (RSA) / 验证码 | ✅ |
| Strava | | ✓ | OAuth 2.0（两步：凭证→授权） | ✅ |
| 捷安特 RideLife | | ✓ | 表单登录 + user_token | ✅ |
| EdgeRide | | ✓ | 验证码 | ✅ |
| 佳明 Connect | ✓ | ✓ | SSO + DI Token | 🚧 即将上线 |

## 快速开始

### 环境要求

- Flutter SDK >= 3.11.0
- Java 17
- Android SDK (用于 APK 构建)

### 本地开发

```bash
flutter pub get
flutter run
```

### 构建发布

```bash
flutter build apk --release
```

APK 输出：`build/app/outputs/flutter-apk/app-release.apk`

## 发版流程

使用 git tag 管理版本号，一条命令完成：

```bash
./scripts/tag_release.sh 1.1.7    # → pubspec.yaml 自动同步 → git tag v1.1.7
git push origin main
git push origin v1.1.7             # → GitHub Actions 自动构建 + 发布 APK
```

设置页显示的版本号从 `pubspec.yaml` 动态读取（`package_info_plus`），无需手动同步。

## 项目结构

```
.
├── scripts/
│   ├── sync_version.sh            # CI 用 — 从 tag 同步版本号
│   └── tag_release.sh             # 本地用 — 打 tag + 同步版本
├── .github/workflows/
│   └── release.yml                # 自动构建 APK + GitHub Release
lib/
├── main.dart
├── sync_hub.dart                  # 同步中心
├── sync_record_manager.dart       # 同步记录（去重）
├── app_storage.dart               # 持久化存储
├── coord_fixer.dart               # GCJ-02 → WGS-84 坐标纠偏
├── upgrader.dart                  # 版本检查 + 应用内更新
├── log_manager.dart               # 日志
├── utils.dart                     # 工具函数
├── l10n/                          # 国际化
│   └── strings.dart
├── services/                      # 各平台 API
│   ├── onelap_service.dart
│   ├── igp_service.dart
│   ├── xingzhe_service.dart
│   ├── garmin_service.dart
│   ├── strava_service.dart
│   ├── giant_service.dart
│   └── edge_ride_service.dart
├── managers/                      # 状态管理
│   ├── onelap_manager.dart
│   ├── igp_manager.dart
│   ├── xingzhe_manager.dart
│   ├── garmin_manager.dart
│   ├── strava_manager.dart
│   ├── giant_manager.dart
│   └── edge_ride_manager.dart
├── pages/                         # UI 页面
│   ├── home_page.dart
│   ├── settings_page.dart
│   ├── sync_settings_page.dart
│   ├── shared_file_page.dart
│   ├── donate_page.dart
│   ├── club_intro_page.dart       # 长安四季骑行俱乐部
│   ├── sync_records_page.dart     # 同步记录管理
│   └── login_pages/
│       ├── login_template.dart
│       ├── onelap_login.dart
│       ├── onelap_webview_login.dart   # 顽鹿验证码登录 (WebView)
│       ├── igp_login.dart
│       ├── xingzhe_login.dart
│       ├── garmin_login.dart
│       ├── strava_login.dart           # OAuth（两步流程）
│       ├── giant_login.dart
│       └── edge_ride_login.dart
└── theme/                         # Material 3 主题
```

## API 参考

### 顽鹿 OTM

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/login` | POST | 密码登录 (MD5 签名) |
| `/api/smscode` | POST | 发送验证码 |
| `/api/smslogin` | POST | 验证码登录 (需先通过阿里滑块) |
| `/api/otm/ride_record/list` | POST | 活动列表 |
| `/api/otm/ride_record/analysis/fit_content/<base64>` | GET | FIT 下载 |

- 签名：`MD5(account=&nonce=&password=MD5(pwd)&timestamp=&key=fe9f8382...)`
- 验证码登录通过 WebView 加载网页完成阿里云滑块验证，拦截 cookie/token
- 认证：JWT `Authorization: <token>` 或 Cookie `onelap_web_session`

### iGPSPORT

| 端点 | 方法 | 说明 |
|------|------|------|
| `/service/auth/account/login` | POST | 密码登录 |
| `/service/auth/account/login/phone` | POST | 验证码登录 |
| `/edge-core/api/public/key` | GET | 获取 access key |

- 签名：`HMAC-SHA256(key="secret-for-web", "METHOD\nPATH\ntimestamp\nnonce\nsha256(body)")`
- 认证：`Authorization: Bearer <jwt>` + 自定义签名头

### 行者

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/v1/user/login/` | POST | 密码登录 (RSA 加密) |
| `/api/v1/mobile/send_sms/` | POST | 发送验证码 |
| `/api/v1/user/mobile/login/` | POST | 验证码登录 |
| `/api/v1/pgworkout/` | GET | 活动列表 |
| `/api/v1/fit/upload/` | POST | FIT 上传 (multipart) |

- 密码登录：RSA PKCS1 v1.5 加密
- 认证：`Cookie: sessionid=<value>` (从 set-cookie 响应头提取)

### Strava

| 端点 | 方法 | 说明 |
|------|------|------|
| `/oauth/authorize` | GET | 授权 |
| `/oauth/token` | POST | Token 交换 (20s timeout) |
| `/api/v3/uploads` | POST | FIT 上传 |

- 认证：OAuth 2.0 (Authorization Code + PKCE)
- 登录流程：① 保存 Client ID/Secret → ② App 授权 / 网页授权

### 捷安特 RideLife

| 端点 | 方法 | 说明 |
|------|------|------|
| `/index.php/api/login` | POST | 表单登录 |
| `/index.php/api/upload_fit` | POST | FIT 上传 |

- 认证：`user_token` + `user_id`

### 佳明 Connect（中国）🚧

| 端点 | 方法 | 说明 |
|------|------|------|
| `/sso/mobile/api/login` | POST | SSO 登录 |
| `/di-oauth2-service/oauth/token` | POST | Token 交换 |
| `connectapi.garmin.cn` | - | 活动列表 / 下载 / 上传 |

> 佳明平台尚未完成开发，设置页已标灰禁用

### EdgeRide

| 端点 | 方法 | 说明 |
|------|------|------|
| `/edge/user/login/webSendRegSMS` | POST | 发送验证码 |
| `/edge/user/login/loginByVerifyCodeByWeb` | POST | 验证码登录 |
| `/edge/user/bind/webUploadFit` | POST | FIT 上传 |



## 数据与隐私

- 本应用不会向作者服务器上传、收集或存储用户数据。
- Strava、顽鹿、iGPSPORT、行者等账号凭证仅保存在设备本地（`flutter_secure_storage`）。
- 活动数据只会在你主动点击上传或同步时发送到目标平台。
- 请妥善保管自己的 API 配置和账号信息。

## 免责声明

- 本项目为个人开源项目，与 Strava、OneLap、iGPSPORT、行者、Garmin 官方均无任何关联。
- 本应用仅供学习和技术研究用途。
- 使用本应用产生的一切后果由用户自行承担，作者不承担任何直接或间接责任。

## 许可证

MIT
