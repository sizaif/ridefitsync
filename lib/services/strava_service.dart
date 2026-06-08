import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../app_storage.dart';

class StravaService {
  static const String _mobileAuthUrl =
      'https://www.strava.com/oauth/mobile/authorize';
  static const String _webAuthUrl = 'https://www.strava.com/oauth/authorize';
  static const String _tokenUrl = 'https://www.strava.com/oauth/token';
  static const String _deauthorizeUrl =
      'https://www.strava.com/oauth/deauthorize';
  static const String _uploadUrl = 'https://www.strava.com/api/v3/uploads';
  static const String _athleteUrl = 'https://www.strava.com/api/v3/athlete';
  static const String _redirectUri = 'stravaauto://localhost';

  final _storage = AppStorage();

  String? clientId;
  String? clientSecret;
  String? accessToken;
  String? refreshToken;
  int? expiresAt;

  Future<void> init() async {
    clientId = await _storage.read(key: 'strava_client_id');
    clientSecret = await _storage.read(key: 'strava_client_secret');
    accessToken = await _storage.read(key: 'strava_access_token');
    refreshToken = await _storage.read(key: 'strava_refresh_token');
    expiresAt = int.parse(await _storage.read(key: 'strava_expires_at') ?? '0');
  }

  bool get isAuthenticated {
    if (accessToken == null || expiresAt == null) return false;
    return true;
  }

  bool get hasCredentials => clientId != null && clientSecret != null;

