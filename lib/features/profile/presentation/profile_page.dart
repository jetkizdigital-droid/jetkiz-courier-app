import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jetkiz_courier_app/core/auth/logout_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';
import 'package:jetkiz_courier_app/features/finance/presentation/finance_page.dart';
import 'package:jetkiz_courier_app/features/home/home_page.dart';
import 'package:jetkiz_courier_app/features/navigation/navigation_presentation/widgets/courier_bottom_bar.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/orders_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static final Uri _offerUri = Uri.parse('https://jetkiz.asia/offer');
  static final Uri _privacyUri = Uri.parse('https://jetkiz.asia/privacy');

  late final _CourierProfileApi _api;
  late final LogoutService _logoutService;
  final ImagePicker _imagePicker = ImagePicker();

  bool _loading = true;
  bool _uploadingPhoto = false;
  bool _loggingOut = false;
  String? _error;
  String _fullName = 'Курьер';
  String? _avatarUrl;
  bool _isOnline = false;
  int _ordersCount = 0;
  String _version = '—';

  @override
  void initState() {
    super.initState();
    _api = _CourierProfileApi(ApiClient());
    _logoutService = LogoutService();
    unawaited(_loadProfile());
    unawaited(_loadVersion());
  }

  @override
  void dispose() {
    _api.dispose();
    unawaited(_logoutService.dispose());
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.buildNumber.trim().isEmpty
            ? info.version
            : '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      // Version is informational only.
    }
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = await _api.getMe();

      if (!mounted) return;
      setState(() {
        _fullName = [me.firstName, me.lastName]
            .where((value) => value.trim().isNotEmpty)
            .join(' ');
        if (_fullName.isEmpty) _fullName = 'Курьер';
        _avatarUrl = me.avatarUrl;
        _isOnline = me.isOnline;
        _ordersCount = me.ordersCount;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanizeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_uploadingPhoto) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (picked == null) return;
      _assertSupportedImage(picked.path);

      setState(() => _uploadingPhoto = true);
      final avatarUrl = await _api.uploadAvatar(File(picked.path));

      if (!mounted) return;
      setState(() => _avatarUrl = avatarUrl);
      _showSnackBar('Фото обновлено');
    } on _AvatarFormatException catch (e) {
      _showSnackBar(e.message);
    } catch (e) {
      _showSnackBar(_humanizeError(e));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _assertSupportedImage(String path) {
    final lower = path.toLowerCase();
    final supported = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');

    if (!supported) {
      throw const _AvatarFormatException(
        'Выберите изображение JPG, PNG или WEBP.',
      );
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() => _loggingOut = true);

    try {
      final hasActiveOrder = await _api.hasActiveOrder();

      if (hasActiveOrder) {
        _showSnackBar('Сначала завершите активную доставку, затем выйдите.');
        return;
      }

      final confirmed = await _confirmLogout();
      if (!confirmed) return;

      await _logoutService.logout();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      _showSnackBar(_humanizeError(e));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<bool> _confirmLogout() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'Статус курьера станет оффлайн, геолокация и push-регистрация этого устройства будут остановлены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _openExternal(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showSnackBar('Не удалось открыть страницу.');
  }

  void _onBottomBarTap(int index) {
    if (index == 3) return;

    final Widget page = switch (index) {
      0 => const HomePage(),
      1 => const OrdersPage(),
      2 => const FinancePage(),
      _ => const ProfilePage(),
    };

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  String _humanizeError(Object error) {
    if (error is ApiException) {
      switch (error.kind) {
        case ApiErrorKind.network:
          return 'Нет соединения с сервером. Проверьте интернет.';
        case ApiErrorKind.timeout:
          return 'Сервер не ответил вовремя. Попробуйте ещё раз.';
        case ApiErrorKind.sessionExpired:
        case ApiErrorKind.unauthorized:
          return 'Сессия истекла. Войдите заново.';
        case ApiErrorKind.forbidden:
          return 'Действие недоступно для этого аккаунта.';
        default:
          return 'Не удалось выполнить действие. Попробуйте ещё раз.';
      }
    }

    return 'Не удалось выполнить действие. Попробуйте ещё раз.';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF8F8FA);

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: CourierBottomBar(
        currentIndex: 3,
        onTap: _onBottomBarTap,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _loadProfile)
            : RefreshIndicator(
                onRefresh: _loadProfile,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  children: [
                    const Text(
                      'Профиль',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ProfileHeaderCard(
                      fullName: _fullName,
                      avatarUrl: _avatarUrl,
                      isOnline: _isOnline,
                      uploadingPhoto: _uploadingPhoto,
                      onPhotoTap: _pickAndUploadPhoto,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            title: 'Заказы',
                            value: '$_ordersCount',
                            icon: Icons.receipt_long_outlined,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricCard(
                            title: 'Статус',
                            value: _isOnline ? 'Онлайн' : 'Оффлайн',
                            icon: Icons.wifi_tethering_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle('Документы'),
                    const SizedBox(height: 10),
                    _MenuTile(
                      title: 'Пользовательское соглашение',
                      subtitle: 'jetkiz.asia/offer',
                      icon: Icons.description_outlined,
                      onTap: () => _openExternal(_offerUri),
                    ),
                    const SizedBox(height: 10),
                    _MenuTile(
                      title: 'Политика конфиденциальности',
                      subtitle: 'jetkiz.asia/privacy',
                      icon: Icons.privacy_tip_outlined,
                      onTap: () => _openExternal(_privacyUri),
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle('Приложение'),
                    const SizedBox(height: 10),
                    _InfoTile(
                      title: 'JETKIZ Курьер',
                      subtitle: 'Версия $_version',
                      icon: Icons.info_outline_rounded,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _loggingOut ? null : _logout,
                        icon: _loggingOut
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.logout_rounded),
                        label: const Text(
                          'Выйти',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB42318),
                          side: const BorderSide(color: Color(0xFFF1C4C4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CourierProfileApi {
  const _CourierProfileApi(this._client);

  final ApiClient _client;

  Future<_CourierMe> getMe() async {
    final json = _asMap(await _client.get('/couriers/me'));
    final profile = _asNullableMap(json['courierProfile']);

    return _CourierMe(
      firstName: _firstNonEmpty([
            json['firstName'],
            profile?['firstName'],
          ]) ??
          '',
      lastName: _firstNonEmpty([
            json['lastName'],
            profile?['lastName'],
          ]) ??
          '',
      avatarUrl: _normalizeImageUrl(
        _firstNonEmpty([json['avatarUrl'], profile?['avatarUrl']]),
      ),
      isOnline: _bool(json['isOnline']) || _bool(profile?['isOnline']),
      ordersCount: _int(json['ordersCount']) ??
          _int(_asNullableMap(json['stats'])?['completedOrders']) ??
          0,
    );
  }

  Future<bool> hasActiveOrder() async {
    final response = await _client.get('/orders/courier/active');
    if (response == null) return false;
    final map = _asMap(response);
    if (map.isEmpty) return false;
    return (map['fulfillmentType'] ?? 'DELIVERY')
            .toString()
            .toUpperCase() !=
        'PICKUP';
  }

  Future<String?> uploadAvatar(File file) async {
    final response = _asMap(
      await _client.postMultipart(
        '/couriers/me/avatar',
        fieldName: 'file',
        filePath: file.path,
      ),
    );

    return _normalizeImageUrl(_firstNonEmpty([response['avatarUrl']]));
  }

  String? _normalizeImageUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '${ApiClient.baseUrl}${raw.startsWith('/') ? raw : '/$raw'}';
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static Map<String, dynamic>? _asNullableMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1';
  }

  void dispose() => _client.dispose();
}

class _CourierMe {
  const _CourierMe({
    required this.firstName,
    required this.lastName,
    required this.avatarUrl,
    required this.isOnline,
    required this.ordersCount,
  });

  final String firstName;
  final String lastName;
  final String? avatarUrl;
  final bool isOnline;
  final int ordersCount;
}

class _AvatarFormatException implements Exception {
  const _AvatarFormatException(this.message);

  final String message;
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.fullName,
    required this.avatarUrl,
    required this.isOnline,
    required this.uploadingPhoto,
    required this.onPhotoTap,
  });

  final String fullName;
  final String? avatarUrl;
  final bool isOnline;
  final bool uploadingPhoto;
  final VoidCallback onPhotoTap;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF489F2A);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: uploadingPhoto ? null : onPhotoTap,
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFFE5E7EB),
                  backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl!),
                  child: avatarUrl == null
                      ? const Icon(Icons.person_rounded, size: 34)
                      : null,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: uploadingPhoto ? null : onPhotoTap,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: uploadingPhoto
                        ? const Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFFECFDF3)
                        : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isOnline ? 'Онлайн' : 'Оффлайн',
                    style: TextStyle(
                      color: isOnline
                          ? const Color(0xFF027A48)
                          : const Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF489F2A)),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF489F2A)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_rounded, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF489F2A)),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => unawaited(onRetry()),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
