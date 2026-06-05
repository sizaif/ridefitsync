# AutoFit2Strava

自动从运动平台获取 FIT 文件并同步到多个目标平台。

## 支持平台

| 平台 | 数据源 | 上传目标 | 认证方式 |
|------|:------:|:----:|----------|
| 顽鹿 OTM | ✓ |  ✓   | MD5 签名 |
| iGPSPORT | ✓ |  ✓   | JWT + HMAC-SHA256 |
| 行者 | ✓ |  ✓   | RSA 加密 + session |
| 佳明 Connect | ✓ |  ✓   | SSO + DI Token |
| Strava | |  ✓   | OAuth 2.0 |
| 捷安特 RideLife | |  ✓   | 表单登录 + user_token |
| EdgeRide | |  ✓   | 短信验证码 |

## 构建

```bash
flutter pub get
flutter build apk --release
```

APK 输出：`build/app/outputs/flutter-apk/app-release.apk`

## 项目结构

```
lib/
├── main.dart
├── sync_hub.dart              # 同步中心
├── app_storage.dart           # 持久化存储
├── coord_fixer.dart           # GCJ-02 → WGS-84 坐标纠偏
├── log_manager.dart           # 日志
├── utils.dart                 # 工具函数
├── l10n/                      # 国际化
│   └── strings.dart
├── services/                  # 各平台 API
│   ├── onelap_service.dart
│   ├── igp_service.dart
│   ├── xingzhe_service.dart
│   ├── garmin_service.dart
│   ├── strava_service.dart
│   ├── giant_service.dart
│   ├── edge_ride_service.dart
│   └── notification_service.dart
├── managers/                  # 状态管理
│   ├── onelap_manager.dart
│   ├── igp_manager.dart
│   ├── xingzhe_manager.dart
│   ├── garmin_manager.dart
│   ├── strava_manager.dart
│   ├── giant_manager.dart
│   └── edge_ride_manager.dart
├── pages/                     # UI 页面
│   ├── home_page.dart
│   ├── settings_page.dart
│   ├── sync_settings_page.dart
│   ├── donate_page.dart
│   └── login_pages/
└── theme/                     # Material 3 主题
```

## API 参考

### 顽鹿 OTM
- 登录：`POST https://www.onelap.cn/api/login`（MD5 签名，key: `fe9f8382418fcdeb136461cac6acae7b`）
- 活动列表：`POST https://otm.onelap.cn/api/otm/ride_record/list`
- FIT 下载：`GET https://otm.onelap.cn/api/otm/ride_record/analysis/fit_content/<base64(fileKey)>`

### iGPSPORT
- 签名：`HMAC-SHA256(key="secret-for-web", sign_str)`
- 登录：`POST https://prod.zh.igpsport.com/service/auth/account/login`
- 活动列表：`GET .../queryMyActivity`
- 上传：OSS 预签名 URL 三步上传

### 行者
- 登录：`POST https://www.imxingzhe.com/api/v1/user/login/`（RSA PKCS1 v1.5）
- 活动列表：`GET https://www.imxingzhe.com/api/v1/pgworkout/`
- 上传：`POST https://www.imxingzhe.com/api/v1/fit/upload/`

### Strava
- 授权：`GET https://www.strava.com/oauth/authorize`
- 上传：`POST https://www.strava.com/api/v3/uploads`

### 捷安特 RideLife
- 登录：`POST https://ridelife.giant.com.cn/index.php/api/login`
- 上传：`POST https://ridelife.giant.com.cn/index.php/api/upload_fit`

### 佳明 Connect（中国）
- SSO 登录：`POST https://sso.garmin.cn/mobile/api/login`
- Token 交换：`POST https://diauth.garmin.cn/di-oauth2-service/oauth/token`
- 活动列表 + 下载 + 上传：`connectapi.garmin.cn`

### EdgeRide
- 验证码：`POST https://www.edge-sports.cn/edge/user/login/webSendRegSMS`
- 登录：`POST https://www.edge-sports.cn/edge/user/login/loginByVerifyCodeByWeb`
- 上传：`POST https://www.edge-sports.cn/edge/user/bind/webUploadFit`

## 数据与隐私
- 本应用不会向作者服务器上传、收集或存储用户数据。 
- Strava、顽鹿、iGPSPORT、Keep 等账号凭证仅保存在设备本地。 
- 活动数据只会在你主动点击上传或同步时发送到 Strava。 
- 请妥善保管自己的 API 配置和账号信息。

## 免责声明 
- 本项目为个人开源项目，与 Strava、OneLap、iGPSPORT、Keep、Garmin 官方均无任何关联。 
- 使用本应用产生的一切后果由用户自行承担，作者不承担任何直接或间接责任。

## 许可证

MIT
