/// 简单的国际化字符串管理
/// 使用方式: S.current.settings
class S {
  final bool _isZh;

  const S._(this._isZh);

  static S current = const S._(true);

  static void setLocale(bool isZh) {
    current = S._(isZh);
  }

  // ===== 通用 =====
  String get settings => _isZh ? '设置' : 'Settings';
  String get confirm => _isZh ? '确认' : 'Confirm';
  String get cancel => _isZh ? '取消' : 'Cancel';
  String get logout => _isZh ? '登出' : 'Logout';
  String get login => _isZh ? '登录' : 'Login';
  String get connected => _isZh ? '已连接' : 'Connected';
  String get notLoggedIn => _isZh ? '未登录' : 'Not logged in';
  String get clear => _isZh ? '清空' : 'Clear';
  String get delete => _isZh ? '删除' : 'Delete';
  String get save => _isZh ? '保存' : 'Save';
  String get close => _isZh ? '关闭' : 'Close';
  String get loading => _isZh ? '加载中...' : 'Loading...';
  String get ok => _isZh ? '确定' : 'OK';
  String get pleaseWait => _isZh ? '请稍候...' : 'Please wait...';
  String get stravaAuthSuccess => _isZh ? 'Strava 授权成功' : 'Strava authorized';
  String get syncingPleaseWait => _isZh ? '正在同步中，请稍候...' : 'Syncing, please wait...';
  String get uploadingPleaseWait => _isZh ? '正在上传中，请稍候...' : 'Uploading, please wait...';
  String get dataSourceNotLoggedIn => _isZh ? '数据源未登录' : 'Source not logged in';
  String get sourceCyclingLabel => _isZh ? '数据源 · 骑行活动' : 'Source · Cycling';
  String get sourceCyclingRunLabel => _isZh ? '数据源 · 骑行/跑步' : 'Source · Cycling/Running';
  String get edgeRideSubtitle => _isZh ? '边缘骑行平台' : 'Edge cycling platform';

  // ===== 首页 =====
  String get ready => _isZh ? '已就绪' : 'Ready';
  String get notReady => _isZh ? '未就绪' : 'Not Ready';
  String get syncing => _isZh ? '同步中...' : 'Syncing...';
  String platformsConnected(int n) => _isZh ? '$n/6 平台已连接' : '$n/6 platforms connected';
  String get startSync => _isZh ? '开始同步' : 'Start Sync';
  String get syncHint => _isZh ? '连接数据源和目标平台后可同步' : 'Connect data source and targets to sync';
  String get runningLog => _isZh ? '运行日志' : 'Log';
  String get dataSourcePlatform => _isZh ? '数据源平台' : 'Data Source';
  String get uploadTargetPlatform => _isZh ? '上传目标平台' : 'Upload Targets';
  String get dataSource => _isZh ? '数据源' : 'Source';
  String get clickToLogin => _isZh ? '点击登录' : 'Tap to login';
  String syncComplete(int success, int failed) =>
      _isZh ? '同步完成: 成功 $success, 失败 $failed' : 'Sync done: $success success, $failed failed';
  String get noNewActivities => _isZh ? '没有新活动需要同步' : 'No new activities to sync';
  String get syncFailed => _isZh ? '同步失败: ' : 'Sync failed: ';
  String get syncToPlatform => _isZh ? '同步到' : 'Sync to';
  String syncSourceLabel(String p) => _isZh ? '数据源 · $p' : 'Source · $p';
  String get selectFile => _isZh ? '点击选择 .FIT .GPX .TCX 文件' : 'Tap to select .FIT .GPX .TCX files';
  String get orShare => _isZh ? '或从其他应用分享文件到此处' : 'Or share files from other apps';
  String get uploading => _isZh ? '上传中...' : 'Uploading...';

  // ===== 设置页 =====
  String get cyclingActivities => _isZh ? '骑行活动' : 'Cycling';
  String get cyclingRunActivities => _isZh ? '骑行/跑步活动' : 'Cycling/Running';
  String get syncSettings => _isZh ? '同步设置' : 'Sync Settings';
  String get detailedSyncSettings => _isZh ? '详细同步设置' : 'Detailed Sync Settings';
  String get coordFixDesc => _isZh ? '坐标纠偏、同步间隔' : 'Coordinate fix, sync interval';
  String get about => _isZh ? '关于' : 'About';
  String get version => _isZh ? '版本' : 'Version';
  String get clearCache => _isZh ? '清除缓存' : 'Clear Cache';
  String get cacheCleared => _isZh ? '缓存已清除' : 'Cache cleared';
  String get donate => _isZh ? '捐赠&打赏' : 'Donate';
  String get supportDev => _isZh ? '支持开发者' : 'Support Developer';
  String get language => _isZh ? '语言' : 'Language';
  String get chinese => _isZh ? '中文' : 'Chinese';
  String get english => _isZh ? '英文' : 'English';
  String get needLoginFirst => _isZh ? '需先登录' : 'Login required';
  String get cannotBeTarget => _isZh ? '当前数据源 · 不可作为上传目标' : 'Current data source · Cannot be target';
  String get comingSoon => _isZh ? '即将上线' : 'Coming soon';
  String get currentDataSource => _isZh ? '当前数据源' : 'Current Source';

