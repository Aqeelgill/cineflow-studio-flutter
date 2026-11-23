import 'package:flutter/widgets.dart';

class AppI18n {
  static const supported = <Locale>[
    Locale('en', 'US'),
    Locale('en', 'GB'),
    Locale('de'),
    Locale('es'),
    Locale('fr'),
    Locale('ar'),
    Locale('ur'), // Roman Urdu
  ];

  static const Map<String, Map<String, String>> _t = {
    'en': {
      'app_title': 'CineFlow Studio',
      'tab_downloader': 'Universal Downloader',
      'tab_series': 'Series & Drama Watcher',
      'tab_leads': 'Lead Generator & Media Scraper',
      'tab_scheduler': 'Task Scheduler',
      'status': 'Status',
      'pause': 'Pause',
      'resume': 'Resume',
      'download_all': 'Download All',
      'help': 'Help',
      'ram': 'RAM',
      'eco': 'ECO',
      'category': 'Category',
      'language': 'Language',
      'ram_mode': 'RAM Mode',
      'bot_missing_token': 'Telegram bot token is missing in .env.',
      'bot_unauthorized': 'Unauthorized. This bot only responds to authorized users.',
      'bot_not_connected': 'Bot is not connected to the download manager.',
      'bot_ready': 'CineFlow bot is ready.',
      'edit_source': 'Edit Source / Proxy',
      'save': 'Save',
      'cancel': 'Cancel',
    },
    'en_GB': {
      'app_title': 'CineFlow Studio',
    },
    'de': {
      'app_title': 'CineFlow Studio',
      'tab_downloader': 'Universeller Downloader',
      'tab_series': 'Serien- & Drama-Watcher',
      'tab_leads': 'Lead-Generator & Media-Scraper',
      'tab_scheduler': 'Aufgabenplaner',
      'status': 'Status',
      'pause': 'Pause',
      'resume': 'Fortsetzen',
      'download_all': 'Alle herunterladen',
      'help': 'Hilfe',
      'ram': 'RAM',
      'category': 'Kategorie',
      'language': 'Sprache',
      'ram_mode': 'RAM-Modus',
      'bot_missing_token': 'Telegram-Bot-Token fehlt in .env.',
      'bot_unauthorized': 'Nicht autorisiert. Dieser Bot antwortet nur autorisierten Benutzern.',
      'bot_not_connected': 'Bot ist nicht mit dem Download-Manager verbunden.',
      'edit_source': 'Quelle / Proxy bearbeiten',
      'save': 'Speichern',
      'cancel': 'Abbrechen',
    },
    'es': {
      'tab_downloader': 'Descargador Universal',
      'tab_series': 'Visor de Series y Dramas',
      'tab_leads': 'Generador de Leads y Scraper',
      'tab_scheduler': 'Programador de Tareas',
      'status': 'Estado',
      'pause': 'Pausar',
      'resume': 'Reanudar',
      'download_all': 'Descargar todo',
      'help': 'Ayuda',
      'category': 'Categoría',
      'language': 'Idioma',
      'ram_mode': 'Modo RAM',
      'bot_missing_token': 'Falta el token del bot de Telegram en .env.',
      'bot_unauthorized': 'No autorizado. Este bot solo responde a usuarios autorizados.',
      'bot_not_connected': 'El bot no está conectado al administrador de descargas.',
      'edit_source': 'Editar origen / proxy',
      'save': 'Guardar',
      'cancel': 'Cancelar',
    },
    'fr': {
      'tab_downloader': 'Téléchargeur Universel',
      'tab_series': 'Séries et Dramas',
      'tab_leads': 'Générateur de Leads et Scraper',
      'tab_scheduler': 'Planificateur de tâches',
      'status': 'Statut',
      'pause': 'Pause',
      'resume': 'Reprendre',
      'download_all': 'Tout télécharger',
      'help': 'Aide',
      'category': 'Catégorie',
      'language': 'Langue',
      'ram_mode': 'Mode RAM',
      'bot_missing_token': 'Le jeton du bot Telegram manque dans .env.',
      'bot_unauthorized': 'Non autorisé. Ce bot répond uniquement aux utilisateurs autorisés.',
      'bot_not_connected': 'Le bot n’est pas connecté au gestionnaire de téléchargements.',
      'edit_source': 'Modifier source / proxy',
      'save': 'Enregistrer',
      'cancel': 'Annuler',
    },
    'ar': {
      'tab_downloader': 'أداة التنزيل الشاملة',
      'tab_series': 'عارض المسلسلات والدراما',
      'tab_leads': 'مولد العملاء وجامع الوسائط',
      'tab_scheduler': 'جدولة المهام',
      'status': 'الحالة',
      'pause': 'إيقاف مؤقت',
      'resume': 'استئناف',
      'download_all': 'تنزيل الكل',
      'help': 'مساعدة',
      'category': 'الفئة',
      'language': 'اللغة',
      'ram_mode': 'وضع الذاكرة',
      'bot_missing_token': 'رمز بوت تيليجرام مفقود في ملف .env.',
      'bot_unauthorized': 'غير مصرح. هذا البوت يستجيب فقط للمستخدمين المصرح لهم.',
      'bot_not_connected': 'البوت غير متصل بمدير التنزيل.',
      'edit_source': 'تعديل المصدر / البروكسي',
      'save': 'حفظ',
      'cancel': 'إلغاء',
    },
    'ur': { // Roman Urdu
      'tab_downloader': 'Universal Downloader',
      'tab_series': 'Series aur Drama Watcher',
      'tab_leads': 'Lead Generator aur Media Scraper',
      'tab_scheduler': 'Task Scheduler',
      'status': 'Status',
      'pause': 'Roko',
      'resume': 'Jari rakho',
      'download_all': 'Sab download karo',
      'help': 'Madad',
      'category': 'Category',
      'language': 'Zaban',
      'ram_mode': 'RAM Mode',
      'bot_missing_token': 'Telegram bot token .env mein mojood nahi hai.',
      'bot_unauthorized': 'Unauthorized. Ye bot sirf authorized users ko jawab deta hai.',
      'bot_not_connected': 'Bot download manager se connected nahi hai.',
      'edit_source': 'Source / Proxy badlein',
      'save': 'Save',
      'cancel': 'Cancel',
    },
  };

  static String localeKey(Locale l) {
    if (l.languageCode == 'en' && l.countryCode == 'GB') return 'en_GB';
    if (l.languageCode == 'en') return 'en';
    return l.languageCode;
  }

  static bool isRtl(Locale l) => l.languageCode == 'ar';

  static String t(String key, Locale locale) {
    final k = localeKey(locale);
    return _t[k]?[key] ?? _t['en']?[key] ?? key;
  }

  static Locale fromCode(String? code) {
    switch (code) {
      case 'en_GB': return const Locale('en', 'GB');
      case 'de': return const Locale('de');
      case 'es': return const Locale('es');
      case 'fr': return const Locale('fr');
      case 'ar': return const Locale('ar');
      case 'ur': return const Locale('ur');
      case 'en_US':
      default: return const Locale('en', 'US');
    }
  }

  static String codeOf(Locale l) => localeKey(l);
}
