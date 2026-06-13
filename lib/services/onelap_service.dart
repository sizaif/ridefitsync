import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'http_client.dart';

class OneLapAuthExpiredException implements Exception {
  final String message;
  OneLapAuthExpiredException([this.message = 'OneLap login expired']);

  @override
  String toString() => message;
}

/// 顽鹿OTM服务
/// 参考 running_page/onelap_sync.py 和 ref/strava_auto2/lib/onelap_service.dart
class OneLapService {
  static const String _loginUrl = 'https://www.onelap.cn/api/login';
  static const String _baseUrl = 'https://otm.onelap.cn';
  static const String _activityListUrl = '$_baseUrl/api/otm/ride_record/list';
  static const String _activityListDetailUrl = '$_baseUrl/api/otm/ride_record/analysis/';
  static const String _otmUrl = '$_baseUrl/api/otm/ride_record/analysis/fit_content/';
  static const String _secretKey = 'fe9f8382418fcdeb136461cac6acae7b';

  // 新增：顽鹿分析接口（来自 running_page）
  static const String _analysisUrl = 'https://u.onelap.cn/analysis/list';

  String? _token;
  String? _uid;
  bool _useCookieAuth = false;

  set token(String? value) {
    _token = value;
  }

  /// 是否使用 Cookie 认证（而非 Authorization 头）
  set useCookieAuth(bool value) {
    _useCookieAuth = value;
  }

  bool get isLoggedIn => _token != null;

  bool _isAuthExpiredStatus(int statusCode) =>
      statusCode == 401 || statusCode == 403;

  void _throwIfAuthExpired(http.Response response, String label) {
    if (_isAuthExpiredStatus(response.statusCode)) {
      _token = null;
      throw OneLapAuthExpiredException(
        '$label auth expired: ${response.statusCode}',
      );
    }
  }

  /// 构建认证请求头
  /// OTM API (otm.onelap.cn) 只接受 Authorization 头，不接受 Cookie
  Map<String, String> _authHeaders({bool otmApi = true}) {
    if (_token == null) return {};
    if (!otmApi && _useCookieAuth) {
      return {'Cookie': 'onelap_web_session=$_token'};
    }
    return {'Authorization': _token!};
  }

  /// 测试网络连接
  Future<Map<String, dynamic>> testConnection() async {
    try {
      final response = await AppHttpClient.get(
        Uri.parse('https://www.onelap.cn'),
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

  /// MD5 加密
  String _md5(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// 登录到顽鹿OTM
  /// 参考 running_page/onelap_sync.py 的登录逻辑
  Future<Map<String, dynamic>> login(String account, String password) async {
    final nonce = const Uuid().v4().replaceAll('-', '').substring(16);
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final passwordMd5 = _md5(password);

    // 签名：MD5(account=...&nonce=...&password=MD5(pwd)&timestamp=...&key=...)
    final signStr = "account=$account&nonce=$nonce&password=$passwordMd5&timestamp=$timestamp&key=$_secretKey";
    final sign = _md5(signStr);

    final headers = {
      'nonce': nonce,
      'timestamp': timestamp,
      'sign': sign,
      'Content-Type': 'application/json',
    };

    final body = jsonEncode({'account': account, 'password': passwordMd5});

    try {
      final response = await AppHttpClient.post(
        Uri.parse(_loginUrl),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        dynamic responseData = data;
        if (data is Map && data.containsKey('data')) {
          responseData = data['data'];
        }

        if (responseData is List && responseData.isNotEmpty) {
          final loginData = responseData[0];
          final token = loginData['token'];
          final refreshToken = loginData['refresh_token'];
          final userinfo = loginData['userinfo'] ?? {};
          _uid = userinfo['uid']?.toString();

          _token = token;
          return {
            'success': true,
            'token': _token,
            'refresh_token': refreshToken,
            'uid': _uid,
            'nickname': userinfo['nickname']?.toString(),
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

  /// 获取活动列表（带重试）
  Future<List<Map<String, dynamic>>> getActivities(DateTime? lastSyncDate) async {
    if (_token == null) throw Exception('Not logged in');

    var lastFormattedDate = "";
    if (lastSyncDate != null) {
      lastFormattedDate = lastSyncDate.toIso8601String().split("T").first;
    }

    // 分页获取活动列表
    List<Map<String, dynamic>> activities = [];
    bool hasMore = true;
    int page = 1;

    while (hasMore) {
      final response = await _retryRequest(
        () => AppHttpClient.post(
          Uri.parse(_activityListUrl),
          headers: {
            ..._authHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            "page": page,
            "limit": 20,
            if (lastFormattedDate.isNotEmpty) "start_date": lastFormattedDate,
          }),
        ),
        '获取活动列表(page=$page)',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('data')) {
          final rawData = data['data'];
          if (rawData == null) break;
          final list = (rawData['list'] as List?) ?? [];
          activities.addAll(list.map((e) => e as Map<String, dynamic>));
          hasMore = rawData['pagination']['has_more'] ?? false;
          if (hasMore) page++;
        }
      } else {
        _throwIfAuthExpired(response, 'get activities');
        throw Exception('Failed to get activities: ${response.statusCode}');
      }
    }

    // 获取每个活动的 fileKey（隔 200ms 防止请求过快）
    for (var activity in activities) {
      try {
        await Future.delayed(const Duration(milliseconds: 200));
        final response = await AppHttpClient.get(
          Uri.parse(_activityListDetailUrl + activity['id'].toString()),
          headers: _authHeaders(),
        );
        _throwIfAuthExpired(response, 'get activity detail');
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map && data.containsKey('data')) {
            final detail = data['data']["ridingRecord"];
            if (detail != null && detail['fileKey'] != null) {
              activity['fileKey'] = detail['fileKey'];
            }
          }
        }
      } catch (e) {
        if (e is OneLapAuthExpiredException) rethrow;
        // 单个活动详情获取失败不影响其他活动
      }
    }

    return activities;
  }

  /// 带重试的请求（5xx 错误重试最多 3 次）
  Future<http.Response> _retryRequest(
    Future<http.Response> Function() request,
    String label,
  ) async {
    const maxRetries = 3;
    for (int i = 0; i < maxRetries; i++) {
      final response = await request();
      if (response.statusCode >= 500 && response.statusCode < 600) {
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(seconds: (i + 1) * 3)); // 3s, 6s 退避
          continue;
        }
      }
      return response;
    }
    throw Exception('$label 请求失败: 服务器错误，已重试 $maxRetries 次');
  }

  /// 下载FIT文件
  /// 参考 ref/strava_auto2/lib/onelap_service.dart
  Future<Uint8List> downloadFit(String fileKey) async {
    if (_token == null) throw Exception('Not logged in');

    final response = await AppHttpClient.get(
      Uri.parse(_otmUrl + base64Encode(utf8.encode(fileKey))),
      headers: _authHeaders(),
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      _throwIfAuthExpired(response, 'download fit');
      throw Exception('Failed to download file: ${response.statusCode}');
    }
  }

  /// 获取活动详情
  Future<Map<String, dynamic>?> getActivityDetail(int activityId) async {
    if (_token == null) throw Exception('Not logged in');

    final response = await AppHttpClient.get(
      Uri.parse('$_activityListDetailUrl$activityId'),
      headers: _authHeaders(),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data.containsKey('data')) {
        return data['data'] as Map<String, dynamic>;
      }
    }
    _throwIfAuthExpired(response, 'get activity detail');
    return null;
  }
}
