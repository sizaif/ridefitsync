import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 通用 HTTP 客户端，自动处理 Web 平台的 CORS 代理
class AppHttpClient {
  // CORS 代理（仅 Web 平台开发环境使用）
  static const String _corsProxy = 'https://corsproxy.io/?';

  /// 获取代理后的 URL（Web 平台自动添加 CORS 代理）
  static String proxyUrl(String url) {
    if (kIsWeb) {
      return '$_corsProxy${Uri.encodeComponent(url)}';
    }
    return url;
  }

  /// GET 请求
  static Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final proxyUri = Uri.parse(proxyUrl(uri.toString()));
    return http.get(proxyUri, headers: headers).timeout(
      timeout ?? const Duration(seconds: 30),
    );
  }

  /// POST 请求
  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final proxyUri = Uri.parse(proxyUrl(uri.toString()));
    return http.post(proxyUri, headers: headers, body: body).timeout(
      timeout ?? const Duration(seconds: 30),
    );
  }
}
