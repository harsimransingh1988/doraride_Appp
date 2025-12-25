import 'package:cloud_firestore/cloud_firestore.dart';

typedef FirestoreOp<T> = Future<T> Function();

Future<T> fbTry<T>(String label, FirestoreOp<T> op) async {
  try {
    return await op();
  } on FirebaseException catch (e) {
    // ignore: avoid_print
    print('❌ Firestore FAIL [$label]: ${e.code} ${e.message}');
    rethrow;
  }
}
