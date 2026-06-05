import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asn1/primitives/asn1_bit_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import '../app_storage.dart';

/// 行者 (imxingzhe.com) 服务
/// 参考 IGPSPORT2XingZhe/ActivitySync.py 和用户逆向的登录API
class XingzheService {
  static const String _baseUrl = 'https://www.imxingzhe.com/api/v1';
  static const String _loginUrl = '$_baseUrl/user/login/';
  static const String _uploadUrl = '$_baseUrl/fit/upload/';
  static const String _activityListUrl = '$_baseUrl/pgworkout/';

  // 行者 RSA 公钥（用于密码加密）
  // 来自 IGPSPORT2XingZhe/ActivitySync.py
  static const String _rsaPublicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDmuQkBbijudDAJgfffDeeIButq
WHZvUwcRuvWdg89393FSdz3IJUHc0rgI/S3WuU8N0VePJLmVAZtCOK4qe4FY/eKm
WpJmn7JfXB4HTMWjPVoyRZmSYjW4L8GrWmh51Qj7DwpTADadF3aq04o+s1b8LXJa
8r6+TIqqL5WUHtRqmQIDAQAB
-----END PUBLIC KEY-----''';

  String? _sessionId;
  set token(String value) {
    _sessionId = value;
  }

  bool get isLoggedIn => _sessionId != null;

  /// RSA 加密密码
  /// 使用 pointycastle 实现 RSA PKCS1 v1.5 加密
  String _encryptPassword(String password) {
    try {
      // 解析 PEM 格式的公钥
      final publicKeyStr = _rsaPublicKeyPem
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll('\n', '')
          .trim();

      final publicKeyBytes = base64.decode(publicKeyStr);

      // 使用 pointycastle 解析 DER 格式的公钥
      final asn1Parser = ASN1Parser(publicKeyBytes);
      final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
      final publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;

      final asn1Parser2 = ASN1Parser(Uint8List.fromList(publicKeyBitString.stringValues!));
      final publicKeySeq = asn1Parser2.nextObject() as ASN1Sequence;

      final modulus = (publicKeySeq.elements![0] as ASN1Integer).integer;
      final exponent = (publicKeySeq.elements![1] as ASN1Integer).integer;

      // 创建 RSA 公钥
      final rsaPublicKey = RSAPublicKey(modulus!, exponent!);

      // 使用 PKCS1 v1.5 加密
      final cipher = PKCS1Encoding(RSAEngine());
      cipher.init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));

      final inputBytes = utf8.encode(password);
      final encrypted = cipher.process(Uint8List.fromList(inputBytes));

      return base64.encode(encrypted);
    } catch (e) {
      // 如果 RSA 加密失败，打印错误并返回降级方案
      print('RSA encryption failed: $e');
      return base64Encode(utf8.encode(password));
    }
  }

  /// 登录到行者平台
  /// API: POST https://www.imxingzhe.com/api/v1/user/login/
  /// 响应: {code: 0, msg: "", data: {userid: 7569099, username: "xxx", enuid: "xxx"}}
  /// Cookie: sessionid=xxx
  Future<Map<String, dynamic>> login(String account, String password) async {
    try {
      // 密码需要 RSA 加密
      final encryptedPassword = _encryptPassword(password);

      final response = await http.post(
        Uri.parse(_loginUrl),
        headers: {
          'Content-Type': 'application/json;charset=UTF-8',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Origin': 'https://www.imxingzhe.com',
          'Referer': 'https://www.imxingzhe.com/login',
        },
        body: jsonEncode({
          'account': account,
          'password': encryptedPassword,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 检查登录是否成功
        if (data is Map && data['code'] == 0) {
          final userData = data['data'];
          if (userData != null && userData is Map) {
            // 从 set-cookie 中获取 sessionid
            final cookies = response.headers['set-cookie'];
            if (cookies != null) {
              final sessionMatch = RegExp(r'sessionid=([^;]+)').firstMatch(cookies);
              if (sessionMatch != null) {
                _sessionId = sessionMatch.group(1);
                return {
                  'success': true,
                  'token': _sessionId,
                  'userid': userData['userid'],
                  'username': userData['username'],
                  'enuid': userData['enuid'],
                };
              }
            }

            // 如果没有 cookie，使用 enuid 作为标识
            _sessionId = userData['enuid'];
            return {
              'success': true,
              'token': _sessionId,
              'userid': userData['userid'],
              'username': userData['username'],
            };
          }
        }

        return {
          'success': false,
          'message': data['msg'] ?? '登录失败',
        };
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
  Future<List<Map<String, dynamic>>> getActivities({int offset = 0, int limit = 10}) async {
    if (_sessionId == null) throw Exception('Not logged in');

    try {
      final response = await http.get(
        Uri.parse('$_activityListUrl?offset=$offset&limit=$limit&sport=3'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'sessionid=$_sessionId',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('data')) {
          final resultData = data['data'];
          if (resultData is Map && resultData.containsKey('data')) {
            return List<Map<String, dynamic>>.from(resultData['data']);
          }
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 上传FIT文件到行者平台
  /// API: POST https://www.imxingzhe.com/api/v1/fit/upload/
  /// Content-Type: multipart/form-data
  Future<String> uploadFit(Uint8List fitBytes, String fileName) async {
    if (_sessionId == null) throw Exception('Not logged in');

    try {
      // 计算文件 MD5
      final md5Hash = md5.convert(fitBytes).toString();

      // 构建 multipart 请求
      var request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));

      // 设置 Headers（携带 sessionid cookie）
      request.headers['Cookie'] = 'sessionid=$_sessionId';

      // 添加文件字段（参考 IGPSPORT2XingZhe/ActivitySync.py）
      request.files.add(http.MultipartFile.fromBytes(
        'fit_file',
        fitBytes,
        filename: fileName,
      ));

      // 添加其他字段
      request.fields['file_source'] = 'undefined';
      request.fields['fit_filename'] = fileName;
      request.fields['md5'] = md5Hash;
      request.fields['name'] = 'AutoFit2Strava-${DateTime.now().toIso8601String()}';
      request.fields['sport'] = '3'; // 3=骑行

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        // 检查业务状态码
        if (data is Map) {
          final code = data['code'];
          if (code != null && code != 0) {
            final msg = data['msg']?.toString() ?? '未知错误';
            throw Exception(_friendlyError(msg));
          }
        }
        return 'Upload successful: ${data.toString()}';
      } else {
        throw Exception('上传失败 (HTTP ${response.statusCode})');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 将服务端错误信息转为人性化提示
  String _friendlyError(String msg) {
    if (msg.contains('已上传过') || msg.contains('已上传') || msg.contains('已经上传')) {
      return '文件已上传过';
    }
    if (msg.contains('登录') || msg.contains('session') || msg.contains('未登录')) {
      return '登录已过期，请重新登录';
    }
    if (msg.contains('格式') || msg.contains('不支持') || msg.contains('文件类型')) {
      return '文件格式不支持';
    }
    return msg;
  }

  /// 获取用户信息
  Future<Map<String, dynamic>?> getUserInfo() async {
    if (_sessionId == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/info/'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'sessionid=$_sessionId',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // 忽略错误
    }
    return null;
  }
}
