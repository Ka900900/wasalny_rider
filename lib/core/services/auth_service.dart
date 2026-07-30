import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/utils/logger.dart';

/// Service responsible for all Firebase Authentication operations.
///
/// Wraps [FirebaseAuth] to provide a clean API for rider authentication
/// (Phone OTP), session management, and logout.
/// Mirrors the same pattern used in [waslny_captain].
class AuthService {
  /// Singleton pattern — use [AuthService.instance] everywhere.
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ──────────────────────────────────────────────
  // Streams
  // ──────────────────────────────────────────────

  /// A broadcast stream that emits the current [User] (or `null`) whenever the
  /// authentication state changes (sign-in, sign-out, token refresh).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ──────────────────────────────────────────────
  // Queries
  // ──────────────────────────────────────────────

  /// Returns `true` when a user is currently signed in to Firebase.
  bool get isLoggedIn => _auth.currentUser != null;

  /// Returns the currently signed-in user, or `null`.
  User? get currentUser => _auth.currentUser;

  /// Phone number of the currently signed-in user, or an empty string.
  String get currentPhoneNumber => currentUser?.phoneNumber ?? '';

  // ──────────────────────────────────────────────
  // Phone Authentication
  // ──────────────────────────────────────────────

  /// Starts phone-number verification for production Firebase Auth.
  Future<void> verifyPhoneNumber(
    String phone,
    void Function(String verificationId) onCodeSent,
    void Function(String error) onError,
  ) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
          } catch (e) {
            onError(_mapFirebaseError(e));
          }
        },
        verificationFailed: (FirebaseAuthException exception) {
          logError(
            'AuthService',
            'verificationFailed — Code: ${exception.code}, '
                'Message: ${exception.message}',
            exception,
          );
          onError(_mapFirebaseError(exception));
        },
        codeSent: (String verificationId, int? resendToken) {
          logInfo('AuthService', 'codeSent — Verification ID: $verificationId');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          onError('انتهت مهلة استرجاع الرمز تلقائيًا.');
        },
        timeout: const Duration(seconds: 60),
      );
    } on FirebaseAuthException catch (exception) {
      onError(_mapFirebaseError(exception));
    } catch (exception) {
      onError(exception.toString());
    }
  }

  /// Verifies the SMS code and signs in with Firebase.
  /// Returns the Firebase ID token on success.
  Future<String> verifyOTP(String verificationId, String smsCode) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'لم يتم إنشاء حساب Firebase بعد التحقق.',
        );
      }

      final firebaseToken = await user.getIdToken(true);
      if (firebaseToken == null || firebaseToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'token-error',
          message: 'فشل في استخراج Firebase ID Token.',
        );
      }

      return firebaseToken;
    } on FirebaseAuthException catch (exception) {
      throw FirebaseAuthException(
        code: exception.code,
        message: _mapFirebaseError(exception),
      );
    } catch (exception) {
      throw Exception('فشل التحقق من الرمز: $exception');
    }
  }

  /// Signs in with a phone credential produced by automatic verification.
  Future<UserCredential> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    final result = await _auth.signInWithCredential(credential);
    await result.user!.getIdToken(true);
    return result;
  }

  /// Returns the current Firebase ID Token.
  /// Throws if there is no signed-in user.
  Future<String> getIdToken({bool forceRefresh = true}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'No authenticated user found.',
      );
    }
    final token = await user.getIdToken(forceRefresh);
    if (token == null) {
      throw FirebaseAuthException(
        code: 'no-token',
        message: 'Failed to retrieve the ID token.',
      );
    }
    return token;
  }

  // ──────────────────────────────────────────────
  // Session Management
  // ──────────────────────────────────────────────

  /// Signs out from Firebase AND clears the app JWT from [ApiService].
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      logError('AuthService', 'signOut error: $e', e);
    }
    ApiService.instance.clearToken();
  }

  /// Exchange the Firebase ID token for the app's JWT via the backend.
  ///
  /// This is the crucial step that links Firebase Auth to our backend.
  /// The backend returns a JWT that [ApiService] stores and uses for
  /// all subsequent authenticated requests.
  Future<Map<String, dynamic>> exchangeFirebaseToken(
    String firebaseIdToken,
  ) async {
    logInfo('AuthService', 'Exchanging Firebase token for app JWT…');
    try {
      final result = await ApiService.instance.signInWithFirebase(
        firebaseIdToken,
      );
      logInfo('AuthService', '✅ Firebase token exchange succeeded');
      return result;
    } catch (e) {
      logError('AuthService', '❌ Firebase token exchange failed: $e', e);
      rethrow;
    }
  }

  // ──────────────────────────────────────────────
  // Error Mapping
  // ──────────────────────────────────────────────

  /// Maps Firebase exceptions to user-friendly Arabic messages.
  String _mapFirebaseError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-phone-number':
          return 'رقم الهاتف غير صالح. يرجى التحقق من الرقم.';
        case 'too-many-requests':
          return 'طلبات كثيرة جداً. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.';
        case 'network-request-failed':
          return 'تعذر الاتصال بالشبكة. تأكد من اتصالك بالإنترنت.';
        case 'session-expired':
          return 'انتهت صلاحية الجلسة. يرجى طلب رمز جديد.';
        case 'invalid-verification-code':
          return 'رمز التحقق غير صالح. يرجى المحاولة مرة أخرى.';
        case 'user-disabled':
          return 'تم تعطيل هذا الحساب. يرجى التواصل مع الدعم.';
        case 'user-not-found':
          return 'لم يتم العثور على حساب بهذا الرقم.';
        case 'cancelled':
          return 'تم إلغاء العملية.';
        default:
          return error.message ?? 'حدث خطأ في التحقق. يرجى المحاولة مرة أخرى.';
      }
    }
    return error.toString();
  }
}
