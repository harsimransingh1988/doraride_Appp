import 'package:shared_preferences/shared_preferences.dart';

class AuthRepository {
  AuthRepository._();
  static final instance = AuthRepository._();

  static const _kPhoneVerified = 'phone_verified';
  static const _kPhoneNumber = 'phone_number';

  Future<bool> isPhoneVerified() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kPhoneVerified) ?? false;
    }

  Future<String?> getSavedPhone() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPhoneNumber);
  }

  /// Demo: “sends” OTP code 123456.
  /// In production, integrate Firebase/your SMS gateway here.
  Future<void> startPhoneVerification(String e164Phone) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPhoneNumber, e164Phone);
    // TODO: call your backend/SMS provider; we just simulate a delay.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Returns true if code matches the demo code.
  Future<bool> verifyOtp(String code) async {
    final ok = code.trim() == '123456';
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPhoneVerified, ok);
    return ok;
  }

  Future<void> clearPhoneVerification() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPhoneVerified);
  }
}
