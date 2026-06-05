import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../app_storage.dart';
import 'http_client.dart';

/// iGPSPORT 服务
/// 参考 running_page/igpsport_sync.py 和用户逆向的上传API
class IGPService {
  // 新版 API - web 端通过代理避免 CORS
  static const String _baseUrl = kIsWeb
      ? '/proxy/igp/service'
      : 'https://prod.zh.igpsport.com/service';
  static const String _loginUrl = '$_baseUrl/auth/account/login';
  static const String _activityBaseUrl = '$_baseUrl/web-gateway/web-analyze/activity/';
  static const String _activityListUrl = '${_activityBaseUrl}queryMyActivity';
  static const String _downloadUrl = '${_activityBaseUrl}getDownloadUrl/';
  static const String _uploadUrl = '${_activityBaseUrl}uploadByOss';
  static const String _ossSignedUrlUrl = '$_baseUrl/sportg/third-party-server/oss/getSignedUrl';
  static const String _publicKeyUrl = '$_baseUrl/edge-core/api/public/key';

  static const String _platform = 'web';
  static const String _appVersion = '8.07.08';

  // HMAC 签名密钥（WASM 逆向：固定值 "secret-for-web"）
  static const String _hmacKey = 'secret-for-web';

  // x-access-key（从 /edge-core/api/public/key 获取，默认 AKIDWebClient）
  String _accessKey = 'AKIDWebClient';
  bool _keysFetched = false;

  String? _token;
  set token(String value) {
    _token = value;
  }

  bool get isLoggedIn => _token != null;

