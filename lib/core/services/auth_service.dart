import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
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
  // Google Sign-In
  // ──────────────────────────────────────────────

  /// Signs in with Google, exchanges the credential with Firebase, obtains
  /// the Firebase ID Token, then sends it to the backend for the app JWT.
  ///
  /// Returns a map containing the app JWT plus the Google profile data
  /// (`displayName`, `email`, `photoUrl`, `uid`). Throws on any failure.
  ///
  /// **Web note:** On web, `GoogleSignIn.signIn()` is deprecated and does not
  /// reliably return an `idToken` (see `google_sign_in_web`). Instead, we use
  /// `FirebaseAuth.signInWithPopup()` which correctly uses the Google
  /// Identity Services (GIS) library and returns the idToken.
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      String idToken;
      String displayName;
      String email;
      String photoUrl;
      String uid;

      if (kIsWeb) {
        // ==========================================
        // WEB: Use Firebase Auth signInWithPopup
        // (GoogleSignIn.signIn() is deprecated on web
        //  and can't reliably provide an idToken)
        // ==========================================
        final GoogleAuthProvider provider = GoogleAuthProvider();
        final UserCredential result = await _auth.signInWithPopup(provider);
        final User? user = result.user;
        if (user == null) {
          throw FirebaseAuthException(
            code: 'user-null',
            message: 'لم يتم إنشاء حساب Firebase بعد التحقق من جوجل.',
          );
        }

        final token = await user.getIdToken(true);
        if (token == null || token.isEmpty) {
          throw FirebaseAuthException(
            code: 'no-id-token',
            message: 'فشل في الحصول على معرف Google ID Token.',
          );
        }
        idToken = token;
        displayName = user.displayName ?? '';
        email = user.email ?? '';
        photoUrl = user.photoURL ?? '';
        uid = user.uid;
      } else {
        // ==========================================
        // MOBILE (Android/iOS): Use GoogleSignIn
        // ==========================================
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          throw FirebaseAuthException(
            code: 'cancelled',
            message: 'تم إلغاء تسجيل الدخول بواسطة جوجل.',
          );
        }

        // 2. Obtain Google authentication details
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        if (googleAuth.idToken == null) {
          throw FirebaseAuthException(
            code: 'no-id-token',
            message: 'فشل في الحصول على معرف Google ID Token.',
          );
        }

        // 3. Create Firebase credential and sign in
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final UserCredential result = await _auth.signInWithCredential(
          credential,
        );
        final User? user = result.user;
        if (user == null) {
          throw FirebaseAuthException(
            code: 'user-null',
            message: 'لم يتم إنشاء حساب Firebase بعد التحقق من جوجل.',
          );
        }

        // 4. Get the Firebase ID Token
        final token = await user.getIdToken(true);
        if (token == null || token.isEmpty) {
          throw FirebaseAuthException(
            code: 'token-error',
            message: 'فشل في استخراج Firebase ID Token.',
          );
        }
        idToken = token;

        // 5. Extract Google profile data
        displayName = user.displayName ?? '';
        email = user.email ?? '';
        photoUrl = user.photoURL ?? '';
        uid = user.uid;
      }

      // ==========================================
      // Exchange Firebase Token → Backend JWT
      // ==========================================
      final loginResult = await ApiService.instance.signInWithFirebase(
        idToken,
        name: displayName,
        email: email,
        photoUrl: photoUrl,
      );

      return {
        'token': loginResult['token'],
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'uid': uid,
      };
    } on FirebaseAuthException {
      rethrow;
    } catch (exception) {
      throw Exception('فشل تسجيل الدخول بحساب جوجل: $exception');
    }
  }

  /// Disconnects the Google Sign-In session (useful for switching accounts).
  Future<void> disconnectGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    if (await googleSignIn.isSignedIn()) {
      await googleSignIn.disconnect();
    }
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
