// lib/common/repos/wallet_repository.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/wallet_models.dart';

class WalletRepository {
  static const _kBalance = 'wallet_balance_cents';
  static const _kTxns = 'wallet_transactions';
  static const _kBank = 'wallet_bank_info';

  /// Keep history bounded so SharedPreferences doesn’t grow forever.
  static const int _kMaxTxnHistory = 200;

  final _uuid = const Uuid();

  /// Simple in-memory op-queue so balance + txns update atomically
  /// even if the user taps buttons quickly.
  Future<void> _op = Future.value();
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final next = _op.then((_) => task());
    _op = next.catchError((_) {}); // keep chain alive on errors
    return next;
  }

  // ------------------------------
  // Reads
  // ------------------------------
  Future<int> getBalanceCents() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kBalance) ?? 0;
  }

  Future<List<WalletTransaction>> getTransactions() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kTxns) ?? const <String>[];

    final parsed = <WalletTransaction>[];
    for (final s in raw) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        parsed.add(WalletTransaction.fromJson(map));
      } catch (_) {
        // skip malformed entry
      }
    }

    // newest first
    parsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return parsed;
  }

  // ------------------------------
  // Internal writers
  // ------------------------------
  Future<void> _saveTransactions(List<WalletTransaction> txns) async {
    final p = await SharedPreferences.getInstance();

    // Trim to max history
    final limited = txns.take(_kMaxTxnHistory).toList();

    final list =
        limited.map((t) => jsonEncode(t.toJson())).toList().cast<String>();
    await p.setStringList(_kTxns, list);
  }

  Future<void> _setBalance(int cents) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kBalance, cents);
  }

  // ------------------------------
  // Mutations (queued atomically)
  // ------------------------------

  /// Add money (top-up from card → wallet)
  Future<WalletTransaction> addMoney(
    int cents, {
    String note = 'Top-up',
  }) {
    return _enqueue<WalletTransaction>(() async {
      final balance = await getBalanceCents();
      final newBal = balance + cents;
      await _setBalance(newBal);

      final txn = WalletTransaction(
        id: _uuid.v4(),
        type: WalletTxnType.add,
        amountCents: cents,
        createdAt: DateTime.now(),
        status: WalletTxnStatus.success,
        note: note,
      );

      final txns = await getTransactions();
      txns.insert(0, txn);
      await _saveTransactions(txns);
      return txn;
    });
  }

  /// Credit ride payment to driver wallet
  Future<WalletTransaction> creditRidePayment(
    int cents, {
    String note = 'Ride payment',
  }) {
    return _enqueue<WalletTransaction>(() async {
      final balance = await getBalanceCents();
      await _setBalance(balance + cents);

      final txn = WalletTransaction(
        id: _uuid.v4(),
        type: WalletTxnType.ridePayment,
        amountCents: cents,
        createdAt: DateTime.now(),
        status: WalletTxnStatus.success,
        note: note,
      );

      final txns = await getTransactions();
      txns.insert(0, txn);
      await _saveTransactions(txns);
      return txn;
    });
  }

  /// OPTION B STYLE – USER SIDE:
  /// Only CREATE a withdrawal request (pending).
  /// Do NOT subtract from balance here.
  ///
  /// Later, your REAL backend/admin flow will:
  /// - subtract from the server balance
  /// - mark a server-side transaction as success.
  ///
  /// For now this gives you a local "pending" transaction
  /// that you can show in the Wallet UI.
  Future<WalletTransaction> requestWithdraw(
    int cents, {
    String note = 'Withdrawal requested',
  }) {
    return _enqueue<WalletTransaction>(() async {
      final balance = await getBalanceCents();

      // Optional UX check: don't allow request bigger than current balance.
      // (Server/admin will still do the final real check.)
      if (cents <= 0 || cents > balance) {
        throw Exception('Invalid withdraw amount');
      }

      final txn = WalletTransaction(
        id: _uuid.v4(),
        type: WalletTxnType.withdraw,
        amountCents: cents,
        createdAt: DateTime.now(),
        status: WalletTxnStatus.pending,
        note: note,
      );

      final txns = await getTransactions();
      txns.insert(0, txn);
      await _saveTransactions(txns);

      // NOTE: balance is NOT changed here (Option B).
      return txn;
    });
  }

  /// Old local "instant withdraw" (subtract immediately and mark success).
  /// You can:
  /// - keep this for dev / manual payouts, or
  /// - stop using it on the user side and only use `requestWithdraw`.
  Future<WalletTransaction> withdraw(int cents) {
    return _enqueue<WalletTransaction>(() async {
      final balance = await getBalanceCents();
      if (cents <= 0 || cents > balance) {
        throw Exception('Invalid withdraw amount');
      }

      final newBal = balance - cents;
      await _setBalance(newBal);

      final txn = WalletTransaction(
        id: _uuid.v4(),
        type: WalletTxnType.withdraw,
        amountCents: cents,
        createdAt: DateTime.now(),
        status: WalletTxnStatus.success,
        note: 'Payout to bank',
      );

      final txns = await getTransactions();
      txns.insert(0, txn);
      await _saveTransactions(txns);
      return txn;
    });
  }

  // ------------------------------
  // Bank info (used by Withdraw / Bank setup screens)
  // ------------------------------
  Future<void> saveBankInfo(BankInfo info) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBank, jsonEncode(info.toJson()));
  }

  Future<BankInfo?> getBankInfo() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kBank);
    if (s == null) return null;
    try {
      return BankInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------
  // Dev helper (optional)
  // ------------------------------
  Future<void> clearAllForDev() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kBalance);
    await p.remove(_kTxns);
    // keep bank info by default; uncomment if you want to clear it too:
    // await p.remove(_kBank);
  }
}
