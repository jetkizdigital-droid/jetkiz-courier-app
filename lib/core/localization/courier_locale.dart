import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/apiClient.dart';

class CourierLocaleController extends ChangeNotifier {
  CourierLocaleController._();

  static final CourierLocaleController instance = CourierLocaleController._();
  static const _preferenceKey = 'jetkiz.courier.language';
  static const Map<String, String> _legacyKeyAliases = {
    'home.earnings': 'home.earned',
    'home.onlineDescription': 'home.onlineHint',
    'home.offlineDescription': 'home.offlineHint',
  };

  Locale _locale = const Locale('ru');
  bool _localSelectionDirty = false;

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode == 'kk' ? 'kk' : 'ru';
  bool get isKazakh => languageCode == 'kk';

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _locale = Locale(_normalize(preferences.getString(_preferenceKey)));
  }

  Future<void> selectBeforeLogin(String language) async {
    _localSelectionDirty = true;
    await _applyLocal(language);
  }

  Future<void> syncAuthenticated(ApiClient api) async {
    if (_localSelectionDirty) {
      await api.patch('/client-settings/me', {'language': languageCode});
      _localSelectionDirty = false;
      return;
    }

    try {
      final response = _asMap(await api.get('/client-settings/me'));
      final settings = _asMap(response['settings']);
      final serverLanguage = _normalize(settings['language']?.toString());
      await _applyLocal(serverLanguage);
    } catch (_) {
      // Language sync must never block an authenticated courier session.
    }
  }

  Future<void> setAuthenticatedLanguage(ApiClient api, String language) async {
    final normalized = _normalize(language);
    await api.patch('/client-settings/me', {'language': normalized});
    _localSelectionDirty = false;
    await _applyLocal(normalized);
  }

  Future<void> _applyLocal(String? language) async {
    final normalized = _normalize(language);
    final changed = _locale.languageCode != normalized;
    _locale = Locale(normalized);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, normalized);
    if (changed) notifyListeners();
  }

  String t(String key) {
    final resolvedKey = _legacyKeyAliases[key] ?? key;
    final table = isKazakh ? _kk : _ru;
    return table[resolvedKey] ?? _ru[resolvedKey] ?? key;
  }

  String format(String key, Map<String, Object?> values) {
    var value = t(key);
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return value;
  }

  String translateKnownMessage(String message) {
    if (!isKazakh) return message;
    const known = <String, String>{
      'Нет соединения с сервером. Проверьте интернет.':
          'Сервермен байланыс жоқ. Интернетті тексеріңіз.',
      'Сервер не ответил вовремя. Попробуйте ещё раз.':
          'Сервер уақытында жауап бермеді. Қайталап көріңіз.',
      'Сервис временно недоступен. Попробуйте позже.':
          'Қызмет уақытша қолжетімсіз. Кейінірек қайталап көріңіз.',
      'Слишком много попыток. Подождите немного и попробуйте снова.':
          'Әрекет тым көп. Біраз күтіп, қайтадан көріңіз.',
      'Временный пароль истёк. Попросите администратора выдать новый.':
          'Уақытша құпиясөздің мерзімі аяқталды. Әкімшіден жаңасын сұраңыз.',
      'Аккаунт курьера заблокирован или отключён.':
          'Курьер аккаунты бұғатталған немесе өшірілген.',
      'Вход по паролю не настроен. Обратитесь к администратору.':
          'Құпиясөзбен кіру бапталмаған. Әкімшіге хабарласыңыз.',
      'Временный пароль уже был изменён. Войдите с новым паролем.':
          'Уақытша құпиясөз өзгертілген. Жаңа құпиясөзбен кіріңіз.',
      'Новый пароль должен содержать не менее 8 символов.':
          'Жаңа құпиясөз кемінде 8 таңбадан тұруы керек.',
      'Пароль слишком простой. Придумайте более надёжный пароль.':
          'Құпиясөз тым қарапайым. Сенімдірек құпиясөз таңдаңыз.',
      'Новый пароль должен отличаться от временного.':
          'Жаңа құпиясөз уақытша құпиясөзден өзгеше болуы керек.',
      'Проверьте введённые данные и попробуйте снова.':
          'Енгізілген деректерді тексеріп, қайтадан көріңіз.',
      'Неверный номер телефона или пароль.':
          'Телефон нөмірі немесе құпиясөз қате.',
      'Сервер вернул некорректный ответ. Попробуйте позже.':
          'Сервер қате жауап қайтарды. Кейінірек қайталап көріңіз.',
      'Не удалось выполнить вход. Попробуйте ещё раз.':
          'Кіру мүмкін болмады. Қайталап көріңіз.',
    };
    return known[message] ?? t('error.generic');
  }

  static String _normalize(String? language) => language == 'kk' ? 'kk' : 'ru';

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}

