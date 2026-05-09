import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  AuthService._();
  static AuthService get instance => _instance;

  bool _anonymousSession = false;

  bool get isAnonymousSession => _anonymousSession || !kFirebaseEnabled;

  User? get currentUser =>
      kFirebaseEnabled ? FirebaseAuth.instance.currentUser : null;

  String? get displayName =>
      currentUser?.displayName ?? currentUser?.email?.split('@').first;

  String? get email => currentUser?.email;

  String get initials {
    final name = displayName ?? '';
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Stream<User?> get authStateChanges => kFirebaseEnabled
      ? FirebaseAuth.instance.authStateChanges()
      : Stream.value(null);

  // Call once at startup (only when Firebase is enabled).
  Future<void> initGoogleSignIn() async {
    if (!kFirebaseEnabled) return;
    await GoogleSignIn.instance.initialize();
  }

  Future<void> signInWithGoogle() async {
    if (!kFirebaseEnabled) throw Exception('Firebase not configured yet.');
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await FirebaseAuth.instance.signInWithCredential(credential);
    _anonymousSession = false;
  }

  Future<void> signInWithEmail(String email, String password) async {
    if (!kFirebaseEnabled) throw Exception('Firebase not configured yet.');
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    _anonymousSession = false;
  }

  Future<void> createAccount(String email, String password) async {
    if (!kFirebaseEnabled) throw Exception('Firebase not configured yet.');
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    _anonymousSession = false;
    await cred.user?.sendEmailVerification();
  }

  Future<void> sendPasswordReset(String email) async {
    if (!kFirebaseEnabled) throw Exception('Firebase not configured yet.');
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  void continueAnonymously() {
    _anonymousSession = true;
  }

  Future<void> signOut() async {
    _anonymousSession = false;
    if (!kFirebaseEnabled) return;
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
  }
}
