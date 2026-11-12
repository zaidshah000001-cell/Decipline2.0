class FirebaseFirestore {}

class DocumentSnapshot {
  String get id => '';
  Map<String, dynamic>? data() => null;
  dynamic operator [](String key) => null;
}

class FieldValue {
  static dynamic arrayUnion(List<dynamic> elements) => elements;
  static dynamic arrayRemove(List<dynamic> elements) => elements;
  static dynamic delete() => null;
  static dynamic serverTimestamp() => DateTime.now();
}

class _DummyUser {
  String get uid => '';
  String? get email => null;
}

class FirebaseAuth {
  static final FirebaseAuth instance = FirebaseAuth();
  _DummyUser? get currentUser => null;
}

Future<FirebaseFirestore?> firebaseGetDBInstanceAnonymous() async => null;
Future<FirebaseFirestore?> firebaseGetDBInstance() async => null;
