import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide language (English / Arabic) with a persisted choice.
/// Listen to [instance] to rebuild on change; use [tr] for strings.
class Lang extends ChangeNotifier {
  Lang._();
  static final Lang instance = Lang._();

  String _code = 'en';
  String get code => _code;
  bool get isAr => _code == 'ar';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _code = p.getString('homzy_lang') ?? 'en';
  }

  Future<void> set(String code) async {
    if (code == _code) return;
    _code = code;
    final p = await SharedPreferences.getInstance();
    await p.setString('homzy_lang', code);
    notifyListeners();
  }

  Future<void> toggle() => set(isAr ? 'en' : 'ar');

  String t(String key) => _strings[key]?[_code] ?? _strings[key]?['en'] ?? key;
}

/// Shorthand: tr('home') -> current-language string.
String tr(String key) => Lang.instance.t(key);

const Map<String, Map<String, String>> _strings = {
  // Bottom nav
  'nav_home': {'en': 'Home', 'ar': 'الرئيسية'},
  'nav_projects': {'en': 'Projects', 'ar': 'المشاريع'},
  'nav_chat': {'en': 'Chat', 'ar': 'المحادثة'},
  'nav_saved': {'en': 'Saved', 'ar': 'المحفوظة'},
  'nav_profile': {'en': 'Profile', 'ar': 'حسابي'},

  // Home
  'home_sub': {'en': 'Your Home Guide', 'ar': 'دليلك لبيتك'},
  'continue_title': {'en': 'Continue your journey', 'ar': 'كمّل رحلتك'},
  'continue_sub': {
    'en': 'Chat with Homzy to find a home that fits your budget, area and needs.',
    'ar': 'اتكلم مع Homzy عشان تلاقي بيت يناسب ميزانيتك ومنطقتك واحتياجك.'
  },
  'start_chatting': {'en': 'Start chatting', 'ar': 'ابدأ المحادثة'},
  'how_help': {'en': 'How can we help?', 'ar': 'نقدر نساعدك إزاي؟'},
  'rent_home': {'en': 'Rent a home', 'ar': 'إيجار'},
  'buy_property': {'en': 'Buy a property', 'ar': 'تمليك'},
  'sheikh_zayed': {'en': 'Sheikh Zayed', 'ar': 'الشيخ زايد'},
  'october': {'en': '6th of October', 'ar': 'السادس من أكتوبر'},

  // Chat
  'chat_hint': {'en': 'Type your message…', 'ar': 'اكتب رسالتك…'},
  'save_chat': {'en': 'Save chat', 'ar': 'احفظ المحادثة'},
  'server_settings': {'en': 'Server settings', 'ar': 'إعدادات السيرفر'},
  'sign_in_to_save': {'en': 'Sign in to save chats.', 'ar': 'سجّل الدخول عشان تحفظ المحادثات.'},
  'nothing_to_save': {'en': 'Nothing to save yet — start chatting first.', 'ar': 'مفيش حاجة تتحفظ — ابدأ المحادثة الأول.'},
  'saved_ok': {'en': 'Saved to your account ✓', 'ar': 'اتحفظت في حسابك ✓'},

  // Auth
  'welcome_back': {'en': 'Welcome back — sign in', 'ar': 'أهلاً بعودتك — سجّل دخول'},
  'create_account': {'en': 'Create your account', 'ar': 'اعمل حسابك'},
  'full_name': {'en': 'Full name', 'ar': 'الاسم بالكامل'},
  'email': {'en': 'Email', 'ar': 'البريد الإلكتروني'},
  'password': {'en': 'Password', 'ar': 'كلمة السر'},
  'sign_up': {'en': 'Sign up', 'ar': 'إنشاء حساب'},
  'sign_in': {'en': 'Sign in', 'ar': 'تسجيل الدخول'},
  'continue_google': {'en': 'Continue with Google', 'ar': 'المتابعة بحساب Google'},
  'have_account': {'en': 'Already have an account? Sign in', 'ar': 'عندك حساب؟ سجّل دخول'},
  'new_here': {'en': 'New here? Create an account', 'ar': 'جديد هنا؟ اعمل حساب'},
  'enter_valid_email': {'en': 'Enter a valid email', 'ar': 'اكتب بريد صحيح'},
  'password_min': {'en': 'At least 6 characters', 'ar': '٦ حروف على الأقل'},

  // Profile
  'profile': {'en': 'Profile', 'ar': 'حسابي'},
  'saved_chats': {'en': 'Saved chats', 'ar': 'المحادثات المحفوظة'},
  'saved_chats_sub': {'en': 'Your conversations are synced to your account.', 'ar': 'محادثاتك متزامنة مع حسابك.'},
  'cloud_sync': {'en': 'Cloud sync', 'ar': 'مزامنة سحابية'},
  'cloud_sync_sub': {'en': 'Log in on any device to restore your data.', 'ar': 'سجّل دخول من أي جهاز وترجع بياناتك.'},
  'sign_out': {'en': 'Sign out', 'ar': 'تسجيل الخروج'},
  'role_user': {'en': 'Customer', 'ar': 'مستخدم'},
  'role_broker': {'en': 'Broker', 'ar': 'سمسار / بروكر'},
  'my_account': {'en': 'My account', 'ar': 'حسابي'},
  'edit_profile': {'en': 'Edit profile', 'ar': 'تعديل البيانات'},
  'save': {'en': 'Save', 'ar': 'حفظ'},
  'saved_done': {'en': 'Saved ✓', 'ar': 'اتحفظ ✓'},
  'change_photo': {'en': 'Change photo', 'ar': 'تغيير الصورة'},
  'delete_account': {'en': 'Delete account', 'ar': 'حذف الحساب'},
  'delete_confirm': {'en': 'Permanently delete your account and all your data? This cannot be undone.', 'ar': 'تحذف حسابك وكل بياناتك نهائيًا؟ الإجراء ده مش هيتراجع.'},
  'cancel': {'en': 'Cancel', 'ar': 'إلغاء'},
  'open_saved_chats': {'en': 'My saved chats', 'ar': 'محادثاتي المحفوظة'},

  // Saved
  'no_saved': {'en': 'No saved chats yet.\nTap the 🔖 in a chat to save it.', 'ar': 'مفيش محادثات محفوظة.\nدوس على 🔖 في المحادثة عشان تحفظها.'},

  // Projects / catalog
  'projects_title': {'en': 'Projects', 'ar': 'المشاريع'},
  'no_projects': {'en': 'No projects yet.', 'ar': 'مفيش مشاريع لسه.'},
  'unit_types': {'en': 'Unit types & prices', 'ar': 'أنواع الوحدات والأسعار'},
  'payment_plan': {'en': 'Payment', 'ar': 'طريقة الدفع'},
  'about_developer': {'en': 'About the developer', 'ar': 'عن المطوّر'},
  'track_record': {'en': 'Track record', 'ar': 'سابقة الأعمال'},
  'amenities': {'en': 'Amenities', 'ar': 'المميزات'},
  'brochure': {'en': 'Brochure', 'ar': 'البروشور'},
  'video': {'en': 'Video', 'ar': 'فيديو'},
  'delivery': {'en': 'Delivery', 'ar': 'التسليم'},
  'down_payment': {'en': 'Down payment', 'ar': 'المقدم'},
  'from_price': {'en': 'From', 'ar': 'يبدأ من'},
  'ask_homzy': {'en': 'Ask Homzy about this', 'ar': 'اسأل Homzy عن ده'},
  'search_projects': {'en': 'Search by project or location…', 'ar': 'ابحث باسم المشروع أو المنطقة…'},
  'filter_area': {'en': 'Location', 'ar': 'المنطقة'},
  'filter_type': {'en': 'Unit type', 'ar': 'نوع الوحدة'},
  'filter_delivery': {'en': 'Delivery', 'ar': 'التسليم'},
  'filter_all': {'en': 'All', 'ar': 'الكل'},
  'clear_filters': {'en': 'Clear', 'ar': 'مسح'},
  'results_count': {'en': 'result(s)', 'ar': 'نتيجة'},
  'type_apartment': {'en': 'Apartment', 'ar': 'شقة'},
  'type_studio': {'en': 'Studio', 'ar': 'استوديو'},
  'type_duplex': {'en': 'Duplex', 'ar': 'دوبلكس'},
  'type_penthouse': {'en': 'Penthouse', 'ar': 'بنتهاوس'},
  'type_villa': {'en': 'Villa', 'ar': 'فيلا'},
  'type_townhouse': {'en': 'Townhouse', 'ar': 'تاون هاوس'},
  'type_twinhouse': {'en': 'Twinhouse', 'ar': 'توين هاوس'},
  'type_chalet': {'en': 'Chalet', 'ar': 'شاليه'},
  'type_hotel apartment': {'en': 'Hotel apartment', 'ar': 'شقة فندقية'},

  // Onboarding (role)
  'onb_title': {'en': 'Tell us about you', 'ar': 'عرّفنا عن نفسك'},
  'onb_sub': {'en': 'This helps Homzy serve you better.', 'ar': 'ده بيساعد Homzy يخدمك أحسن.'},
  'onb_i_am': {'en': 'I am a…', 'ar': 'أنا…'},
  'onb_user_title': {'en': 'Customer', 'ar': 'مستخدم'},
  'onb_user_desc': {'en': 'Looking to rent or buy a home.', 'ar': 'بدور على إيجار أو تمليك.'},
  'onb_broker_title': {'en': 'Broker', 'ar': 'سمسار / بروكر'},
  'onb_broker_desc': {'en': 'I work in real estate.', 'ar': 'بشتغل في العقارات.'},
  'onb_phone': {'en': 'Mobile number', 'ar': 'رقم الموبايل'},
  'onb_company': {'en': 'Company name', 'ar': 'اسم الشركة'},
  'onb_continue': {'en': 'Continue', 'ar': 'متابعة'},
  'onb_phone_required': {'en': 'Please enter your mobile number', 'ar': 'من فضلك اكتب رقم موبايلك'},
  'onb_company_required': {'en': 'Please enter your company name', 'ar': 'من فضلك اكتب اسم الشركة'},
  'onb_choose_role': {'en': 'Please choose Customer or Broker', 'ar': 'اختار مستخدم ولا بروكر'},

  // Marketplace nav + home
  'nav_listings': {'en': 'My listings', 'ar': 'إعلاناتي'},
  'nav_favorites': {'en': 'Favorites', 'ar': 'المفضلة'},
  'nav_more': {'en': 'More', 'ar': 'المزيد'},
  'greeting_hi': {'en': 'Hi', 'ar': 'مرحباً'},
  'home_help_today': {'en': 'How can we help today?', 'ar': 'إزاي نقدر نساعدك النهاردة؟'},
  'search_nl_hint': {'en': 'Type your request in natural language…', 'ar': 'اكتب طلبك باللغة الطبيعية…'},
  'search_nl_example': {'en': 'e.g. apartment in New Cairo under 4M · 3 beds', 'ar': 'مثال: شقة في التجمع أقل من ٤ مليون · ٣ غرف'},
  'recent_searches': {'en': 'Recent searches', 'ar': 'عمليات بحث سابقة'},
  'search_with_homzy': {'en': 'Search with Homzy', 'ar': 'ابحث مع Homzy'},
  'discover_home': {'en': 'Discover your ideal home, easily and smartly', 'ar': 'اكتشف بيتك المثالي بسهولة وذكاء'},
  'start_now': {'en': 'Start now', 'ar': 'ابدأ الآن'},

  // Search results + cards
  'search_results': {'en': 'Search results', 'ar': 'نتائج البحث'},
  'flt_filter': {'en': 'Filter', 'ar': 'فلتر'},
  'flt_price': {'en': 'Price', 'ar': 'السعر'},
  'flt_size': {'en': 'Size', 'ar': 'المساحة'},
  'flt_more': {'en': 'More', 'ar': 'المزيد'},
  'no_results': {'en': 'No properties match your search.', 'ar': 'مفيش عقارات مطابقة لبحثك.'},

  // Listing detail
  'featured': {'en': 'Featured', 'ar': 'مميز'},
  'desc_label': {'en': 'Description', 'ar': 'الوصف'},
  'contact_owner': {'en': 'Contact owner', 'ar': 'تواصل مع المعلن'},
  'whatsapp': {'en': 'WhatsApp', 'ar': 'واتساب'},
  'view_location': {'en': 'View location', 'ar': 'شوف الموقع'},
  'location_label': {'en': 'Location', 'ar': 'الموقع'},
  'nearby_places': {'en': 'Nearby places', 'ar': 'الأماكن القريبة'},
  'beds_short': {'en': 'beds', 'ar': 'غرف'},
  'baths_short': {'en': 'baths', 'ar': 'حمام'},
  'floor_short': {'en': 'floor', 'ar': 'طابق'},

  // Favorites
  'favorites_title': {'en': 'Favorites', 'ar': 'المفضلة'},
  'no_favorites': {'en': 'No saved properties yet.', 'ar': 'مفيش عقارات محفوظة لسه.'},

  // My listings + add
  'my_listings_title': {'en': 'My listings', 'ar': 'إعلاناتي'},
  'add_new_listing': {'en': 'Add new listing', 'ar': 'أضف عقار جديد'},
  'add_property': {'en': 'Add property', 'ar': 'أضف عقار'},
  'st_active': {'en': 'Active', 'ar': 'نشط'},
  'st_pending': {'en': 'Under review', 'ar': 'قيد المراجعة'},
  'st_inactive': {'en': 'Inactive', 'ar': 'غير نشط'},
  'tab_all': {'en': 'All', 'ar': 'الكل'},
  'basic_info': {'en': 'Basic information', 'ar': 'المعلومات الأساسية'},
  'add_photos': {'en': 'Add property photos', 'ar': 'أضف صور العقار'},
  'lst_title': {'en': 'Title', 'ar': 'عنوان الإعلان'},
  'property_type': {'en': 'Property type', 'ar': 'نوع العقار'},
  'choose_area': {'en': 'Area', 'ar': 'المنطقة'},
  'enter_price': {'en': 'Price', 'ar': 'السعر'},
  'lst_beds': {'en': 'Bedrooms', 'ar': 'غرف'},
  'lst_baths': {'en': 'Bathrooms', 'ar': 'حمامات'},
  'lst_floor': {'en': 'Floor', 'ar': 'الطابق'},
  'lst_size': {'en': 'Size (m²)', 'ar': 'المساحة (م²)'},
  'lst_address': {'en': 'Address', 'ar': 'العنوان التفصيلي'},
  'lst_desc': {'en': 'Description', 'ar': 'الوصف'},
  'for_sale': {'en': 'For sale', 'ar': 'تمليك'},
  'for_rent': {'en': 'For rent', 'ar': 'إيجار'},
  'publish': {'en': 'Publish', 'ar': 'نشر الإعلان'},
  'next_step': {'en': 'Next', 'ar': 'التالي'},
  'published_ok': {'en': 'Listing published ✓', 'ar': 'اتنشر الإعلان ✓'},
  'delete_listing': {'en': 'Delete listing', 'ar': 'حذف الإعلان'},
  'title_required': {'en': 'Enter a title', 'ar': 'اكتب عنوان'},

  // Messages
  'messages_title': {'en': 'Messages', 'ar': 'الرسائل'},
  'no_messages': {'en': 'No conversations yet.', 'ar': 'مفيش محادثات لسه.'},
  'message_hint': {'en': 'Type a message…', 'ar': 'اكتب رسالة…'},

  // More / profile menu
  'more_title': {'en': 'More', 'ar': 'المزيد'},
  'menu_profile': {'en': 'Profile', 'ar': 'الملف الشخصي'},
  'menu_my_data': {'en': 'My data', 'ar': 'بياناتي'},
  'menu_settings': {'en': 'App settings', 'ar': 'إعدادات التطبيق'},
  'language': {'en': 'Language', 'ar': 'اللغة'},
  'menu_valuation': {'en': 'Property valuation', 'ar': 'تقييم عقار'},

  // Valuation
  'val_title': {'en': 'Property valuation', 'ar': 'تقييم عقار'},
  'val_sub': {
    'en': 'Estimate a fair resale price from comparable units on the market.',
    'ar': 'قدّر سعر بيع عادل لعقارك بناءً على وحدات مشابهة في السوق.'
  },
  'val_cta': {'en': 'Estimate price', 'ar': 'قدّر السعر'},
  'val_estimate': {'en': 'Estimated price', 'ar': 'السعر التقديري'},
  'val_range': {'en': 'Range', 'ar': 'النطاق'},
  'val_comps': {'en': 'comparables', 'ar': 'وحدة مشابهة'},
  'val_based_on': {'en': 'Based on units like:', 'ar': 'مبني على وحدات زي:'},
  'val_disclaimer': {
    'en': 'A market estimate from current asking prices — not an official appraisal.',
    'ar': 'تقدير سوقي من الأسعار المعروضة حاليًا — مش تقييم رسمي.'
  },
  'val_need_size': {'en': 'Enter the size in m²', 'ar': 'اكتب المساحة بالمتر'},
  'val_not_enough': {
    'en': 'Not enough comparable units for this area/type yet.',
    'ar': 'مفيش وحدات مشابهة كفاية للمنطقة/النوع ده لسه.'
  },
  'finishing_label': {'en': 'Finishing', 'ar': 'التشطيب'},
  'optional': {'en': 'Optional', 'ar': 'اختياري'},
  'val_src_resale': {
    'en': 'Based on real resale asking prices (RE/MAX).',
    'ar': 'مبني على أسعار بيع فعلية (RE/MAX).'
  },
  'val_src_pf': {
    'en': 'Based on PropertyFinder resale prices.',
    'ar': 'مبني على أسعار PropertyFinder (مراجعة).'
  },
  'val_src_catalog': {
    'en': 'Based on primary-market catalog prices.',
    'ar': 'مبني على أسعار الكتالوج (بيع أوّلي).'
  },
  'menu_messages': {'en': 'Messages', 'ar': 'الرسائل'},
  'menu_projects': {'en': 'Compounds', 'ar': 'الكومباوندات'},
  'menu_terms': {'en': 'Terms & conditions', 'ar': 'الشروط والأحكام'},
  'menu_privacy': {'en': 'Privacy policy', 'ar': 'سياسة الخصوصية'},

  // Broker / user mode switch
  'new_chat': {'en': 'New chat', 'ar': 'محادثة جديدة'},
  'broker_mode': {'en': 'Broker mode', 'ar': 'وضع البروكر'},
  'broker_mode_sub': {
    'en': 'List your own properties and manage them.',
    'ar': 'اعرض عقاراتك وتحكّم فيها.'
  },
  'mode_switched_broker': {'en': 'Broker mode on', 'ar': 'وضع البروكر اتفعّل'},
  'mode_switched_user': {'en': 'User mode on', 'ar': 'وضع المستخدم اتفعّل'},
  'browse_search_hint': {
    'en': 'Search by area, type or keyword…',
    'ar': 'ابحث بالمنطقة أو النوع أو كلمة…'
  },
};