  /// 测试网络连接
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final response = await AppHttpClient.get(
        Uri.parse('https://prod.zh.igpsport.com'),
        timeout: const Duration(seconds: 10),
      );
      return {
        'success': true,
        'statusCode': response.statusCode,
        'message': '连接成功',
      };
    } catch (e) {
      return {
        'success': false,
        'message': '连接失败: $e',
      };
    }
  }

  /// 从服务器获取 accessKey（用于 x-access-key header）
  Future<void> _fetchAccessKey() async {
    if (_keysFetched) return;
    try {
      final response = await AppHttpClient.get(
        Uri.parse(_publicKeyUrl),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0 && data['data'] != null) {
          final d = data['data'] as Map<String, dynamic>;
          _accessKey = (d['accessKey'] as String?) ?? _accessKey;
          _keysFetched = true;
        }
      }
    } catch (_) {
      // 获取失败则继续使用默认 AKIDWebClient
    }
  }

  /// 生成签名（WASM 逆向算法）
  /// sign_str = method\npath\ntimestamp\nnonce\nsha256hex(body)
  /// signature = base64(HMAC-SHA256(key="secret-for-web", sign_str))
  String _generateSignature(String method, String path, String timestamp, String nonce, String body) {
    final bodyHash = sha256.convert(utf8.encode(body)).toString();
    final signStr = '$method\n$path\n$timestamp\n$nonce\n$bodyHash';
    final hmacSha256 = Hmac(sha256, utf8.encode(_hmacKey));
    final digest = hmacSha256.convert(utf8.encode(signStr));
    return base64Encode(digest.bytes);
  }

  /// 生成带签名的请求 Headers
  /// [method] HTTP 方法 (GET/POST)
  /// [url] 完整请求 URL
  /// [body] 请求体（GET 请求传空字符串）
  Map<String, String> _generateHeaders(String method, String url, {String body = ''}) {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = const Uuid().v4();
    final uri = Uri.parse(url);
    // path 含 query string，如 /service/.../getSignedUrl?fileExtension=.fit
    final path = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    final signature = _generateSignature(method, path, timestamp, nonce, body);

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-Hans',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',
      'timezone': 'Asia/Shanghai',
      'qiwu-app-version': _appVersion,
      'x-access-key': _accessKey,
      'x-nonce': nonce,
      'x-platform': _platform,
      'x-signature': signature,
      'x-timestamp': timestamp,
      'origin': 'https://app.zh.igpsport.com',
      'referer': 'https://app.zh.igpsport.com/',
    };
  }

  /// 登录到 iGPSPORT
  Future<Map<String, dynamic>> login(String account, String password) async {
    try {
      final response = await AppHttpClient.post(
        Uri.parse(_loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'appId': 'igpsport-web',
          'username': account,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        dynamic responseData = data;
        if (data is Map && data.containsKey('data')) {
          responseData = data['data'];
        }
        if (responseData is Map && responseData['access_token'] != null) {
          _token = responseData['access_token'];
          // 预获取 accessKey
          _fetchAccessKey();
          return {
            'success': true,
            'token': _token,
            'nickname': responseData['nickname']?.toString(),
          };
        } else {
          return {
            'success': false,
            'message': 'Invalid response format: $data',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'HTTP Error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 获取活动列表
  Future<List<Map<String, dynamic>>> getActivities(DateTime? lastSyncDate) async {
    if (_token == null) throw Exception('Not logged in');

    var lastFormattedDate = "";
    if (lastSyncDate != null) {
      lastFormattedDate = lastSyncDate.toIso8601String().split("T").first;
    }

    List<Map<String, dynamic>> activities = [];
    bool hasMore = true;
    int page = 1;

    Map<String, dynamic> queryParameters = {
      'pageNo': '1',
      'pageSize': '20',
      'sort': '1',
      'reqType': '0', // 0=fit
    };

    if (lastFormattedDate.isNotEmpty) {
      queryParameters['beginTime'] = lastFormattedDate;
    }

    while (hasMore) {
      queryParameters["pageNo"] = page.toString();

      final uri = Uri.parse(_activityListUrl).replace(queryParameters: queryParameters);
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_token!}',
        'origin': 'https://app.zh.igpsport.com',
        'referer': 'https://app.zh.igpsport.com/',
      };

      final response = await AppHttpClient.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('data')) {
          final rawData = data['data'];
          if (rawData == null) break;
          final list = (rawData['rows'] as List?) ?? [];
          activities.addAll(list.map((e) => e as Map<String, dynamic>));
          hasMore = rawData['totalPage'] > rawData['pageNo'];
          if (hasMore) page++;
        }
      } else {
        throw Exception('Failed to get activities: ${response.statusCode}');
      }
    }

    // 获取每个活动的下载URL
    for (var activity in activities) {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_token!}',
        'origin': 'https://app.zh.igpsport.com',
        'referer': 'https://app.zh.igpsport.com/',
      };

      final response = await AppHttpClient.get(
        Uri.parse(_downloadUrl + activity['rideId'].toString()),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('data')) {
          final durl = (data['data'] as String?) ?? '';
          if (durl.isNotEmpty) {
            activity['downloadUrl'] = durl;
            if (activity['title'] != null) {
              activity['fileName'] = activity['title'].isNotEmpty
                  ? '${activity['startTime']}${activity['title']}.fit'
                  : durl.split("/").last;
            }
          }
        }
      }
    }

    return activities;
  }

  /// 下载FIT文件
  Future<Uint8List> downloadFit(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to download file: ${response.statusCode}');
    }
  }

  /// 上传FIT文件到iGPSPORT
  /// 流程（逆向自网页版 app.zh.igpsport.com）：
  ///   1. GET getSignedUrl?fileExtension=.fit → 获取 OSS 预签名 URL + ossName
  ///   2. PUT 文件到 OSS (igp-zh.oss-cn-hangzhou.aliyuncs.com)
  ///   3. POST uploadByOss {fileName, ossName} → 通知服务端注册上传
  Future<String> uploadFit(Uint8List fitBytes, String fileName) async {
    if (_token == null) throw Exception('Not logged in');

    try {
      // 确保已获取 accessKey
      await _fetchAccessKey();

      // ── Step 1: 获取 OSS 预签名 URL ──
      final signedUrl = '$_ossSignedUrlUrl?fileExtension=.fit';
      final signedHeaders = _generateHeaders('GET', signedUrl);
      signedHeaders['Authorization'] = 'Bearer $_token';

      final signedResp = await AppHttpClient.get(
        Uri.parse(signedUrl),
        headers: signedHeaders,
      );

      if (signedResp.statusCode != 200) {
        throw Exception(
          'getSignedUrl failed: ${signedResp.statusCode} ${signedResp.body}',
        );
      }

      final signedData = jsonDecode(signedResp.body);
      if (signedData['code'] != 0) {
        throw Exception(
          signedData['message'] ?? 'getSignedUrl failed: ${signedResp.body}',
        );
      }

      final data = signedData['data'];
      if (data == null) {
        throw Exception('getSignedUrl response missing data: ${signedResp.body}');
      }

      // 解析 OSS 预签名 URL
      // 实际响应: {signedUrl, ossId}
      final ossUrl = (data['signedUrl'] as String?) ?? (data['url'] as String?);
      final ossName = (data['ossId'] as String?) ??
          (data['key'] as String?) ??
          (data['ossName'] as String?) ??
          '${const Uuid().v4().replaceAll('-', '')}.fit';

      if (ossUrl == null) {
        throw Exception('getSignedUrl response missing OSS URL: ${signedResp.body}');
      }

      // ── Step 2: PUT 文件到 OSS ──
      final putResponse = await http.put(
        Uri.parse(ossUrl),
        body: fitBytes,
      );

      if (putResponse.statusCode != 200) {
        throw Exception(
          'OSS upload failed: ${putResponse.statusCode} ${putResponse.body}',
        );
      }

      // ── Step 3: 通知 iGPSPORT 注册上传 ──
      final registerBody = jsonEncode({
        'fileName': fileName,
        'ossName': ossName,
      });

      final registerHeaders = _generateHeaders('POST', _uploadUrl, body: registerBody);
      registerHeaders['Authorization'] = 'Bearer $_token';

      final registerResp = await AppHttpClient.post(
        Uri.parse(_uploadUrl),
        headers: registerHeaders,
        body: registerBody,
      );

      if (registerResp.statusCode == 200) {
        final regData = jsonDecode(registerResp.body);
        if (regData['code'] == 0) {
          return 'Upload successful: $ossName';
        }
        throw Exception(regData['message'] ?? 'uploadByOss registration failed');
      } else {
        throw Exception(
          'uploadByOss failed: ${registerResp.statusCode} ${registerResp.body}',
        );
      }
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
  }

  /// 解析JWT token获取过期时间
  int? getTokenExp() {
    if (_token == null) return null;
    try {
      final parts = _token!.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
        return payload['exp'] as int?;
      }
    } catch (e) {
      // 解析失败
    }
    return null;
  }
}
