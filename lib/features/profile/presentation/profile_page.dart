import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jetkiz_courier_app/core/auth/logout_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';
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

  late final ApiClient _client;
  late final _CourierProfileApi _api;
  late final LogoutService _logout;
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _uploading = false;
  bool _loggingOut = false;
  String? _error;
  String _name = 'Курьер';
  String? _avatarUrl;
  bool _online = false;
  int _ordersCount = 0;
  String _version = '—';

  @override
  void initState() {
    super.initState();
    _client = ApiClient();
    _api = _CourierProfileApi(_client);
    _logout = LogoutService();
    unawaited(_loadProfile());
    unawaited(_loadVersion());
  }

  @override
  void dispose() {
    _client.dispose();
    unawaited(_logout.dispose());
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
      // Informational only.
    }
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final me = await _api.getMe();
      if (!mounted) return;

      setState(() {
        final fullName = [
          me.firstName,
          me.lastName,
        ].where((value) => value.trim().isNotEmpty).join(' ');
        _name = fullName.isEmpty ? 'Курьер' : fullName;
        _avatarUrl = me.avatarUrl;
        _online = me.isOnline;
        _ordersCount = me.ordersCount;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _humanizeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploading) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;

      final lower = picked.path.toLowerCase();
      if (!(lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp'))) {
        _showSnackBar('Выберите изображение JPG, PNG или WEBP.');
        return;
      }

      setState(() => _uploading = true);
      final avatarUrl = await _api.uploadAvatar(File(picked.path));

      if (!mounted) return;
      setState(() => _avatarUrl = avatarUrl);
      _showSnackBar('Фото обновлено');
    } catch (error) {
      _showSnackBar(_humanizeError(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _logoutAccount() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);

    try {
      final hasActiveDelivery = await _api.hasActiveDelivery();
      if (!mounted) return;

      if (hasActiveDelivery) {
        _showSnackBar('Сначала завершите активную доставку, затем выйдите.');
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Выйти из аккаунта?'),
          content: const Text(
            'Статус станет оффлайн, а геолокация и push-регистрация этого устройства будут остановлены.',
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

      if (confirmed != true) return;

      await _logout.logout();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (error) {
      _showSnackBar(_humanizeError(error));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _open(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showSnackBar('Не удалось открыть страницу.');
  }

  String _humanizeError(Object error) {
    if (error is ApiException) {
      switch (error.kind) {
        case ApiErrorKind.network:
          return 'Нет соединения с сервером. Проверьте интернет.';
        case ApiErrorKind.timeout:
          return 'Сервер не ответил вовремя.';
        case ApiErrorKind.sessionExpired:
        case ApiErrorKind.unauthorized:
          return 'Сессия истекла. Войдите заново.';
        case ApiErrorKind.forbidden:
          return 'Действие недоступно для этого аккаунта.';
        default:
          return 'Не удалось выполнить действие.';
      }
    }
    return 'Не удалось выполнить действие.';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ProfileError(message: _error!, onRetry: _loadProfile)
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
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ProfileHeader(
                      name: _name,
                      avatarUrl: _avatarUrl,
                      online: _online,
                      uploading: _uploading,
                      onAvatar: _pickAvatar,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            label: 'Заказы',
                            value: '$_ordersCount',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Metric(
                            label: 'Статус',
                            value: _online ? 'Онлайн' : 'Оффлайн',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Документы',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _LinkTile(
                      icon: Icons.description_outlined,
                      title: 'Пользовательское соглашение',
                      subtitle: 'jetkiz.asia/offer',
                      onTap: () => _open(_offerUri),
                    ),
                    const SizedBox(height: 10),
                    _LinkTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Политика конфиденциальности',
                      subtitle: 'jetkiz.asia/privacy',
                      onTap: () => _open(_privacyUri),
                    ),
                    const SizedBox(height: 20),
                    _InfoTile(version: _version),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _loggingOut ? null : _logoutAccount,
                        icon: _loggingOut
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
    final profile = _map(json['courierProfile']) ?? _map(json['profile']);

    return _CourierMe(
      firstName: _firstText([json['firstName'], profile?['firstName']]),
      lastName: _firstText([json['lastName'], profile?['lastName']]),
      avatarUrl: _normalizeImageUrl(
        _firstText([json['avatarUrl'], profile?['avatarUrl']]),
      ),
      isOnline: _bool(json['isOnline']) || _bool(profile?['isOnline']),
      ordersCount:
          _int(json['ordersCount']) ??
          _int(_map(json['stats'])?['completedOrders']) ??
          0,
    );
  }

  Future<bool> hasActiveDelivery() async {
    final raw = _asMap(await _client.get('/orders/courier/active'));
    if (raw.isEmpty) return false;

    final active = _map(raw['activeOrder']);
    final order = active ?? (_text(raw['id']).isNotEmpty ? raw : null);
    if (order == null) return false;

    return _text(order['fulfillmentType']).toUpperCase() != 'PICKUP';
  }

  Future<String?> uploadAvatar(File file) async {
    final response = _asMap(
      await _client.postMultipart(
        '/couriers/me/avatar',
        fieldName: 'file',
        filePath: file.path,
      ),
    );

    return _normalizeImageUrl(_firstText([response['avatarUrl']]));
  }

  String? _normalizeImageUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '${ApiClient.baseUrl}${raw.startsWith('/') ? raw : '/$raw'}';
  }
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.avatarUrl,
    required this.online,
    required this.uploading,
    required this.onAvatar,
  });

  final String name;
  final String? avatarUrl;
  final bool online;
  final bool uploading;
  final VoidCallback onAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: uploading ? null : onAvatar,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFFE5E7EB),
                  backgroundImage: avatarUrl == null
                      ? null
                      : NetworkImage(avatarUrl!),
                  child: avatarUrl == null
                      ? const Icon(Icons.person_rounded, size: 34)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3FAE2A),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: uploading
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
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  online ? 'Онлайн' : 'Оффлайн',
                  style: TextStyle(
                    color: online
                        ? const Color(0xFF027A48)
                        : const Color(0xFF667085),
                    fontWeight: FontWeight.w800,
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

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

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
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
              Icon(icon, color: const Color(0xFF3FAE2A)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
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
  const _InfoTile({required this.version});

  final String version;

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
          const Icon(Icons.info_outline_rounded, color: Color(0xFF3FAE2A)),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'JETKIZ Курьер',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'Версия $version',
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

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.message, required this.onRetry});

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
            const Icon(Icons.error_outline_rounded, size: 44),
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

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

Map<String, dynamic>? _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _text(dynamic value) => value?.toString().trim() ?? '';

String _firstText(List<dynamic> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_text(value));
}

bool _bool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = _text(value).toLowerCase();
  return text == 'true' || text == '1';
}
