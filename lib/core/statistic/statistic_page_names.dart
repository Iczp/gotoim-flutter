/// 统计页面常量与路径映射
class StatisticPageNames {
  const StatisticPageNames._();

  static const home = 'home';
  static const chatHome = 'chat.home';
  static const chatSession = 'chat.session';
  static const contacts = 'contacts.home';
  static const profile = 'profile.home';
  static const settings = 'settings.home';
  static const workbench = 'workbench.home';
  static const search = 'search.home';
  static const login = 'login';
  static const agreement = 'agreement';
  static const groupManagement = 'group.management';
  static const devices = 'devices.list';
  static const diagnostics = 'diagnostics.home';
  static const unknown = 'unknown';

  /// 将实际路由路径映射为稳定规范的统计页面名称
  static String resolvePageName(String? path) {
    if (path == null || path.isEmpty) return home;
    final normalized = path.split('?').first;
    if (normalized == '/' || normalized == '/home') return home;
    if (normalized == '/login') return login;
    if (normalized.startsWith('/agreement')) return agreement;
    if (normalized.startsWith('/workbench')) return workbench;
    if (normalized.startsWith('/search')) return search;
    if (normalized.startsWith('/settings')) return settings;
    if (normalized.startsWith('/account') || normalized.startsWith('/mine')) {
      return profile;
    }
    if (normalized.startsWith('/devices') || normalized.startsWith('/online-devices')) {
      return devices;
    }
    if (normalized.startsWith('/group-management')) return groupManagement;
    if (normalized.startsWith('/diagnostics')) return diagnostics;

    // 聊天相关路由
    if (normalized.startsWith('/chat/')) {
      return chatSession;
    }
    if (normalized == '/chat') return chatHome;

    return normalized.replaceAll('/', '.').replaceAll(RegExp(r'^\.+|\.+$'), '');
  }
}