const Map<String, String> _ru = {
  'common.retry': 'Повторить',
  'common.cancel': 'Отмена',
  'common.back': 'Назад',
  'common.save': 'Сохранить',
  'common.refresh': 'Обновить',
  'error.generic': 'Не удалось выполнить действие. Попробуйте ещё раз.',
  'error.network': 'Нет соединения с сервером. Проверьте интернет.',
  'error.timeout': 'Сервер не ответил вовремя.',
  'error.session': 'Сессия истекла. Войдите заново.',
  'error.forbidden': 'Действие недоступно для этого аккаунта.',
  'nav.home': 'Главная',
  'nav.orders': 'Заказы',
  'nav.finance': 'Финансы',
  'nav.profile': 'Профиль',
  'auth.title': 'Вход для курьера',
  'auth.subtitle':
      'Введите номер телефона и пароль, который выдал администратор JETKIZ.',
  'auth.password': 'Пароль',
  'auth.signIn': 'Войти',
  'auth.agree': 'Я принимаю ',
  'auth.offer': 'Пользовательское соглашение',
  'auth.offerOpenFailed': 'Не удалось открыть пользовательское соглашение.',
  'auth.changePasswordTitle': 'Смените временный пароль',
  'auth.changePasswordSubtitle':
      'Для безопасности создайте новый постоянный пароль.',
  'auth.newPassword': 'Новый пароль',
  'auth.repeatPassword': 'Повторите пароль',
  'auth.changePassword': 'Сменить пароль',
  'auth.passwordMismatch': 'Пароли не совпадают.',
  'auth.passwordTooShort': 'Пароль должен содержать не менее 8 символов.',
  'home.greeting': 'Привет, {name}',
  'home.courier': 'Курьер',
  'home.shift': 'Рабочая смена JETKIZ',
  'home.today': 'Сегодня',
  'home.orders': 'Заказов',
  'home.delivered': 'Доставлено',
  'home.earned': 'Заработано сегодня',
  'home.activeOrder': 'Активный заказ',
  'home.order': 'Заказ',
  'home.orderNumber': 'Заказ №{number}',
  'home.income': 'Ваш доход: {amount} ₸',
  'home.openOrder': 'Открыть заказ',
  'home.online': 'Вы на линии',
  'home.offline': 'Вы оффлайн',
  'home.goOnline': 'Выйти на линию',
  'home.goOffline': 'Выйти с линии',
  'home.onlineHint': 'GPS активен для назначения и доставки',
  'home.offlineHint': 'Выйдите на линию, чтобы получать заказы',
  'home.onlineSuccess': 'Вы на линии. Геолокация активна.',
  'home.offlineSuccess': 'Вы оффлайн.',
  'home.cannotOffline': 'Нельзя уйти оффлайн, пока есть активный заказ.',
  'orders.title': 'Заказы',
  'orders.today': 'Сегодня',
  'orders.week': '7 дней',
  'orders.month': '30 дней',
  'orders.custom': 'Период',
  'orders.pickPeriod': 'Выберите период',
  'orders.empty': 'Заказов за выбранный период нет',
  'orders.active': 'Активный заказ',
  'orders.history': 'История',
  'orders.open': 'Открыть',
  'orders.pickupAction': 'Забрал',
  'orders.deliverAction': 'Доставлен',
  'orders.confirmPickup':
      'Убедитесь, что вы забрали заказ №{number} из ресторана и что заказ хорошо упакован.',
  'orders.confirmDelivery':
      'Убедитесь, что вы передаёте заказ №{number} по нужному адресу и правильному получателю.',
  'orders.checked': 'Проверил',
  'orders.deliveredButton': 'Доставлено',
  'orders.pickedSuccess': 'Заказ №{number} забран из ресторана',
  'orders.deliveredSuccess': 'Заказ №{number} доставлен',
  'details.title': 'Заказ №{number}',
  'details.restaurant': 'Ресторан',
  'details.client': 'Клиент',
  'details.call': 'Позвонить',
  'details.route': 'Маршрут в 2GIS',
  'details.items': 'Состав заказа',
  'details.comment': 'Комментарий клиента',
  'details.leaveAtDoor': 'Оставить у двери',
  'details.income': 'Ваш доход',
  'details.status': 'Статус',
  'details.noPhone': 'Телефон не указан',
  'details.noAddress': 'Адрес не указан',
  'details.callFailed': 'Не удалось открыть звонок',
  'details.routeFailed': 'Не удалось открыть маршрут в 2GIS',
  'details.actionUnavailable': 'Для этого статуса действие недоступно',
  'finance.title': 'Финансы',
  'finance.today': 'Сегодня',
  'finance.yesterday': 'Вчера',
  'finance.week': '7 дней',
  'finance.month': '30 дней',
  'finance.custom': 'Период',
  'finance.accrued': 'Начислено',
  'finance.pending': 'К выплате',
  'finance.paid': 'Выплачено',
  'finance.delivered': 'Доставок',
  'finance.history': 'Операции',
  'finance.empty': 'Операций за период нет',
  'profile.title': 'Профиль',
  'profile.orders': 'Заказы',
  'profile.status': 'Статус',
  'profile.online': 'Онлайн',
  'profile.offline': 'Оффлайн',
  'profile.management': 'Управление',
  'profile.language': 'Язык',
  'profile.notifications': 'Уведомления',
  'profile.offer': 'Пользовательское соглашение',
  'profile.privacy': 'Политика конфиденциальности',
  'profile.version': 'Версия {version}',
  'profile.logout': 'Выйти',
  'profile.logoutTitle': 'Выйти из аккаунта?',
  'profile.logoutBody':
      'Статус станет оффлайн, геолокация и push-регистрация этого устройства будут остановлены.',
  'profile.activeDelivery':
      'Сначала завершите активную доставку, затем выйдите.',
  'profile.photoUpdated': 'Фото обновлено',
  'profile.photoFormat': 'Выберите изображение JPG, PNG или WEBP.',
  'profile.photoTooLarge': 'Файл слишком большой. Максимальный размер — 5 МБ.',
  'profile.photoRateLimit': 'Слишком много попыток загрузки. Попробуйте позже.',
  'profile.pageOpenFailed': 'Не удалось открыть страницу.',
  'profile.settingsSaveFailed': 'Не удалось сохранить настройку.',
  'notifications.title': 'Уведомления',
  'notifications.markAll': 'Прочитать все',
  'notifications.empty': 'Новых уведомлений нет',
  'notifications.default': 'Уведомление',
  'status.READY': 'Готов к выдаче',
  'status.ON_THE_WAY': 'В пути',
  'status.DELIVERED': 'Доставлен',
  'status.CANCELED': 'Отменён',
  'status.CANCELLED': 'Отменён',
  'status.ACCEPTED': 'Принят',
  'status.COOKING': 'Готовится',
};

