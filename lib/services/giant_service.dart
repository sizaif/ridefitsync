import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// 捷安特 RideLife (ridelife.giant.com.cn) 服务
/// 基于用户逆向的登录和上传API，无签名机制
class GiantService {
  static const String _baseUrl = 'https://ridelife.giant.com.cn/index.php/api';
  static const String _loginUrl = '$_baseUrl/login';
  static const String _uploadUrl = '$_baseUrl/upload_fit';

  String? _token;
  set token(String value) => _token = value;

  bool get isLoggedIn => _token != null;

  static const Map<String, String> _baseHeaders = {
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'origin': 'https://ridelife.giant.com.cn',
    'x-requested-with': 'XMLHttpRequest',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  /// 登录到捷安特 RideLife
  /// Content-Type: application/x-www-form-urlencoded
  /// 响应: {"status":1, "user_token":"...", "user":{...}}
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse(_loginUrl),
        headers: {
          ..._baseHeaders,
          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'referer': 'https://ridelife.giant.com.cn/web/login.html',
        },
        body: 'username=$username&password=$password',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['user_token'] as String?;
        if (token != null && data['status'] == 1) {
          _token = token;
          final nickname = data['user'] is Map ? data['user']['nickname']?.toString() : null;
          return {'success': true, 'token': token, 'nickname': nickname};
        }
        return {'success': false, 'message': data['message'] ?? '登录失败: ${response.body}'};
      }
      return {'success': false, 'message': 'HTTP Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 上传FIT文件到捷安特 RideLife
  /// multipart/form-data: token, device=trailer, brand=giant, files[]
  Future<String> uploadFit(Uint8List fitBytes, String fileName) async {
    if (_token == null) throw Exception('Not logged in');

    final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
      ..headers.addAll({
        ..._baseHeaders,
        'referer': 'https://ridelife.giant.com.cn/web/main_fit.html',
      })
      ..fields['token'] = _token!
      ..fields['device'] = 'trainer'
      ..fields['brand'] = 'giant'
      ..files.add(http.MultipartFile.fromBytes(
        'files[]',
        fitBytes,
        filename: fileName,
        contentType: MediaType('application', 'octet-stream'),
      ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // status 可能是 String "1" 或 int 1
      final statusOk = data['status'] == '1' || data['status'] == 1;
      if (statusOk || data['code'] == 0 || data['code'] == '0') {
        return 'Upload successful';
      }
      throw Exception((data['msg'] ?? data['message']) ?? 'Upload failed: ${response.body}');
    }
    throw Exception('HTTP Error: ${response.statusCode} ${response.body}');
  }
}
