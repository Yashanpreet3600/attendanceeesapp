import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:async'; // Required for the Timer
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'supabase_config.dart';
import 'app_session.dart';
import 'student_dashboard.dart';
import 'faculity.dart';
import 'admin.dart';
import 'management_dashboard.dart';
import 'password_dialog.dart';
import 'notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Connect to Supabase (settings are in supabase_config.dart)
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseKey,
  );

  // Phone notifications (does nothing on web)
  await NotificationService.init();

  runApp(LoginApp());
}

class LoginApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login',
      // CHANGE 1: Start with SplashScreen instead of LoginScreen
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- NEW SPLASH SCREEN WIDGET ---
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // CHANGE 2: Wait 3 seconds, then navigate to LoginScreen
    Timer(Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => LoginScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Using your Brand Navy Blue color
      backgroundColor: const Color(0xFF002046),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo inside a white circle for better visibility
            Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Image.asset('assets/images/12.png', height: 100, width: 100),
            ),
            SizedBox(height: 200),
            Text(
              'Akal University',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42 ,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Value Based Education',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 32,
              ),
            ),
            SizedBox(height: 50),
            // Loading Indicator
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// --- YOUR EXISTING LOGIN SCREEN ---
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  // --- COLORS ---
  final Color kalgidharBlue = const Color(0xFF002046);
  final Color kalgidharTeal = const Color(0xFF00796B);
  // --------------

  String selectedRole = 'Student';
  bool rememberMe = true;
  String selectedLanguage = 'English';
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  final roleKeys = ['Student', 'Faculty', 'Admin', 'Management'];
  final languages = ['English', 'Punjabi', 'Hindi'];

  final Map<String, Map<String, String>> _localizedValues = {
    'English': {
      // Contemplate and reflect upon knowledge, and you will become a benefactor to others.
      'subtitle': 'True learning induces in the mind service to mankind.',
      'username': 'User Name',
      'password': 'Password',
      'remember': 'Remember me',
      'pref_lang': 'Preferred language',
      'login': 'Log In',
      'Student': 'Student',
      'Faculty': 'Faculty',
      'Teacher': 'Teacher',
      'empty_user': 'Please enter User Name',
      'empty_pass': 'Please enter Password',
      'user_hint': 'Roll No. or Staff ID',
      'not_found': 'No account found with this ID for the selected role. Check the ID and role, then try again.',
      'conn_error': 'Could not connect to the server. Check your internet connection and try again.',
      'Management': 'Management',
      'wrong_login': 'Wrong ID, password or role. Check them and try again.',
      'disabled': 'This account has been turned off. Please contact the management office.',
    },
    'Punjabi': {
      'subtitle': 'ਗਿਆਨ ਨੂੰ ਵਿਚਾਰੋ ਅਤੇ ਚਿੰਤਨ ਕਰੋ, ਅਤੇ ਤੁਸੀਂ ਦੂਜਿਆਂ ਦੇ ਪਰਉਪਕਾਰੀ ਬਣ ਜਾਓਗੇ।',
      'username': 'ਉਪਭੋਗਤਾ ਨਾਮ',
      'password': 'ਪਾਸਵਰਡ',
      'remember': 'ਮੈਨੂੰ ਯਾਦ ਰੱਖੋ',
      'pref_lang': 'ਪਸੰਦੀਦਾ ਭਾਸ਼ਾ',
      'login': 'ਲੌਗ ਇਨ',
      'Student': 'ਵਿਦਿਆਰਥੀ',
      'Faculty': 'ਫੈਕਲਟੀ',
      'Teacher': 'ਅਧਿਆਪਕ',
      'empty_user': 'ਕਿਰਪਾ ਕਰਕੇ ਉਪਭੋਗਤਾ ਨਾਮ ਦਰਜ ਕਰੋ',
      'empty_pass': 'ਕਿਰਪਾ ਕਰਕੇ ਪਾਸਵਰਡ ਦਰਜ ਕਰੋ',
      'user_hint': 'ਰੋਲ ਨੰਬਰ ਜਾਂ ਸਟਾਫ ID',
      'not_found': 'ਚੁਣੀ ਗਈ ਭੂਮਿਕਾ ਲਈ ਇਸ ID ਨਾਲ ਕੋਈ ਖਾਤਾ ਨਹੀਂ ਮਿਲਿਆ। ID ਅਤੇ ਭੂਮਿਕਾ ਦੀ ਜਾਂਚ ਕਰਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।',
      'conn_error': 'ਸਰਵਰ ਨਾਲ ਕਨੈਕਟ ਨਹੀਂ ਹੋ ਸਕਿਆ। ਆਪਣਾ ਇੰਟਰਨੈੱਟ ਕਨੈਕਸ਼ਨ ਜਾਂਚ ਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।',
      'Management': 'ਪ੍ਰਬੰਧਨ',
      'wrong_login': 'ਗਲਤ ID, ਪਾਸਵਰਡ ਜਾਂ ਭੂਮਿਕਾ। ਜਾਂਚ ਕਰਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।',
      'disabled': 'ਇਹ ਖਾਤਾ ਬੰਦ ਕਰ ਦਿੱਤਾ ਗਿਆ ਹੈ। ਕਿਰਪਾ ਕਰਕੇ ਪ੍ਰਬੰਧਨ ਦਫ਼ਤਰ ਨਾਲ ਸੰਪਰਕ ਕਰੋ।',
    },
    'Hindi': {
      'subtitle': 'ज्ञान पर चिंतन और मनन करें, और आप दूसरों के लिए परोपकारी बन जाएंगे।',
      'username': 'उपयोगकर्ता नाम',
      'password': 'पासवर्ड',
      'remember': 'मुझे याद रखें',
      'pref_lang': 'पसंदीदा भाषा',
      'login': 'लॉग इन',
      'Student': 'छात्र',
      'Faculty': 'संकाय',
      'Teacher': 'शिक्षक',
      'empty_user': 'कृपया उपयोगकर्ता नाम दर्ज करें',
      'empty_pass': 'कृपया पासवर्ड दर्ज करें',
      'user_hint': 'रोल नंबर या स्टाफ ID',
      'not_found': 'चुनी गई भूमिका के लिए इस ID से कोई खाता नहीं मिला। ID और भूमिका जांचकर फिर से कोशिश करें।',
      'conn_error': 'सर्वर से कनेक्ट नहीं हो सका। अपना इंटरनेट कनेक्शन जांचकर फिर से कोशिश करें।',
      'Management': 'प्रबंधन',
      'wrong_login': 'गलत ID, पासवर्ड या भूमिका। जांचकर फिर से कोशिश करें।',
      'disabled': 'यह खाता बंद कर दिया गया है। कृपया प्रबंधन कार्यालय से संपर्क करें।',
    },
  };

  String getTrans(String key) {
    return _localizedValues[selectedLanguage]?[key] ?? key;
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // --- LOGIN ---
  // Checks ID + role + password in Supabase (Phase 5).
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final result = await AppSession.signIn(
        loginId: usernameController.text,
        role: selectedRole.toLowerCase(), // 'student', 'faculty', 'admin', 'management'
        password: passwordController.text,
      );
      if (!mounted) return;

      if (result.user == null) {
        _showMessage(getTrans(result.failure == 'disabled' ? 'disabled' : 'wrong_login'));
        return;
      }

      // First login (or password was reset): ask for a new password
      if (result.mustChangePassword) {
        setState(() => _isLoading = false);
        await showChangePasswordDialog(context, firstLogin: true);
        if (!mounted) return;
      }

      final Widget dashboard;
      if (selectedRole == 'Student') {
        dashboard = StudentDashboard();
      } else if (selectedRole == 'Faculty') {
        dashboard = FacultyDashboard();
      } else if (selectedRole == 'Management') {
        dashboard = const ManagementDashboard();
      } else {
        dashboard = AdminDashboard();
      }

      passwordController.clear();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => dashboard),
      );
    } catch (e) {
      debugPrint('Login error: $e');
      if (mounted) _showMessage(_explainError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Turns a technical error into a message that says what to fix.
  // Setup problems are explained in English for the developer; the full
  // error is shown only while developing (debug mode).
  String _explainError(Object e) {
    if (supabaseUrl.contains('YOUR-PROJECT-ID') || supabaseKey.startsWith('YOUR-')) {
      return 'Supabase is not set up yet. Paste your Project URL and key into lib/supabase_config.dart, then stop and run the app again.';
    }
    if (!supabaseUrl.startsWith('https://') || !supabaseUrl.endsWith('.supabase.co')) {
      return 'The Project URL in lib/supabase_config.dart looks wrong. It should look like https://abcdefgh.supabase.co with nothing after .supabase.co.';
    }

    final details = e.toString();
    if (details.contains('app_login') || details.contains('PGRST202')) {
      return 'The database needs the Phase 5 update (passwords). Run supabase_phase5.sql in the Supabase SQL Editor, then try again.';
    }
    if (details.contains('PGRST205') || details.contains('schema cache') || details.contains('does not exist')) {
      return 'The database tables are missing. Run supabase_setup.sql in the Supabase SQL Editor, then try again.';
    }
    if (details.contains('Invalid API key') || details.contains('No API key') || details.contains('JWT')) {
      return 'Supabase rejected the key. Copy the publishable (or anon public) key again into lib/supabase_config.dart.';
    }

    final message = getTrans('conn_error');
    return kDebugMode ? '$message\n\nDetails: $details' : message;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: Colors.red[700],
        duration: const Duration(seconds: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // HEADER
              Container(
                color: kalgidharBlue,
                padding: EdgeInsets.all(16),
                width: double.infinity,
                child: Column(
                  children: [
                    Text(
                      // ਵਿਦਿਆ ਵੀਚਾਰੀ ਤਾਂ ਪਰਉਪਕਾਰੀ ॥
                      '',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      getTrans('subtitle'),
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
// Logo inside a white circle for better visibility
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Image.asset('assets/images/12.png', height: 100, width: 100),
              ),
              SizedBox(height: 50),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // USERNAME
                      TextFormField(
                        controller: usernameController,
                        decoration: InputDecoration(
                          labelText: getTrans('username'),
                          hintText: getTrans('user_hint'),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return getTrans('empty_user');
                          }
                          return null;
                        },
                      ),

                      SizedBox(height: 12),

                      // PASSWORD
                      TextFormField(
                        controller: passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: getTrans('password'),
                          border: OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return getTrans('empty_pass');
                          }
                          return null;
                        },
                      ),

                      SizedBox(height: 16),

                      // ROLES
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: roleKeys.map((roleKey) {
                          final isSelected = selectedRole == roleKey;
                          return ElevatedButton(
                            onPressed: () => setState(() => selectedRole = roleKey),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSelected ? kalgidharBlue : Colors.grey[300],
                              foregroundColor: isSelected ? Colors.white : Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            child: Text(getTrans(roleKey)),
                          );
                        }).toList(),
                      ),

                      SizedBox(height: 10),

                      // REMEMBER ME
                      Row(
                        children: [
                          Switch(
                            value: rememberMe,
                            activeColor: kalgidharTeal,
                            onChanged: (val) => setState(() => rememberMe = val),
                          ),
                          Text(getTrans('remember')),
                        ],
                      ),

                      // PREFERRED LANGUAGE
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            getTrans('pref_lang'),
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
                          ),
                          SizedBox(width: 10),
                          DropdownButton<String>(
                            value: selectedLanguage,
                            underline: Container(height: 2, color: kalgidharBlue),
                            onChanged: (val) => setState(() => selectedLanguage = val!),
                            items: languages.map((lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(lang),
                            )).toList(),
                          ),
                        ],
                      ),

                      SizedBox(height: 20),

                      // LOGIN BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kalgidharBlue,
                            disabledBackgroundColor: kalgidharBlue, // stays navy while loading
                            padding: EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  getTrans('login'),
                                  style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      SizedBox(height: 30),
                    ],
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