import 'package:flutter/foundation.dart';

enum WalletTxnType { add, ridePayment, withdraw }
enum WalletTxnStatus { pending, success, failed }

@immutable
class WalletTransaction {
  final String id;
  final WalletTxnType type;
  final int amountCents; // store money in cents
  final DateTime createdAt;
  final WalletTxnStatus status;
  final String note;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.createdAt,
    required this.status,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'amountCents': amountCents,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'note': note,
      };

  factory WalletTransaction.fromJson(Map<String, dynamic> j) => WalletTransaction(
        id: j['id'] as String,
        type: WalletTxnType.values.firstWhere((e) => e.name == j['type']),
        amountCents: j['amountCents'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
        status: WalletTxnStatus.values.firstWhere((e) => e.name == j['status']),
        note: (j['note'] ?? '') as String,
      );
}

@immutable
class BankInfo {
  final String accountHolder;
  final String accountNumberMasked;
  final String ifscOrRouting; // IFSC / Routing / SWIFT etc.
  final String email;
  final String phone;

  const BankInfo({
    required this.accountHolder,
    required this.accountNumberMasked,
    required this.ifscOrRouting,
    required this.email,
    required this.phone,
  });

  Map<String, dynamic> toJson() => {
        'accountHolder': accountHolder,
        'accountNumberMasked': accountNumberMasked,
        'ifscOrRouting': ifscOrRouting,
        'email': email,
        'phone': phone,
      };

  factory BankInfo.fromJson(Map<String, dynamic> j) => BankInfo(
        accountHolder: j['accountHolder'] as String,
        accountNumberMasked: j['accountNumberMasked'] as String,
        ifscOrRouting: j['ifscOrRouting'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
      );
}
