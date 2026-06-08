import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../theme/app_theme.dart';

/// 顽鹿 WebView 登录页面
/// 加载顽鹿网页登录页，用户在 WebView 内完成滑块验证，
/// 拦截登录成功后 /api/smslogin 返回的 token 或 Cookie
class OneLapWebViewLoginPage extends StatefulWidget {
  /// 登录成功回调
  final void Function({
    required String token,
    String? refreshToken,
    String? uid,
    String? nickname,
  })
  onLoginSuccess;

  const OneLapWebViewLoginPage({super.key, required this.onLoginSuccess});

  @override
  State<OneLapWebViewLoginPage> createState() => _OneLapWebViewLoginPageState();
}

class _OneLapWebViewLoginPageState extends State<OneLapWebViewLoginPage> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  double _progress = 0;
  bool _extracted = false; // token 已成功提取，防止重复处理
  bool _redirectChecked = false; // URL 跳转检测已触发过，防止重复调用提取逻辑

  // 顽鹿 OTM 登录页 URL
  static const _loginUrl =
      'https://www.onelap.cn/login.html?url=aHR0cHM6Ly9vdG0ub25lbGFwLmNu&token=1&type=otm&logout=1';

  @override
  void dispose() {
    // 清理可能残留的 JS handler
    _controller?.removeJavaScriptHandler(handlerName: 'onTokenCaptured');
    super.dispose();
  }

  /// 注入 JS 拦截 fetch 请求，捕获 /api/smslogin 的响应
  Future<void> _injectInterceptor(InAppWebViewController controller) async {
    await controller.evaluateJavascript(
      source: """
(function() {
  // 避免重复注入
  if (window.__onelapInterceptorInjected) return;
  window.__onelapInterceptorInjected = true;

  // 劫持 fetch
  const originalFetch = window.fetch;
  window.fetch = function(...args) {
    const url = typeof args[0] === 'string' ? args[0] : args[0].url;
    return originalFetch.apply(this, args).then(async response => {
      // 拦截 /api/smslogin 响应
      if (url && url.includes('/api/smslogin') || url && url.includes('/api/login')) {
        try {
          const clone = response.clone();
          const text = await clone.text();
          // 通过 message handler 回传原生层
          window.flutter_inappwebview.callHandler('onTokenCaptured', JSON.stringify({
            url: url,
            status: response.status,
            body: text,
            headers: JSON.parse(JSON.stringify(Object.fromEntries(response.headers.entries()))),
          }));
        } catch(e) {
          console.log('onelap interceptor error:', e);
        }
      }
      return response;
    });
  };
})();
""",
    );
  }

  /// 检查 URL 跳转 — 登录成功后会重定向到 otm.onelap.cn
  void _checkRedirect(Uri? url) {
    if (url == null || _extracted || _redirectChecked) return;
    final urlStr = url.toString();

    // 登录成功后跳转到 otm.onelap.cn
    if (urlStr.contains('otm.onelap.cn') && !urlStr.contains('login')) {
      _redirectChecked = true;
      _extractTokenFromWebView();
    }

    // 也检查 URL 参数里是否携带 token
    if (urlStr.contains('token=') && !urlStr.contains('token=1')) {
      final uri = Uri.parse(urlStr);
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        _extracted = true;
        widget.onLoginSuccess(token: token);
        if (mounted) Navigator.pop(context, true);
      }
    }
  }

  /// 登录成功后，从 WebView 中提取认证信息
  Future<void> _extractTokenFromWebView() async {
    if (_controller == null) return;

    try {
      // 方式1: 通过 CookieManager 读取 httponly cookie
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(
        url: WebUri('https://www.onelap.cn'),
      );

      String? sessionCookie;
      for (final cookie in cookies) {
        if (cookie.name == 'onelap_web_session') {
          sessionCookie = cookie.value;
          break;
        }
      }

      // 方式2: 注入 JS 读取页面上可能存在的 auth 数据
      String? jsResult;
      try {
        jsResult = await _controller!.evaluateJavascript(
          source: """
          (function() {
            // 尝试从 localStorage 读取
            const ls = localStorage.getItem('onelap_token') ||
                       localStorage.getItem('token') ||
                       localStorage.getItem('auth');
            if (ls) return ls;

            // 尝试从 sessionStorage 读取
            const ss = sessionStorage.getItem('onelap_token') ||
                       sessionStorage.getItem('token');
            if (ss) return ss;

            // 尝试从页面全局变量读取
            if (window.__onelapAuth) {
              return JSON.stringify(window.__onelapAuth);
            }

            return '';
          })();
        """,
        );
      } catch (_) {
        // JS 注入可能失败，忽略
      }

      // 解析获取到的 token
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        _extracted = true;
        // 使用 session cookie 作为认证 token
        widget.onLoginSuccess(token: sessionCookie, uid: '');
        if (mounted) Navigator.pop(context, true);
        return;
      }

      if (jsResult != null && jsResult.isNotEmpty && jsResult != '""') {
        try {
          final data = jsonDecode(jsResult);
          final token = data is Map
              ? (data['token'] ?? data['access_token'])
              : jsResult;
          _extracted = true;
          widget.onLoginSuccess(
            token: token.toString(),
            refreshToken: data is Map
                ? data['refresh_token']?.toString()
                : null,
            uid: data is Map ? data['uid']?.toString() : null,
            nickname: data is Map ? data['nickname']?.toString() : null,
          );
          if (mounted) Navigator.pop(context, true);
          return;
        } catch (_) {
          _extracted = true;
          // 纯 token 字符串
          widget.onLoginSuccess(token: jsResult);
          if (mounted) Navigator.pop(context, true);
          return;
        }
      }

      // 方式3: 没找到 token，提示用户手动确认
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '检测到登录成功跳转，但未能自动获取 token。'
              '请尝试在网页中完成登录后查看。',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取凭证失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('顽鹿验证码登录'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
        actions: [
          TextButton(
            onPressed: _extracted ? null : () => _extractTokenFromWebView(),
            child: const Text('获取凭证', style: TextStyle()),
          ),
        ],
        bottom: _progress < 1.0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              useWideViewPort: true,
              supportZoom: true,
              builtInZoomControls: true,
              displayZoomControls: false,
              // 伪装成普通浏览器 UA（避免被检测）
              userAgent:
                  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              // 允许所有 Cookie
              thirdPartyCookiesEnabled: true,
              // 允许文件访问
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              // 注册 JS → Flutter 消息通道，拦截 /api/smslogin 响应
              controller.addJavaScriptHandler(
                handlerName: 'onTokenCaptured',
                callback: (args) {
                  if (_extracted) return;

                  try {
                    final data =
                        jsonDecode(args.first.toString())
                            as Map<String, dynamic>;
                    final bodyStr = data['body'] as String? ?? '';
                    if (bodyStr.isEmpty) return;

                    final responseData = jsonDecode(bodyStr);

                    // 解析 token（格式与现有 /api/login 一致）
                    dynamic inner = responseData;
                    if (responseData is Map &&
                        responseData.containsKey('data')) {
                      inner = responseData['data'];
                    }
                    if (inner is List && inner.isNotEmpty) {
                      final authData = inner[0];
                      _extracted = true;
                      widget.onLoginSuccess(
                        token: authData['token']?.toString() ?? '',
                        refreshToken: authData['refresh_token']?.toString(),
                        uid: authData['userinfo']?['uid']?.toString(),
                        nickname: authData['userinfo']?['nickname']?.toString(),
                      );
                      if (mounted) Navigator.pop(context, true);
                      return;
                    }
                    // 兜底：直接是 token 字段
                    if (responseData is Map &&
                        responseData.containsKey('token')) {
                      _extracted = true;
                      widget.onLoginSuccess(
                        token: responseData['token'].toString(),
                      );
                      if (mounted) Navigator.pop(context, true);
                      return;
                    }
                  } catch (e) {
                    debugPrint('解析 token 失败: $e, args: $args');
                  }

                  // 解析失败，降级到 Cookie 提取（不在此处标记 extracted，
                  // 让 _extractTokenFromWebView 的 Cookie 路径再试一次）
                  _extractTokenFromWebView();
                },
              );
            },
            onLoadStart: (controller, url) {
              _checkRedirect(url);
            },
            onLoadStop: (controller, url) async {
              if (mounted) {
                setState(() => _isLoading = false);
              }
              _checkRedirect(url);
              // 每次页面加载完重新注入（防止 SP 单页导航导致注入丢失）
              await _injectInterceptor(controller);
            },
            onProgressChanged: (controller, progress) {
              setState(() => _progress = progress / 100.0);
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url?.toString() ?? '';

              // 阻止跳转到非 onelap 的外部链接
              if (url.isNotEmpty &&
                  !url.contains('onelap.cn') &&
                  !url.contains('onelap.com') &&
                  !url.contains('aliyuncs.com') && // 滑块验证码 CDN
                  !url.startsWith('data:') &&
                  !url.startsWith('javascript:')) {
                return NavigationActionPolicy.CANCEL;
              }

              _checkRedirect(navigationAction.request.url);
              return NavigationActionPolicy.ALLOW;
            },
            onReceivedError: (controller, request, error) {
              debugPrint('WebView error: ${error.description}');
            },
          ),

          // 加载指示
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.onelapColor),
            ),
        ],
      ),
    );
  }
}
