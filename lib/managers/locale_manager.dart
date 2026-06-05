import 'package:flutter/foundation.dart';
import '../app_storage.dart';
import '../l10n/strings.dart';

/// 本地化语言管理器
class LocaleManager extends ChangeNotifier {
  static final LocaleManager _instance = LocaleManager._internal();
  factory LocaleManager() => _instance;
  LocaleManager._internal();

  final _storage = AppStorage();

  bool _isZh = true;
  bool get isZh => _isZh;

  Future<void> init() async {
    await _storage.init();
    final saved = await _storage.read(key: 'locale');
    _isZh = saved != 'en';
    S.setLocale(_isZh);
  }

  Future<void> setLocale(bool isZh) async {
    if (_isZh == isZh) return;
    _isZh = isZh;
    S.setLocale(isZh);
    await _storage.write(key: 'locale', value: isZh ? 'zh' : 'en');
    notifyListeners();
  }
}