  // ===== 登录页 =====
  String get loginSuccess => _isZh ? '登录成功' : 'Login successful';
  String get loginFailed => _isZh ? '登录失败' : 'Login failed';
  String get loginError => _isZh ? '登录错误' : 'Login error';
  String get usernameOrPhone => _isZh ? '用户名/手机号' : 'Username/Phone';
  String get password => _isZh ? '密码' : 'Password';
  String get phoneNumber => _isZh ? '手机号' : 'Phone Number';
  String get verifyCode => _isZh ? '验证码' : 'Verification Code';
  String get sendCode => _isZh ? '发送验证码' : 'Send Code';
  String get codeSent => _isZh ? '验证码已发送到' : 'Code sent to';
  String get enterPhoneAndCode => _isZh ? '请输入手机号和验证码' : 'Enter phone and code';
  String get enterUsernameAndPassword => _isZh ? '请输入用户名和密码' : 'Enter username and password';
  String get enterUsernamePassword => _isZh ? '请输入用户名和密码' : 'Enter username and password';
  String get uploadSuccess => _isZh ? '上传成功' : 'Upload successful';
  String get uploadFailed => _isZh ? '上传失败' : 'Upload failed';
  String notLoggedInToPlatform(String p) => _isZh ? '$p未登录' : '$p not logged in';
  String get passwordLogin => _isZh ? '密码登录' : 'Password';
  String get smsLogin => _isZh ? '验证码登录' : 'SMS';

  // ===== 登出 =====
  String logoutTitle(String name) => _isZh ? '登出 $name' : 'Logout $name';
  String logoutConfirm(String name) => _isZh ? '确定要登出 $name 吗？' : 'Confirm logout $name?';
  String loggedOut(String name) => _isZh ? '$name 已登出' : '$name logged out';

  // ===== 平台名称 =====
  String get strava => 'Strava';
  String get igpsport => 'iGPSPORT';
  String get xingzhe => _isZh ? '行者' : 'Xingzhe';
  String get onelap => _isZh ? '顽鹿(迈金)' : 'OneLap (Magene)';
  String get giant => _isZh ? '捷安特 RideLife' : 'Giant RideLife';
  String get garmin => _isZh ? '佳明 Connect' : 'Garmin Connect';
  String get edgeRide => 'EdgeRide';

  String platformSubtitle(String platform) {
    switch (platform) {
      case 'strava': return _isZh ? '国际运动平台' : 'International sports platform';
      case 'igp': case 'xingzhe': return _isZh ? '国内骑行平台' : 'Domestic cycling platform';
      case 'giant': return _isZh ? '捷安特官方平台' : 'Giant official platform';
      case 'garmin': return _isZh ? '佳明中国平台' : 'Garmin China platform';
      case 'edge_ride': return _isZh ? '边缘骑行平台' : 'Edge cycling platform';
      default: return '';
    }
  }

  // ===== 同步状态 =====
  String syncingActivities(int n) => _isZh ? '正在同步 $n 个活动' : 'Syncing $n activities';
  String get loginWillAutoSync => _isZh ? '登录后将自动同步骑行数据' : 'Login to auto sync cycling data';
  String get uploadEdgeRideHint => _isZh ? '登录后可将活动同步到EdgeRide平台' : 'Login to sync activities to EdgeRide';
  String get codeSendFailed => _isZh ? '发送验证码失败，请重试' : 'Failed to send code, please retry';
  String get invalidPhone => _isZh ? '请输入正确的手机号' : 'Please enter a valid phone number';
  String get invalidCode => _isZh ? '请输入正确的验证码' : 'Please enter a valid code';

  // ===== 文件同步 =====
  String get onlyFitGpxTcx => _isZh ? '只支持 .fit、.gpx、.tcx 文件' : 'Only .fit, .gpx, .tcx files supported';
  String syncSuccess(String platform, String file) =>
      _isZh ? '$platform 同步成功: $file' : '$platform sync success: $file';
  String get usingCache => _isZh ? '使用缓存文件: ' : 'Using cached: ';
  String get downloadComplete => _isZh ? '下载完成: ' : 'Downloaded: ';
  String get syncingTo => _isZh ? '开始同步到 ' : 'Syncing to ';

