import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// EdgeRide (edge-sports.cn) 服务
class EdgeRideService {
  static const String _baseUrl = 'https://www.edge-sports.cn/edge';
  static const String _sendSmsUrl = '$_baseUrl/user/login/webSendRegSMS';
  static const String _loginUrl = '$_baseUrl/user/login/loginByVerifyCodeByWeb';
  static const String _uploadUrl = '$_baseUrl/user/bind/webUploadFit';

  String? _sid;
  String? _uid;
  bool get isLoggedIn => _sid != null;

  String? get sid => _sid;
  String? get uid => _uid;

  static const Map<String, String> _baseHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'origin': 'https://www.edge-sports.cn',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  /// 恢复登录会话
  void restoreSession(String? sid, String? uid) {
    _sid = sid;
    _uid = uid;
  }

  /// 发送短信验证码
  Future<Map<String, dynamic>> sendSmsCode(String phone) async {
    try {
      final uri = Uri.parse(_sendSmsUrl);
      final response = await http.post(
        uri,
        headers: {
          ..._baseHeaders,
          'referer': 'https://www.edge-sports.cn/',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'phone': phone, 'areaCode': '+86'},
      );

      if (response.body.isEmpty) {
        return {'success': false, 'message': '服务器返回空响应'};
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code']?.toString() == '100') {
          return {'success': true};
        }
        return {'success': false, 'message': data['msg'] ?? '发送验证码失败'};
      }
      return {'success': false, 'message': 'HTTP Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 验证码登录
  Future<Map<String, dynamic>> login(String phone, String verifyCode) async {
    try {
      final uri = Uri.parse(_loginUrl);
      final response = await http.post(
        uri,
        headers: {
          ..._baseHeaders,
          'referer': 'https://www.edge-sports.cn/',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'phone': phone, 'areaCode': '+86', 'verifyCode': verifyCode},
      );

      if (response.body.isEmpty) {
        return {'success': false, 'message': '服务器返回空响应'};
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['sid'] != null) {
          _sid = data['sid'];
          _uid = data['uid']?.toString();
          return {'success': true, 'sid': _sid, 'uid': _uid};
        }
        return {'success': false, 'message': data['msg'] ?? '登录失败'};
      }
      return {'success': false, 'message': 'HTTP Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 上传FIT文件
  Future<String> uploadFit(Uint8List fitBytes, String fileName) async {
    if (_sid == null || _uid == null) throw Exception('Not logged in');

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
        ..headers.addAll({..._baseHeaders, 'referer': 'https://www.edge-sports.cn/fit'})
        ..fields['uid'] = _uid!
        ..files.add(http.MultipartFile.fromBytes(
          'uploadFileList',
          fitBytes,
          filename: fileName,
          contentType: MediaType('application', 'octet-stream'),
        ));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code']?.toString() == '100') {
          return 'Upload successful';
        }
        throw Exception(data['msg'] ?? '上传失败');
      }
      throw Exception('HTTP Error: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }
}
