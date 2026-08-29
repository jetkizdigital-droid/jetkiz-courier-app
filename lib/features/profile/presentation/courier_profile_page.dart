import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jetkiz_courier_app/core/auth/logout_service.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/push/push_registration_service.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class CourierProfilePage extends StatefulWidget {
  const CourierProfilePage({super.key});

  @override
  State<CourierProfilePage> createState() => _CourierProfilePageState();
}

class _CourierProfilePageState extends State<CourierProfilePage> {
  static final Uri _offerUri = Uri.parse('https://jetkiz.asia/offer');
  static final Uri _privacyUri = Uri.parse('https://jetkiz.asia/privacy');
  static final Uri _supportUri = Uri.parse('https://t.me/+oOgI_P4cqdZlNjFi');

  late final ApiClient _client;
  late final LogoutService _logout;
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _uploading = false;
  bool _savingSettings = false;
  bool _loggingOut = false;
  String? _errorKey;
  String _name = '';
  String? _avatarUrl;
  bool _online = false;
  int _ordersCount = 0;
  bool _pushEnabled = true;
  String _version = '—';

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    _client = ApiClient();
    _logout = LogoutService();
    unawaited(_load());
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
    } catch (_) {}
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorKey = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        _client.get('/couriers/me'),
        _client.get('/client-settings/me'),
      ]);
      final me = _asMap(results[0]);
      final settingsEnvelope = _asMap(results[1]);
      final settings = _asMap(settingsEnvelope['settings']);
      final profile = _map(me['courierProfile']) ?? _map(me['profile']);
      final first = _firstText([me['firstName'], profile?['firstName']]);
      final last = _firstText([me['lastName'], profile?['lastName']]);
      final fullName = [first, last].where((v) => v.isNotEmpty).join(' ');

      if (!mounted) return;
      setState(() {
        _name = fullName;
        _avatarUrl = _normalizeImageUrl(
          _firstText([me['avatarUrl'], profile?['avatarUrl']]),
        );
        _online = _bool(me['isOnline']) || _bool(profile?['isOnline']);
        _ordersCount =
            _int(me['ordersCount']) ??
            _int(_map(me['stats'])?['completedOrders']) ??
            0;
        _pushEnabled = settings['pushEnabled'] != false;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorKey = _errorFor(error));
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'error.generic');
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
        _show(_locale.t('profile.photoFormat'));
        return;
      }

      setState(() => _uploading = true);
      final response = _asMap(
        await _client.postMultipart(
          '/couriers/me/avatar',
          fieldName: 'file',
          filePath: File(picked.path).path,
        ),
      );
      final avatar = _normalizeImageUrl(_firstText([response['avatarUrl']]));
      if (!mounted) return;
      setState(() => _avatarUrl = avatar);
      _show(_locale.t('profile.photoUpdated'));
    } on ApiException catch (error) {
      _show(_avatarError(error));
    } catch (_) {
      _show(_locale.t('error.generic'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _avatarError(ApiException error) {
    if (error.statusCode == 413) return _locale.t('profile.photoTooLarge');
    if (error.statusCode == 429) return _locale.t('profile.photoRateLimit');
    if (error.statusCode == 400) return _locale.t('profile.photoFormat');
    return _locale.t(_errorFor(error));
  }

  Future<void> _setLanguage(String language) async {
    if (_savingSettings || language == _locale.languageCode) return;
    setState(() => _savingSettings = true);
    try {
      await _locale.setAuthenticatedLanguage(_client, language);
    } on ApiException catch (error) {
      _show(_locale.t(_errorFor(error)));
    } catch (_) {
      _show(_locale.t('profile.settingsSaveFailed'));
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _setPushEnabled(bool value) async {
    if (_savingSettings || value == _pushEnabled) return;
    setState(() => _savingSettings = true);
    final push = PushRegistrationService(apiClient: _client);
    try {
      await _client.patch('/client-settings/me', {'pushEnabled': value});
      if (value) {
        final token = await push.getToken();
        if (token != null && token.isNotEmpty) {
          await push.registerToken(token);
        }
      } else {
        try {
          await push.unregisterCurrentToken();
        } catch (_) {
          // pushEnabled=false is already enforced by backend.
        }
      }
      if (!mounted) return;
      setState(() => _pushEnabled = value);
    } on ApiException catch (error) {
      _show(_locale.t(_errorFor(error)));
    } catch (_) {
      _show(_locale.t('profile.settingsSaveFailed'));
    } finally {
      await push.dispose();
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _logoutAccount() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      final active = _asMap(await _client.get('/orders/courier/active'));
      final order =
          _map(active['activeOrder']) ??
          (_text(active['id']).isNotEmpty ? active : null);
      if (order != null &&
          _text(order['fulfillmentType']).toUpperCase() != 'PICKUP') {
        _show(_locale.t('profile.activeDelivery'));
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_locale.t('profile.logoutTitle')),
          content: Text(_locale.t('profile.logoutBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_locale.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_locale.t('profile.logout')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      await _logout.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } on ApiException catch (error) {
      _show(_locale.t(_errorFor(error)));
    } catch (_) {
      _show(_locale.t('error.generic'));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _open(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _show(_locale.t('profile.pageOpenFailed'));
  }

  String _errorFor(ApiException error) {
    switch (error.kind) {
      case ApiErrorKind.network:
        return 'error.network';
      case ApiErrorKind.timeout:
        return 'error.timeout';
      case ApiErrorKind.sessionExpired:
      case ApiErrorKind.unauthorized:
        return 'error.session';
      case ApiErrorKind.forbidden:
        return 'error.forbidden';
      default:
        return 'error.generic';
    }
  }

  void _show(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String? _normalizeImageUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '${ApiClient.baseUrl}${raw.startsWith('/') ? raw : '/$raw'}';
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.isEmpty ? _locale.t('home.courier') : _name;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorKey != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_off_outlined, size: 46),
                      const SizedBox(height: 12),
                      Text(_locale.t(_errorKey!), textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _load,
                        child: Text(_locale.t('common.retry')),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  children: [
                    Text(
                      _locale.t('profile.title'),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ProfileHeader(
                      name: name,
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
                            label: _locale.t('profile.orders'),
                            value: '$_ordersCount',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Metric(
                            label: _locale.t('profile.status'),
                            value: _locale.t(
                              _online ? 'profile.online' : 'profile.offline',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      _locale.t('profile.management'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SettingsTile(
                      icon: Icons.language_rounded,
                      title: _locale.t('profile.language'),
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'ru', label: Text('RU')),
                          ButtonSegment(value: 'kk', label: Text('ҚАЗ')),
                        ],
                        selected: {_locale.languageCode},
                        onSelectionChanged: _savingSettings
                            ? null
                            : (selection) {
                                if (selection.isNotEmpty) {
                                  unawaited(_setLanguage(selection.first));
                                }
                              },
                        showSelectedIcon: false,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.notifications_outlined,
                      title: _locale.t('profile.notifications'),
                      trailing: Switch.adaptive(
                        value: _pushEnabled,
                        onChanged: _savingSettings
                            ? null
                            : (value) => unawaited(_setPushEnabled(value)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.support_agent_rounded,
                      title: _locale.isKazakh ? 'Қолдау' : 'Поддержка',
                      onTap: () => _open(_supportUri),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      title: _locale.t('profile.offer'),
                      onTap: () => _open(_offerUri),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: _locale.t('profile.privacy'),
                      onTap: () => _open(_privacyUri),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: _locale.format('profile.version', {
                        'version': _version,
                      }),
                    ),
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
                        label: Text(
                          _locale.t('profile.logout'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB42318),
                          side: const BorderSide(color: Color(0xFFF1C4C4)),
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
  Widget build(BuildContext context) => Container(
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
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFF3FAE2A),
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
              const SizedBox(height: 7),
              Text(
                CourierLocaleController.instance.t(
                  online ? 'profile.online' : 'profile.offline',
                ),
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

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
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
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
        ),
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF3FAE2A)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
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