  // ===== 捐赠页 =====
  String get donateTitle => _isZh ? '捐赠&打赏' : 'Donate';
  String get donateThanks => _isZh ? '感谢您的支持！' : 'Thank you for your support!';
  String get donateDesc => _isZh ? '如果这个工具帮助到了您\n欢迎捐赠支持开发者继续改进' : 'If this tool helped you\nconsider donating to support development';
  String get alipay => _isZh ? '支付宝' : 'Alipay';
  String get wechatPay => _isZh ? '微信支付' : 'WeChat Pay';
  String get donateFooter => _isZh ? '您的每一份支持都是我们前进的动力' : 'Every bit of support keeps us going';
  String get donateThanks2 => _isZh ? '❤️ 谢谢 ❤️' : '❤️ Thank you ❤️';
  String get githubProject => _isZh ? 'GitHub 项目地址' : 'GitHub Project';
  String get githubProjectDesc => _isZh ? '欢迎 Star ⭐ & Fork 🍴' : 'Star ⭐ & Fork 🍴 welcome!';

  // ===== 作者 & 俱乐部 =====
  String get authorInfo => _isZh ? '长安四季#小悟空' : 'ChangAnSiJi#XiaoWuKong';
  String get clubIntroTitle => _isZh ? '长安四季骑行俱乐部' : 'ChangAnSiJi Cycling Club';
  String get clubName => _isZh ? '长安四季骑行俱乐部' : 'ChangAnSiJi Cycling Club';
  String get clubSlogan => _isZh
      ? '长安四季（CASF · Chang An Four Seasons）\n尽览古城四季更迭，山水花色；春夏秋冬都骑，哪季都不缺席'
      : 'Chang An Four Seasons (CASF)\nRide through all four seasons of the ancient capital; mountains, rivers, and blossoms — we ride them all, never missing a season';
  String get clubAbout => _isZh ? '俱乐部介绍' : 'About Us';
  String get clubDescription => _isZh
      ? '长安四季骑行俱乐部成立于2023年，坐落于古都西安。\n\n'
          '我们是一群热爱骑行、追求自由的伙伴，无论春夏秋冬，每一个季节都有我们的轮迹。俱乐部秉持"快乐骑行、安全第一"的理念，致力于为每一位骑行爱好者打造一个温暖、专业的骑行社区。\n\n'
          '俱乐部定期组织周末骑游、长途拉练、夜骑长安等活动，覆盖秦岭、环山路、渭河绿道等经典路线。无论你是新手入门还是资深老鸟，都能在这里找到志同道合的伙伴。'
      : 'Founded in 2023, ChangAnSiJi Cycling Club is based in Xi\'an, China.\n\n'
          'We are a group of cycling enthusiasts who love riding and freedom. Our tracks cover all four seasons around the ancient capital. The club adheres to the principle of "Happy Riding, Safety First" and is committed to building a warm and professional cycling community for every rider.\n\n'
          'We regularly organize weekend rides, long-distance training, and night rides around classic routes including Qinling Mountains, Huanshan Road, and Weihe Greenway. Whether you\'re a beginner or a veteran, you\'ll find like-minded friends here.';
  String get clubJoinUs => _isZh ? '加入我们' : 'Join Us';
  String get clubJoinIntro => _isZh
      ? '如果你也热爱骑行，欢迎加入长安四季骑行俱乐部！请添加微信好友（注明来意）：'
      : 'If you love cycling too, welcome to join us! Add us on WeChat (please state your purpose):';
  String get clubJoinActivity => _isZh
      ? '🕐 每日早昆，早上 6:20 昆明池大石头\n\n一起用车轮丈量长安，用汗水书写四季！'
      : '🕐 Daily morning ride, 6:20 AM at Kunming Lake Big Stone\n\nLet\'s measure Chang\'an with our wheels!';

  // ===== 更新 =====
  String get alreadyLatestVersion => _isZh ? '已是最新版本' : 'Already up to date';
  String get findNewVersion => _isZh ? '发现新版本' : 'New version available';
  String get changelog => _isZh ? '更新内容' : 'Changelog';
  String get versionNo => _isZh ? '版本号' : 'Version';
  String get updateNow => _isZh ? '立即更新' : 'Update Now';
  String get checkUpdateFailed => _isZh ? '检查更新失败' : 'Check update failed';
  String get downloading => _isZh ? '正在下载...' : 'Downloading...';
  String get downloadFailed => _isZh ? '下载失败，请重试' : 'Download failed, please retry';
  String get installPrompt => _isZh ? '下载完成，即将安装更新' : 'Downloaded, installing...';

  // ===== 日志 =====
  String get noLogs => _isZh ? '暂无日志' : 'No logs';
}
