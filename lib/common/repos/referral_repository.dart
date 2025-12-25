// lib/common/repos/referral_repository.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'wallet_repository.dart';

/// Lightweight referral storage using SharedPreferences.
class ReferralRepository {
  static const _kPoints = 'ref_points';
  static const _kToken = 'ref_token';
  static const _kUsedCode = 'ref_used_code';   // <-- NEW: store which friend code was used once

  static const _kBaseLink =
      'https://doraride-af3ec.web.app'; // you can change later to doraride.com

  static const int pointsPerReferral = 10;
  static const int centsPerPoint = 10; // 1 point = $0.10

  final _uuid = const Uuid();

  /// Returns current points (0 if none)
  Future<int> getPoints() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kPoints) ?? 0;
  }

  /// Ensure a stable token for this user; returns the full referral link.
  /// Example result: https://doraride-af3ec.web.app/?code=ABCD1234
  Future<String> getOrCreateReferralLink() async {
    final p = await SharedPreferences.getInstance();

    var token = p.getString(_kToken);
    if (token == null || token.isEmpty) {
      // short token for clean link
      token = _uuid.v4().split('-').first;
      await p.setString(_kToken, token);
    }

    return '$_kBaseLink/?code=$token';
  }

  /// Read only the token (handy if you want to show / debug it)
  Future<String?> getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kToken);
  }

  /// Returns the friend code this device already used (if any).
  Future<String?> getUsedCode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUsedCode);
  }

  /// Call this when your app detects a NEW INSTALL / NEW ACCOUNT that used a referral code.
  ///
  /// - `code`: the referrer’s code (from URL or deep link)
  /// - Prevents:
  ///   - self reward (code == my own token)
  ///   - using more than one code (only first code gives reward)
  ///
  /// Returns:
  ///   `true`  → points awarded
  ///   `false` → nothing awarded (self or already used some code)
  Future<bool> redeemInstall(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return false;

    final p = await SharedPreferences.getInstance();
    final myToken = p.getString(_kToken);
    final usedCode = p.getString(_kUsedCode);

    // 1) already used some friend code before → no more rewards
    if (usedCode != null && usedCode.isNotEmpty) {
      return false;
    }

    // 2) prevent self reward (user opened their own link)
    if (myToken != null && myToken == cleanCode) {
      return false;
    }

    // 3) grant points
    await _addPoints(pointsPerReferral);

    // 4) remember that this device / account has used this friend code
    await p.setString(_kUsedCode, cleanCode);
    return true;
  }

  /// Internal: add points
  Future<void> _addPoints(int delta) async {
    final p = await SharedPreferences.getInstance();
    final current = p.getInt(_kPoints) ?? 0;
    await p.setInt(_kPoints, current + delta);
  }

  /// Convert [pointsToConvert] into wallet cents and deduct from points.
  /// Returns the number of cents credited.
  Future<int> convertPointsToWallet({
    required int pointsToConvert,
    required WalletRepository walletRepo,
  }) async {
    if (pointsToConvert <= 0) return 0;

    final p = await SharedPreferences.getInstance();
    final current = p.getInt(_kPoints) ?? 0;
    if (pointsToConvert > current) {
      throw Exception('Not enough points');
    }

    final cents = pointsToConvert * centsPerPoint; // 10 pts -> 100 cents = $1
    await p.setInt(_kPoints, current - pointsToConvert);

    await walletRepo.addMoney(cents, note: 'Referral conversion');
    return cents;
  }
}
