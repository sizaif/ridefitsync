import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'http_client.dart';


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

  set token(String value) {
    _token = value;
  }

  /// 是否使用 Cookie 认证（而非 Authorization 头）
  set useCookieAuth(bool value) {
    _useCookieAuth = value;
  }

  bool get isLoggedIn => _token != null;

  /// 构建认证请求头，支持 JWT token 和 Cookie 两种模式
  Map<String, String> _authHeaders() {
    if (_token == null) return {};
    if (_useCookieAuth) {
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

  /// 获取活动列表
  /// 参考 running_page/onelap_sync.py 的活动列表获取
  Future<List<Map<String, dynamic>>> getActivities(DateTime? lastSyncDate) async {
    if (_token == null) throw Exception('Not logged in');

    var lastFormattedDate = "";
    if (lastSyncDate != null) {
      lastFormattedDate = lastSyncDate.toIso8601String().split("T").first;
    }

    // 方式1：使用 otm.onelap.cn API（参考 ref/strava_auto2）
    List<Map<String, dynamic>> activities = [];
    bool hasMore = true;
    int page = 1;

    while (hasMore) {
      final response = await AppHttpClient.post(
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
        throw Exception('Failed to get activities: ${response.statusCode}');
      }
    }

    // 获取每个活动的 fileKey
    for (var activity in activities) {
      final response = await AppHttpClient.get(
        Uri.parse(_activityListDetailUrl + activity['id'].toString()),
        headers: _authHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('data')) {
          final detail = data['data']["ridingRecord"];
          if (detail != null && detail['fileKey'] != null) {
            activity['fileKey'] = detail['fileKey'];
          }
        }
      }
    }

    return activities;
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
    return null;
  }
}
