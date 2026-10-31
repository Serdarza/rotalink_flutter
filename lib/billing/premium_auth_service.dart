import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

String obfuscatedPremiumAccountId(String uid) {
  if (uid.isEmpty) throw ArgumentError.value(uid, 'uid');
  return base64Url
      .encode(sha256.convert(utf8.encode(uid)).bytes)
      .replaceAll('=', '');
}

/// The user closed the store account sheet.
class PremiumSignInCanceled implements Exception {
  const PremiumSignInCanceled();
}

/// Optional account identity for future server-verified Premium rights.
/// Existing Rotalink browsing and legacy Pro access never require sign-in.
class PremiumAuthService {
  PremiumAuthService._();

  static final PremiumAuthService instance = PremiumAuthService._();

  /// Firebase web client (client_type 3). Android needs it to mint an ID token.
  static const _serverClientId =
      '409913824071-tgg4fj1ce17evm0hg58peg4qftqidhc7.apps.googleusercontent.com';
  Future<void>? _googleInitialization;

  Future<void> _ready() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  }

  Stream<User?> get userChanges async* {
    await _ready();
    yield* FirebaseAuth.instance.authStateChanges();
  }

  User? get currentUser =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;

  Future<UserCredential> signInWithGoogle() async {
    await _ready();
    _googleInitialization ??= GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId,
    );
    await _googleInitialization;
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('Google ile giriş bu cihazda kullanılamıyor.');
    }
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const PremiumSignInCanceled();
      }
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw StateError('Google girişi bu kurulumun imzasıyla eşleşmiyor.');
      }
      throw StateError('Google ile giriş tamamlanamadı.');
    }
    final credential = await _firebaseFromGoogle(account);
    if (credential == null) throw StateError('Google hesabı doğrulanamadı.');
    return credential;
  }

  /// Links the phone's store account so the receipt can be recognized later.
  /// Android uses the Google account. iOS uses the Apple account.
  /// Returning visitors skip the account sheet. There is no Rotalink form.
  Future<void> ensureAccountForPurchase() async {
    await _ready();
    final existing = currentUser;
    if (existing != null && !existing.isAnonymous) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await signInWithApple();
      return;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _ensureGoogleAccount();
      return;
    }
    throw StateError('Pro satın alma bu cihazda kullanılamıyor.');
  }

  Future<void> _ensureGoogleAccount() async {
    _googleInitialization ??= GoogleSignIn.instance.initialize(
      serverClientId: _serverClientId,
    );
    await _googleInitialization;
    try {
      final silent = GoogleSignIn.instance.attemptLightweightAuthentication();
      if (silent != null) {
        final account = await silent;
        if (account != null &&
            await _firebaseFromGoogle(account, retry: true) != null) {
          return;
        }
      }
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw StateError('Google girişi bu kurulumun imzasıyla eşleşmiyor.');
      }
    }
    await signInWithGoogle();
  }

  /// Returns null only when [retry] is set and this attempt can be replaced
  /// by an interactive sign-in. The billing sheet is never opened here.
  Future<UserCredential?> _firebaseFromGoogle(
    GoogleSignInAccount account, {
    bool retry = false,
  }) async {
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      if (retry) return null;
      throw StateError('Google hesabı doğrulanamadı.');
    }
    try {
      return await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on FirebaseAuthException catch (error) {
      developer.log(
        'Firebase girişi reddedildi: ${error.code}',
        name: 'PremiumAuth',
      );
      if (retry) return null;
      rethrow;
    }
  }

  Future<UserCredential> signInWithApple() async {
    await _ready();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw StateError('Apple ile giriş bu cihazda kullanılamıyor.');
    }
    try {
      return await FirebaseAuth.instance.signInWithProvider(
        AppleAuthProvider(),
      );
    } on FirebaseAuthException catch (error) {
      if (_storeSignInCanceled(error.code)) throw const PremiumSignInCanceled();
      throw StateError('Apple hesabı doğrulanamadı.');
    } on PlatformException catch (error) {
      if (_storeSignInCanceled(error.code)) throw const PremiumSignInCanceled();
      throw StateError('Apple hesabı doğrulanamadı.');
    }
  }

  bool _storeSignInCanceled(String code) =>
      code.toLowerCase().contains('cancel');

  Future<String> freshIdToken() async {
    await _ready();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Mağaza hesabı doğrulanamadı.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Hesap oturumu yenilenemedi.');
    }
    return token;
  }

  /// Passed to Google Play Billing as applicationUserName when checkout opens.
  /// The server compares this digest with the authenticated Firebase UID.
  String obfuscatedAccountId() {
    final uid = currentUser?.uid;
    if (uid == null || uid.isEmpty || currentUser?.isAnonymous == true) {
      throw StateError('Mağaza hesabı doğrulanamadı.');
    }
    return obfuscatedPremiumAccountId(uid);
  }

  Future<void> signOut() async {
    await _ready();
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb && _googleInitialization != null) {
      await GoogleSignIn.instance.signOut();
    }
  }

  /// In-app account removal is required when an account can be created.
  /// Store subscriptions are managed separately by the platform's store.
  Future<void> deleteAccount() async {
    await _ready();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await user.delete();
    if (!kIsWeb && _googleInitialization != null) {
      await GoogleSignIn.instance.signOut();
    }
  }
}
