/// 对账号进行脱敏处理（中间字符替换为****）
String maskAccount(String account) {
  if (account.length <= 4) return account;
  // 邮箱：只显示首尾字符
  if (account.contains('@')) {
    final parts = account.split('@');
    final name = parts[0];
    if (name.length <= 2) return account;
    return '${name[0]}****${name[name.length - 1]}@${parts[1]}';
  }
  // 手机号：138****8000
  if (account.length == 11 && RegExp(r'^\d+$').hasMatch(account)) {
    return '${account.substring(0, 3)}****${account.substring(7)}';
  }
  // 通用：保留首尾各一部分
  final showLen = (account.length - 4) ~/ 2;
  if (showLen <= 0) return '${account[0]}****';
  return '${account.substring(0, showLen)}****${account.substring(account.length - showLen)}';
}
