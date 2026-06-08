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
  bool get isLoggedIn =>
      _sid != null && _sid!.isNotEmpty && _uid != null && _uid!.isNotEmpty;

  String? get sid => _sid;
  String? get uid => _uid;

  static const Map<String, String> _baseHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'Origin': 'https://www.edge-sports.cn',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  /// 恢复登录会话
  void restoreSession(String? sid, String? uid) {
    _sid = sid?.trim();
    _uid = uid?.trim();
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

      // EdgeRide 验证码接口：成功时 body 为空，响应头 ret: 0
      if (response.statusCode == 200) {
        final retHeader = response.headers['ret'];
        if (retHeader == '0') return {'success': true};

        // 有 body 时解析 msg 检查
        if (response.body.isNotEmpty) {
          try {
            final data = jsonDecode(response.body);
            final msg = data['msg'] ?? data['message'] ?? '';
            if (msg.toString().contains('失败') ||
                msg.toString().contains('错误')) {
              return {'success': false, 'message': msg};
            }
            return {'success': true};
          } catch (_) {}
        }
        return {'success': true}; // HTTP 200 且没有明确错误 → 成功
      }
      return {
        'success': false,
        'message': 'HTTP Error: ${response.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 验证码登录
  Future<Map<String, dynamic>> login(String phone, String verifyCode) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_loginUrl))
        ..headers.addAll({
          ..._baseHeaders,
          'Referer': 'https://www.edge-sports.cn/',
        })
        ..fields['phone'] = phone
        ..fields['areaCode'] = '+86'
        ..fields['verifyCode'] = verifyCode;

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.body.isEmpty) {
        return {'success': false, 'message': '服务器返回空响应'};
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final cookieSession = _parseCycleCookie(
            response.headers['set-cookie'],
          );
          final sid =
              _stringValue(data, ['sid', 'sessionId', 'session_id']) ??
              cookieSession['sid'];
          final uid =
              _stringValue(data, ['uid', 'userId', 'user_id', 'id']) ??
              cookieSession['uid'];
          if (sid != null && uid != null) {
            _sid = sid;
            _uid = uid;
            return {'success': true, 'sid': _sid, 'uid': _uid};
          }
          if (sid != null) {
            return {'success': false, 'message': '登录成功但未返回 uid，请重新登录'};
          }
          return {'success': false, 'message': data['msg'] ?? '登录失败'};
        }
        if (data is Map && data['sid'] != null) {
          final cookieSession = _parseCycleCookie(
            response.headers['set-cookie'],
          );
          _sid = data['sid']?.toString() ?? cookieSession['sid'];
          _uid = data['uid']?.toString() ?? cookieSession['uid'];
          return {'success': true, 'sid': _sid, 'uid': _uid};
        }
        return {'success': false, 'message': '登录响应格式异常'};
      }
      return {
        'success': false,
        'message': 'HTTP Error: ${response.statusCode}',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// 上传FIT文件
  Future<String> uploadFit(Uint8List fitBytes, String fileName) async {
    if (!isLoggedIn) throw Exception('未登录或缺少 uid，请重新登录 EdgeRide');

    final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
      ..headers.addAll({
        ..._baseHeaders,
        'Referer': 'https://www.edge-sports.cn/fit',
        'Cookie': 'sid=$_sid',
      })
      ..fields['uid'] = _uid!.trim()
      ..files.add(
        http.MultipartFile.fromBytes(
          'uploadFileList',
          fitBytes,
          filename: fileName,
          contentType: MediaType('application', 'octet-stream'),
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('登录已过期，请重新登录');
    }

    if (response.body.isEmpty) {
      if (response.statusCode == 200) {
        final ret = response.headers['ret'];
        if (ret == null || ret == '0' || ret == '100') {
          return 'Upload successful';
        }
      }
      throw Exception('上传失败: 服务器返回空响应 (HTTP ${response.statusCode})');
    }

    final data = _decodeJson(response.body);
    if (data is! Map) {
      if (response.statusCode == 200) return 'Upload successful';
      throw Exception('上传失败 (HTTP ${response.statusCode}): ${response.body}');
    }

    final code = data['code']?.toString();
    final msg = (data['msg'] ?? data['message'] ?? data['data'] ?? '')
        .toString();
    final success =
        code == '0' ||
        code == '100' ||
        code == '200' ||
        data['success'] == true ||
        data['status'] == 1 ||
        data['status'] == '1';

    if (response.statusCode == 200 && success) {
      return 'Upload successful';
    }
    if (msg.contains('已上传') || msg.contains('重复')) {
      return '文件已上传';
    }
    if (msg.contains('登录') || msg.toLowerCase().contains('session')) {
      throw Exception('登录已过期，请重新登录');
    }

    throw Exception(
      msg.isNotEmpty
          ? '上传失败 (HTTP ${response.statusCode}, code=$code): $msg'
          : '上传失败 (HTTP ${response.statusCode}, code=$code)',
    );
  }

  dynamic _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String? _stringValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    for (final value in data.values) {
      if (value is Map<String, dynamic>) {
        final found = _stringValue(value, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  Map<String, String> _parseCycleCookie(String? setCookie) {
    final result = <String, String>{};
    if (setCookie == null || setCookie.isEmpty) return result;
    final match = RegExp(r'cyclecookie=([^;]+)').firstMatch(setCookie);
    if (match == null) return result;

    final decoded = Uri.decodeComponent(match.group(1)!);
    for (final part in decoded.split('&')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final key = part.substring(0, index);
      final value = part.substring(index + 1).trim();
      if (value.isNotEmpty) result[key] = value;
    }
    return result;
  }
}