  Uri getAuthorizationUrl({bool mobile = true}) {
    if (!hasCredentials) {
      throw Exception('Client ID/Secret not configured');
    }
    return Uri.parse(mobile ? _mobileAuthUrl : _webAuthUrl).replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'approval_prompt': 'force',
        'scope': 'read,activity:read_all,activity:write',
      },
    );
  }

  Future<bool> handleAuthCallback(Uri uri) async {
    if (uri.queryParameters.containsKey('error')) {
      throw Exception('Auth error: ${uri.queryParameters['error']}');
    }
    if (uri.queryParameters.containsKey('code')) {
      final code = uri.queryParameters['code'];
      return await _exchangeToken(code!);
    }
    return false;
  }

  Future<bool> _exchangeToken(String code) async {
    late final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_tokenUrl),
            body: {
              'client_id': clientId,
              'client_secret': clientSecret,
              'code': code,
              'grant_type': 'authorization_code',
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw Exception('Strava token请求失败，请检查网络/VPN/代理: $e');
    }

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        await _saveTokens(data);
        return true;
      } catch (e) {
        throw Exception('Strava token响应解析失败: $e');
      }
    } else {
      throw Exception(
        'Strava token交换失败 HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<void> refreshTokenIfNeeded() async {
    if (accessToken == null || expiresAt == null) return;

    final refreshThreshold =
        DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/
        1000;
    if (refreshThreshold > expiresAt!) {
      await _refreshToken();
    }
  }

  Future<void> _refreshToken() async {
    if (refreshToken == null) throw Exception('No refresh token');
    final response = await http.post(
      Uri.parse(_tokenUrl),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveTokens(data);
    } else {
      throw Exception('Failed to refresh token');
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    accessToken = data['access_token'];
    refreshToken = data['refresh_token'];
    expiresAt = data['expires_at'];

    await _storage.write(key: 'strava_access_token', value: accessToken!);
    await _storage.write(key: 'strava_refresh_token', value: refreshToken!);
    await _storage.write(
      key: 'strava_expires_at',
      value: expiresAt!.toString(),
    );
  }

  Future<bool> saveCredentials(String clientId, String clientSecret) async {
    final bool credentialsChanged =
        (this.clientId != clientId || this.clientSecret != clientSecret);
    if (this.clientId != null && credentialsChanged) {
      await logout();
    }
    this.clientId = clientId == "" ? null : clientId;
    this.clientSecret = clientSecret == "" ? null : clientSecret;
    if (clientId != "") {
      await _storage.write(key: 'strava_client_id', value: clientId);
    } else {
      await _storage.delete(key: 'strava_client_id');
    }
    if (clientSecret != "") {
      await _storage.write(key: 'strava_client_secret', value: clientSecret);
    } else {
      await _storage.delete(key: 'strava_client_secret');
    }
    return credentialsChanged;
  }

  Future<bool> logout({bool deauthorize = true}) async {
    var deauthorized = false;
    if (deauthorize && accessToken != null) {
      try {
        await refreshTokenIfNeeded();
        final token = accessToken;
        if (token != null) {
          final response = await http
              .post(Uri.parse(_deauthorizeUrl), body: {'access_token': token})
              .timeout(const Duration(seconds: 15));
          deauthorized =
              response.statusCode >= 200 && response.statusCode < 300;
        }
      } catch (_) {
        deauthorized = false;
      }
    }

    await _storage.delete(key: 'strava_access_token');
    await _storage.delete(key: 'strava_refresh_token');
    await _storage.delete(key: 'strava_expires_at');
    accessToken = null;
    refreshToken = null;
    expiresAt = null;
    return deauthorized;
  }

  // 获取运动员信息
  Future<Map<String, dynamic>?> getAthlete() async {
    if (!isAuthenticated) return null;
    await refreshTokenIfNeeded();

    final response = await http.get(
      Uri.parse(_athleteUrl),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  // 上传FIT文件到Strava
  Future<String> uploadFitFile(
    Uint8List fitBytes,
    String fileName, {
    String? sportType,
    String? activityName,
    String? description,
    String? externalId,
  }) async {
    if (!isAuthenticated) throw Exception('Not authenticated');
    await refreshTokenIfNeeded();

    // gzip压缩
    final compressedBytes = GZipEncoder().encode(fitBytes) as List<int>;

    var request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
    request.headers['Authorization'] = 'Bearer $accessToken';

    // 确保文件名有.gz后缀
    final baseName = fileName.endsWith('.fit') ? fileName : '$fileName.fit';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        compressedBytes,
        filename: '$baseName.gz',
      ),
    );

    request.fields['data_type'] = 'fit.gz';
    if (sportType != null && sportType != 'Default') {
      request.fields['activity_type'] = sportType;
    }
    if (activityName != null && activityName.isNotEmpty) {
      request.fields['name'] = activityName;
    }
    if (description != null && description.isNotEmpty) {
      request.fields['description'] = description;
    }
    if (externalId != null && externalId.isNotEmpty) {
      request.fields['external_id'] = externalId;
    }

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final uploadId = data['id'];
      final activityId = data['activity_id'];

      // 轮询上传状态（Strava 异步处理，可能需要几秒到几十秒）
      if (uploadId != null && activityId == null) {
        for (int i = 0; i < 24; i++) {
          await Future.delayed(const Duration(seconds: 5));
          if (!isAuthenticated) break;
          try {
            final status = await getUploadStatus(uploadId);
            if (status?['activity_id'] != null) {
              return 'https://www.strava.com/activities/${status!['activity_id']}';
            }
            if (status?['error'] != null) {
              throw Exception(status!['error']);
            }
          } catch (e) {
            if (e.toString().contains('refresh')) rethrow;
          }
        }
        // 超时但上传可能仍在处理中
        return 'Upload submitted (ID: $uploadId), processing...';
      }
      if (activityId != null) {
        return 'https://www.strava.com/activities/$activityId';
      }
      return 'Upload successful (ID: $uploadId)';
    }

    // 错误处理：尝试解析 body 中的错误信息
    String errorMsg;
    try {
      final data = jsonDecode(response.body);
      errorMsg =
          data['error']?.toString() ??
          data['message']?.toString() ??
          'HTTP ${response.statusCode}';
    } catch (_) {
      errorMsg = 'HTTP ${response.statusCode}';
    }
    throw Exception(errorMsg);
  }

  // 查询上传状态
  Future<Map<String, dynamic>?> getUploadStatus(int uploadId) async {
    if (!isAuthenticated) return null;
    await refreshTokenIfNeeded();

    final response = await http.get(
      Uri.parse('https://www.strava.com/api/v3/uploads/$uploadId'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }
}
