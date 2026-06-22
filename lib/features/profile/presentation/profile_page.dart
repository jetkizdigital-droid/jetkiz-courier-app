import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:jetkiz_courier_app/core/auth/logout_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/storage/token_storage.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';
import 'package:jetkiz_courier_app/features/finance/presentation/finance_page.dart';
import 'package:jetkiz_courier_app/features/home/home_page.dart';
import 'package:jetkiz_courier_app/features/navigation/navigation_presentation/widgets/courier_bottom_bar.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/orders_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
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

  @override
  void initState() {
    super.initState();

    _api = _CourierProfileApi(ApiClient());
    _logoutService = LogoutService();

    _loadProfile();
  }

  @override
  void dispose() {
    unawaited(_logoutService.dispose());
    super.dispose();
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
        _fullName = _buildFullName(me.firstName, me.lastName);
        _avatarUrl = me.avatarUrl;
        _isOnline = me.isOnline;
        _ordersCount = me.ordersCount;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Не удалось загрузить профиль: $e';
        _loading = false;
      });
    }
  }

  String _buildFullName(String firstName, String lastName) {
    final parts = [
      firstName.trim(),
      lastName.trim(),
    ].where((e) => e.isNotEmpty).toList();

    if (parts.isEmpty) return 'Курьер';
    return parts.join(' ');
  }

  Future<void> _pickAndUploadPhoto() async {
    if (_uploadingPhoto) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );

      if (picked == null) return;

      setState(() {
        _uploadingPhoto = true;
      });

      final avatarUrl = await _api.uploadAvatar(File(picked.path));

      if (!mounted) return;

      setState(() {
        _avatarUrl = avatarUrl;
      });

      _showSnackBar('Фото обновлено');
    } on _AvatarFormatException catch (e) {
      if (!mounted) return;
      _showSnackBar(e.message);
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Не удалось загрузить фото');
    } finally {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
      });
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() {
      _loggingOut = true;
    });

    try {
      try {
        await _api.setOnline(false);
      } catch (_) {
        // Выход не должен блокироваться из-за ошибки смены online-статуса.
      }

      await _logoutService.logout();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loggingOut = false;
      });

      _showSnackBar('Не удалось выйти');
    }
  }

  void _showDocuments() {
    _showSnackBar('Документы подключим следующим файлом');
  }

  void _showHelp() {
    _showSnackBar('Помощь подключим следующим файлом');
  }

  void _onBottomBarTap(int index) {
    if (index == 3) return;

    if (index == 0) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      return;
    }

    if (index == 1) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const OrdersPage()));
      return;
    }

    if (index == 2) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const FinancePage()));
      return;
    }
  }

  void _showSnackBar(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(text)));
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
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF489F2A)),
              )
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _loadProfile)
            : RefreshIndicator(
                color: const Color(0xFF489F2A),
                onRefresh: _loadProfile,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
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
                    const SizedBox(height: 14),
                    _StatCard(
                      title: 'Количество заказов',
                      value: '$_ordersCount',
                      icon: Icons.receipt_long_rounded,
                    ),
                    const SizedBox(height: 14),
                    _StatusCard(isOnline: _isOnline),
                    const SizedBox(height: 14),
                    _MenuTile(
                      title: 'Документы',
                      icon: Icons.description_outlined,
                      onTap: _showDocuments,
                    ),
                    const SizedBox(height: 10),
                    _MenuTile(
                      title: 'Помощь',
                      icon: Icons.help_outline_rounded,
                      onTap: _showHelp,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loggingOut ? null : _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF374151),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                        ),
                        child: _loggingOut
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Выйти',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
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
    const accent = Color(0xFF489F2A);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
                  backgroundImage:
                      avatarUrl != null && avatarUrl!.trim().isNotEmpty
                      ? NetworkImage(avatarUrl!)
                      : null,
                  child: avatarUrl == null || avatarUrl!.trim().isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          size: 34,
                          color: Color(0xFF6B7280),
                        )
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
                      color: accent,
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
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFFECFDF3)
                        : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isOnline
                          ? const Color(0xFFA6F4C5)
                          : const Color(0xFFD0D5DD),
                    ),
                  ),
                  child: Text(
                    isOnline ? 'Онлайн' : 'Оффлайн',
                    style: TextStyle(
                      color: isOnline
                          ? const Color(0xFF027A48)
                          : const Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

class _StatCard extends StatelessWidget {
  const _StatCard({
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF489F2A).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF489F2A)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color:
                  (isOnline ? const Color(0xFF12B76A) : const Color(0xFF98A2B3))
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.wifi_tethering_rounded,
              color: isOnline
                  ? const Color(0xFF12B76A)
                  : const Color(0xFF98A2B3),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Статус',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
          ),
          Text(
            isOnline ? 'Онлайн' : 'Оффлайн',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isOnline
                  ? const Color(0xFF027A48)
                  : const Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE4E8EF)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF489F2A).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF489F2A)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
            ],
          ),
        ),
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
            const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Color(0xFFD92D20),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF489F2A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourierProfileApi {
  _CourierProfileApi(this._client, {TokenStorage? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorage();

  final ApiClient _client;
  final TokenStorage _tokenStorage;

  Future<_CourierMe> getMe() async {
    final dynamic response = await _client.get('/couriers/me');
    final json = _asMap(response);

    final firstName = _readString(
      json,
      const ['firstName'],
      fallbackKeys: const ['courierProfile.firstName', 'user.firstName'],
    );

    final lastName = _readString(
      json,
      const ['lastName'],
      fallbackKeys: const ['courierProfile.lastName', 'user.lastName'],
    );

    final avatarUrl = _normalizeImageUrl(
      _readNullableString(
        json,
        const ['avatarUrl'],
        fallbackKeys: const ['user.avatarUrl'],
      ),
    );

    final isOnline = _readBool(
      json,
      const ['isOnline'],
      fallbackKeys: const ['courierProfile.isOnline'],
    );

    final ordersCount = _readInt(
      json,
      const ['ordersCount'],
      fallbackKeys: const ['stats.todayCompleted', 'todayCompleted'],
    );

    final activeOrder = _readMap(json, const ['activeOrder']);
    final activeOrders =
        _extractList(json, const ['activeOrders']) ?? const <dynamic>[];

    return _CourierMe(
      firstName: firstName,
      lastName: lastName,
      avatarUrl: avatarUrl,
      isOnline: isOnline,
      ordersCount: ordersCount > 0
          ? ordersCount
          : (activeOrder != null || activeOrders.isNotEmpty ? 1 : 0),
    );
  }

  Future<String?> uploadAvatar(File file) async {
    final contentType = _avatarContentType(file.path);

    final accessToken = await _tokenStorage.getAccessToken();

    if (accessToken == null || accessToken.trim().isEmpty) {
      throw Exception('Нет access token');
    }

    final uri = Uri.parse('${ApiClient.baseUrl}/couriers/me/avatar');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'avatar.jpg',
        contentType: contentType,
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Ошибка загрузки фото: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final json = _asMap(decoded);

    return _normalizeImageUrl(_readNullableString(json, const ['avatarUrl']));
  }

  static http.MediaType _avatarContentType(String path) {
    final normalized = path.trim().toLowerCase();
    final dotIndex = normalized.lastIndexOf('.');
    final extension = dotIndex >= 0 ? normalized.substring(dotIndex) : '';

    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return http.MediaType('image', 'jpeg');
      case '.png':
        return http.MediaType('image', 'png');
      case '.webp':
        return http.MediaType('image', 'webp');
      case '.heic':
      case '.heif':
        throw const _AvatarFormatException(
          'Этот формат фото не поддерживается. Выберите JPG, PNG или WEBP.',
        );
      default:
        throw const _AvatarFormatException('Неподдерживаемый формат файла.');
    }
  }

  Future<void> setOnline(bool value) async {
    await _client.patch('/couriers/me/online', {
      'isOnline': value,
      'source': 'mobile',
    });
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic>? _extractList(
    Map<String, dynamic> json,
    List<String> path,
  ) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    return current is List ? current : null;
  }

  static Map<String, dynamic>? _readMap(
    Map<String, dynamic> json,
    List<String> path,
  ) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    if (current is Map<String, dynamic>) return current;
    if (current is Map) return Map<String, dynamic>.from(current);
    return null;
  }

  static String _readString(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    return value?.toString() ?? '';
  }

  static String? _readNullableString(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _readInt(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _readBool(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);

    if (value is bool) return value;
    if (value is num) return value != 0;

    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1';
  }

  static dynamic _readValue(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        current = null;
        break;
      }
    }

    if (current != null) return current;

    for (final key in fallbackKeys) {
      final fallback = _readByKeyPath(json, key);
      if (fallback != null) return fallback;
    }

    return null;
  }

  static dynamic _readByKeyPath(Map<String, dynamic> json, String path) {
    dynamic current = json;

    for (final part in path.split('.')) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    return current;
  }

  static String? _normalizeImageUrl(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    if (raw.startsWith('/')) {
      return '${ApiClient.baseUrl}$raw';
    }

    return '${ApiClient.baseUrl}/$raw';
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

class _AvatarFormatException implements Exception {
  const _AvatarFormatException(this.message);

  final String message;
}
