import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// 佳明 Connect 中国服务
class GarminService {
  static const String _iosClientId = 'GCM_IOS_DARK';
  static const String _diGrantType =
      'https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket';
  static const List<String> _diClientIds = [
    'GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2',
    'GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4',
    'GARMIN_CONNECT_MOBILE_ANDROID_DI',
  ];

  final http.Client _client = http.Client();

  String? _token;
  String? _refreshToken;
  String? _diClientId;
  String? _tokenExp;

  String get _domain => 'garmin.cn';
  String get _ssoBaseUrl => 'https://sso.$_domain';
  String get _diTokenUrl => 'https://diauth.$_domain/di-oauth2-service/oauth/token';
  String get _connectApiBaseUrl => 'https://connectapi.$_domain';
  String get _iosServiceUrl => 'https://mobile.integration.$_domain/gcm/ios';

  set token(String value) => _token = value;
  set refreshToken(String? value) => _refreshToken = value;
  set diClientId(String? value) => _diClientId = value;
  set tokenExp(String? value) => _tokenExp = value;

  String? get token => _token;
  String? get refreshToken => _refreshToken;
  String? get diClientId => _diClientId;
  String? get tokenExp => _tokenExp;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  Map<String, String> get _authHeaders {
    if (_token == null) throw Exception('Not logged in');
    return {
      ..._nativeHeaders(),
      'Authorization': 'Bearer $_token',
      'Accept': 'application/json',
    };
  }

