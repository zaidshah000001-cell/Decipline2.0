class GoogleSignInAccount {
  String get id => '';
  String? get displayName => null;
  String get email => '';
  Future> get authHeaders async => {};
  Future<void> clearAuthCache() async {}
}

class GoogleSignIn {
  GoogleSignIn({String? clientId, List<String>? scopes});
  GoogleSignIn.standard({List<String>? scopes});
  GoogleSignInAccount? get currentUser => null;
  Future<GoogleSignInAccount?> signIn() async => null;
  Future<GoogleSignInAccount?> signInSilently() async => null;
  Future<GoogleSignInAccount?> signOut() async => null;
}
