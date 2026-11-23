// Sign-in (Google, via Firebase) and access to the AI key stored in Firestore.
// Everything else in the app keeps working without signing in.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class Account extends ChangeNotifier {
  bool ready = false;
  String? error;
  User? get user => ready ? FirebaseAuth.instance.currentUser : null;
  String? get email => user?.email;
  bool get signedIn => user != null;
  String? _key;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      ready = true;
      FirebaseAuth.instance.authStateChanges().listen((_) {
        _key = null;
        notifyListeners();
      });
    } catch (e) {
      error = 'Couldn’t start the online features: $e';
    }
    notifyListeners();
  }

  Future<bool> signIn() async {
    if (!ready) return false;
    try {
      final p = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
      await FirebaseAuth.instance.signInWithProvider(p);
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Sign-in didn’t finish: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    _key = null;
    notifyListeners();
  }

  /// The Anthropic key, readable only by allowed accounts (Firestore rules).
  Future<String?> aiKey() async {
    if (_key != null) return _key;
    if (!signedIn) return null;
    try {
      final d = await FirebaseFirestore.instance.doc('config/ai').get();
      final k = d.data()?['anthropicKey'];
      if (k is String && k.trim().isNotEmpty) _key = k.trim();
    } catch (e) {
      error = 'This account can’t use the AI yet. Ask Cooper to add your email.';
      notifyListeners();
    }
    return _key;
  }
}

final account = Account();