  /// 登录佳明中国
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final ticket = await _requestServiceTicket(email, password);
      final tokenData = await _exchangeServiceTicket(ticket);
      return _completeLogin(tokenData);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 刷新token
  Future<Map<String, dynamic>> refresh() async {
    if (_refreshToken == null || _diClientId == null) {
      return {'success': false, 'message': 'No refresh token'};
    }
    try {
      final response = await _client
          .post(
            Uri.parse(_diTokenUrl),
            headers: _nativeHeaders({
              'Authorization': 'Basic ${base64Encode(utf8.encode('$_diClientId:'))}',
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
              'Cache-Control': 'no-cache',
            }),
            body: {
              'grant_type': 'refresh_token',
              'client_id': _diClientId!,
              'refresh_token': _refreshToken!,
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {'success': false, 'message': 'Refresh failed: ${response.statusCode}'};
      }

      final data = _decodeJson(response.body);
      return _completeLogin(data);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Map<String, dynamic> _completeLogin(Map<String, dynamic> tokenData) {
    _token = tokenData['access_token'] as String?;
    _refreshToken = tokenData['refresh_token'] as String?;
    _diClientId = _extractClientIdFromJwt(_token) ?? tokenData['client_id'] as String?;

    if (_token == null || _token!.isEmpty) {
      return {'success': false, 'message': 'Invalid token response'};
    }

    return {
      'success': true,
      'token': _token,
      'refreshToken': _refreshToken,
      'clientId': _diClientId,
    };
  }

  /// 获取用户名
  Future<String> getUsername() async {
    final profile = await _getJson('$_connectApiBaseUrl/userprofile-service/userprofile/userProfileBase');
    final email = profile['emailAddress']?.toString();
    final displayName = profile['displayName']?.toString();
    return (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (email ?? '');
  }

  /// 获取活动列表
  Future<List<Map<String, dynamic>>> getActivities(String sportType, DateTime? lastSyncDate) async {
    int start = 0;
    final List<Map<String, dynamic>> allActivities = [];
    final params = {
      'start': start.toString(),
      'limit': '20',
      'activityType': sportType,
      if (lastSyncDate != null)
        'startDate': lastSyncDate.toIso8601String().split('T').first,
    };

    while (true) {
      final uri = Uri.parse(
        '$_connectApiBaseUrl/activitylist-service/activities/search/activities',
      ).replace(queryParameters: params);

      final response = await _client
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 401) {
        throw Exception('佳明认证失败或token过期');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('获取活动失败: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded == null || decoded is! List) break;

      for (final item in decoded) {
        allActivities.add({
          'id': item['activityId'].toString(),
          'title': item['activityName']?.toString() ?? '',
          'startTime': item['startTimeGMT']?.toString() ?? '',
        });
      }

      if (decoded.length < 20) break;
      start += 20;
      params['start'] = start.toString();
    }
    return allActivities;
  }

  /// 下载活动FIT文件
  Future<Uint8List> downloadFit(String activityId) async {
    final uri = Uri.parse(
      '$_connectApiBaseUrl/download-service/files/activity/$activityId',
    );
    final response = await _client
        .get(uri, headers: {..._authHeaders, 'Accept': '*/*'})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      throw Exception('佳明认证失败或token过期');
    }
    if (response.statusCode == 404) {
      throw Exception('活动文件不存在: $activityId');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('下载失败: ${response.statusCode}');
    }

    return response.bodyBytes;
  }

  /// 上传FIT文件到佳明
  Future<String> uploadFit(Uint8List fitBytes, String fileName) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_connectApiBaseUrl/upload-service/upload'),
    );
    request.headers.addAll(_authHeaders);
    request.files.add(http.MultipartFile.fromBytes('file', fitBytes, filename: fileName));

    final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('佳明上传失败: ${response.statusCode}');
    }
    return '上传成功';
  }

  // --- 内部方法 ---

  Future<String> _requestServiceTicket(String email, String password) async {
    final uri = Uri.parse('$_ssoBaseUrl/mobile/api/login').replace(
      queryParameters: {
        'clientId': _iosClientId,
        'locale': 'zh-CN',
        'service': _iosServiceUrl,
      },
    );

    final response = await _client
        .post(
          uri,
          headers: {
            'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
                'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json',
            'Origin': _ssoBaseUrl,
          },
          body: jsonEncode({
            'username': email,
            'password': password,
            'rememberMe': true,
            'captchaToken': '',
          }),
        )
        .timeout(const Duration(seconds: 30));

    final data = _decodeJson(response.body);
    final responseType = data['responseStatus'] is Map
        ? data['responseStatus']['type'] as String?
        : null;

    switch (responseType) {
      case 'SUCCESSFUL':
        final ticket = data['serviceTicketId'] as String?;
        if (ticket == null || ticket.isEmpty) {
          throw Exception('登录成功但未获取到ticket');
        }
        return ticket;
      case 'INVALID_USERNAME_PASSWORD':
        throw Exception('佳明账号或密码错误');
      case 'MFA_REQUIRED':
        throw Exception('佳明账号需要二次验证，暂不支持');
      default:
        throw Exception('佳明登录失败: $data');
    }
  }

  Future<Map<String, dynamic>> _exchangeServiceTicket(String ticket) async {
    Map<String, dynamic>? lastError;

    for (final clientId in _diClientIds) {
      final response = await _client
          .post(
            Uri.parse(_diTokenUrl),
            headers: _nativeHeaders({
              'Authorization': 'Basic ${base64Encode(utf8.encode('$clientId:'))}',
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
              'Cache-Control': 'no-cache',
            }),
            body: {
              'client_id': clientId,
              'service_ticket': ticket,
              'grant_type': _diGrantType,
              'service_url': _iosServiceUrl,
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        lastError = {'client_id': clientId, 'statusCode': response.statusCode};
        continue;
      }

      final data = _decodeJson(response.body);
      if (data['access_token'] is String) {
        data['client_id'] = clientId;
        return data;
      }
      lastError = {'client_id': clientId, 'body': data};
    }

    throw Exception('佳明token交换失败: $lastError');
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: _authHeaders)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      throw Exception('佳明认证失败');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    return _decodeJson(response.body);
  }

  Map<String, dynamic> _decodeJson(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('无效的JSON响应');
  }

  Map<String, String> _nativeHeaders([Map<String, String>? extra]) {
    return {
      'User-Agent': 'GCM-Android-5.23',
      'X-Garmin-User-Agent': 'com.garmin.android.apps.connectmobile/5.23; Android/33',
      'X-Garmin-Paired-App-Version': '10861',
      'X-Garmin-Client-Platform': 'Android',
      'X-App-Ver': '10861',
      'X-Lang': 'zh',
      'X-GCExperience': 'GC5',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      ...?extra,
    };
  }

  String? _extractClientIdFromJwt(String? token) {
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (payload is Map && payload['client_id'] != null) {
        return payload['client_id'].toString();
      }
    } catch (_) {}
    return null;
  }
}
