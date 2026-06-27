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
};
