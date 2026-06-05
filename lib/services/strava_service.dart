import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../app_storage.dart';

class StravaService {
  static const String _authUrl = 'https://www.strava.com/oauth/authorize';
  static const String _tokenUrl = 'https://www.strava.com/oauth/token';
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

  Uri getAuthorizationUrl() {
    if (!hasCredentials) {
      throw Exception('Client ID/Secret not configured');
    }
    return Uri.parse(
      '$_authUrl?client_id=$clientId&response_type=code&redirect_uri=$_redirectUri&approval_prompt=force&scope=activity:write',
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
    final response = await http.post(
      Uri.parse(_tokenUrl),
      body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveTokens(data);
      return true;
    } else {
      throw Exception('Token exchange failed: ${response.body}');
    }
  }

  Future<void> refreshTokenIfNeeded() async {
    if (accessToken == null || expiresAt == null) return;

    final refreshThreshold = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;
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
    await _storage.write(key: 'strava_expires_at', value: expiresAt!.toString());
  }

  Future<bool> saveCredentials(String clientId, String clientSecret) async {
    final bool credentialsChanged = (this.clientId != clientId || this.clientSecret != clientSecret);
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

  Future<void> logout() async {
    await _storage.delete(key: 'strava_access_token');
    await _storage.delete(key: 'strava_refresh_token');
    await _storage.delete(key: 'strava_expires_at');
    accessToken = null;
    refreshToken = null;
    expiresAt = null;
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
  Future<String> uploadFitFile(Uint8List fitBytes, String fileName, {String? sportType}) async {
    if (!isAuthenticated) throw Exception('Not authenticated');
    await refreshTokenIfNeeded();

    // gzip压缩
    final compressedBytes = GZipEncoder().encode(fitBytes) as List<int>;

    var request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
    request.headers['Authorization'] = 'Bearer $accessToken';

    // 确保文件名有.gz后缀
    final baseName = fileName.endsWith('.fit') ? fileName : '$fileName.fit';
    request.files.add(
      http.MultipartFile.fromBytes('file', compressedBytes, filename: '$baseName.gz'),
    );

    request.fields['data_type'] = 'fit.gz';
    if (sportType != null && sportType != 'Default') {
      request.fields['sport_type'] = sportType;
    }

    try {
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return 'Upload successful! Upload ID: ${data['id']}';
      } else {
        // Strava可能返回409表示重复活动
        final data = jsonDecode(response.body);
        if (data['error'] != null) {
          throw Exception('Upload failed: ${data['error']}');
        } else if (data['message'] != null) {
          throw Exception('Upload failed: ${data['message']}');
        }
        throw Exception('Upload failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception("Upload failed: $e");
    }
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