const Map<String, String> _kk = {
  'common.retry': 'Қайталау',
  'common.cancel': 'Бас тарту',
  'common.back': 'Артқа',
  'common.save': 'Сақтау',
  'common.refresh': 'Жаңарту',
  'error.generic': 'Әрекетті орындау мүмкін болмады. Қайталап көріңіз.',
  'error.network': 'Сервермен байланыс жоқ. Интернетті тексеріңіз.',
  'error.timeout': 'Сервер уақытында жауап бермеді.',
  'error.session': 'Сессия аяқталды. Қайта кіріңіз.',
  'error.forbidden': 'Бұл әрекет осы аккаунтқа қолжетімсіз.',
  'nav.home': 'Басты бет',
  'nav.orders': 'Тапсырыстар',
  'nav.finance': 'Қаржы',
  'nav.profile': 'Профиль',
  'auth.title': 'Курьерге кіру',
  'auth.subtitle':
      'Телефон нөмірін және JETKIZ әкімшісі берген құпиясөзді енгізіңіз.',
  'auth.password': 'Құпиясөз',
  'auth.signIn': 'Кіру',
  'auth.agree': 'Мен ',
  'auth.offer': 'Пайдаланушы келісімін қабылдаймын',
  'auth.offerOpenFailed': 'Пайдаланушы келісімін ашу мүмкін болмады.',
  'auth.changePasswordTitle': 'Уақытша құпиясөзді өзгертіңіз',
  'auth.changePasswordSubtitle':
      'Қауіпсіздік үшін жаңа тұрақты құпиясөз жасаңыз.',
  'auth.newPassword': 'Жаңа құпиясөз',
  'auth.repeatPassword': 'Құпиясөзді қайталаңыз',
  'auth.changePassword': 'Құпиясөзді өзгерту',
  'auth.passwordMismatch': 'Құпиясөздер сәйкес емес.',
  'auth.passwordTooShort': 'Құпиясөз кемінде 8 таңбадан тұруы керек.',
  'home.greeting': 'Сәлем, {name}',
  'home.courier': 'Курьер',
  'home.shift': 'JETKIZ жұмыс ауысымы',
  'home.today': 'Бүгін',
  'home.orders': 'Тапсырыс',
  'home.delivered': 'Жеткізілді',
  'home.earned': 'Бүгінгі табыс',
  'home.activeOrder': 'Белсенді тапсырыс',
  'home.order': 'Тапсырыс',
  'home.orderNumber': '№{number} тапсырыс',
  'home.income': 'Сіздің табысыңыз: {amount} ₸',
  'home.openOrder': 'Тапсырысты ашу',
  'home.online': 'Сіз желідесіз',
  'home.offline': 'Сіз желіден тыссыз',
  'home.goOnline': 'Желіге шығу',
  'home.goOffline': 'Желіден шығу',
  'home.onlineHint': 'GPS тағайындау және жеткізу үшін қосулы',
  'home.offlineHint': 'Тапсырыс алу үшін желіге шығыңыз',
  'home.onlineSuccess': 'Сіз желідесіз. Геолокация қосулы.',
  'home.offlineSuccess': 'Сіз желіден тыссыз.',
  'home.cannotOffline': 'Белсенді тапсырыс бар кезде желіден шығуға болмайды.',
  'orders.title': 'Тапсырыстар',
  'orders.today': 'Бүгін',
  'orders.week': '7 күн',
  'orders.month': '30 күн',
  'orders.custom': 'Кезең',
  'orders.pickPeriod': 'Кезеңді таңдаңыз',
  'orders.empty': 'Таңдалған кезеңде тапсырыс жоқ',
  'orders.active': 'Белсенді тапсырыс',
  'orders.history': 'Тарих',
  'orders.open': 'Ашу',
  'orders.pickupAction': 'Тапсырысты алдым',
  'orders.deliverAction': 'Жеткіздім',
  'orders.confirmPickup':
      '№{number} тапсырысты мейрамханадан алғаныңызға және оның дұрыс қапталғанына көз жеткізіңіз.',
  'orders.confirmDelivery':
      '№{number} тапсырысты дұрыс мекенжайға және дұрыс алушыға беріп жатқаныңызға көз жеткізіңіз.',
  'orders.checked': 'Тексердім',
  'orders.deliveredButton': 'Жеткізілді',
  'orders.pickedSuccess': '№{number} тапсырыс мейрамханадан алынды',
  'orders.deliveredSuccess': '№{number} тапсырыс жеткізілді',
  'details.title': '№{number} тапсырыс',
  'details.restaurant': 'Мейрамхана',
  'details.client': 'Клиент',
  'details.call': 'Қоңырау шалу',
  'details.route': '2GIS бағыты',
  'details.items': 'Тапсырыс құрамы',
  'details.comment': 'Клиент пікірі',
  'details.leaveAtDoor': 'Есік алдына қалдыру',
  'details.income': 'Сіздің табысыңыз',
  'details.status': 'Мәртебе',
  'details.noPhone': 'Телефон көрсетілмеген',
  'details.noAddress': 'Мекенжай көрсетілмеген',
  'details.callFailed': 'Қоңырауды ашу мүмкін болмады',
  'details.routeFailed': '2GIS бағытын ашу мүмкін болмады',
  'details.actionUnavailable': 'Бұл мәртебеде әрекет қолжетімсіз',
  'finance.title': 'Қаржы',
  'finance.today': 'Бүгін',
  'finance.yesterday': 'Кеше',
  'finance.week': '7 күн',
  'finance.month': '30 күн',
  'finance.custom': 'Кезең',
  'finance.accrued': 'Есептелді',
  'finance.pending': 'Төленуге тиіс',
  'finance.paid': 'Төленді',
  'finance.delivered': 'Жеткізу',
  'finance.history': 'Операциялар',
  'finance.empty': 'Кезеңде операция жоқ',
  'profile.title': 'Профиль',
  'profile.orders': 'Тапсырыстар',
  'profile.status': 'Мәртебе',
  'profile.online': 'Онлайн',
  'profile.offline': 'Офлайн',
  'profile.management': 'Басқару',
  'profile.language': 'Тіл',
  'profile.notifications': 'Хабарламалар',
  'profile.offer': 'Пайдаланушы келісімі',
  'profile.privacy': 'Құпиялық саясаты',
  'profile.version': '{version} нұсқасы',
  'profile.logout': 'Шығу',
  'profile.logoutTitle': 'Аккаунттан шығу керек пе?',
  'profile.logoutBody':
      'Мәртебе офлайн болады, геолокация және осы құрылғының push тіркелуі тоқтатылады.',
  'profile.activeDelivery':
      'Алдымен белсенді жеткізуді аяқтап, содан кейін шығыңыз.',
  'profile.photoUpdated': 'Фото жаңартылды',
  'profile.photoFormat': 'JPG, PNG немесе WEBP суретін таңдаңыз.',
  'profile.photoTooLarge': 'Файл тым үлкен. Ең үлкен өлшемі — 5 МБ.',
  'profile.photoRateLimit':
      'Жүктеу әрекеті тым көп. Кейінірек қайталап көріңіз.',
  'profile.pageOpenFailed': 'Бетті ашу мүмкін болмады.',
  'profile.settingsSaveFailed': 'Баптауды сақтау мүмкін болмады.',
  'notifications.title': 'Хабарламалар',
  'notifications.markAll': 'Барлығын оқу',
  'notifications.empty': 'Жаңа хабарлама жоқ',
  'notifications.default': 'Хабарлама',
  'status.READY': 'Алуға дайын',
  'status.ON_THE_WAY': 'Жолда',
  'status.DELIVERED': 'Жеткізілді',
  'status.CANCELED': 'Бас тартылды',
  'status.CANCELLED': 'Бас тартылды',
  'status.ACCEPTED': 'Қабылданды',
  'status.COOKING': 'Дайындалып жатыр',
};
