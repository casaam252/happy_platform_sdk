library happy_platform_sdk;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

//==============================================================================
// Qaybta 1: Entry Point & Initialization
//==============================================================================

/// The main class for interacting with the Happy Platform SDK.
class HappyPlatform {
  static final HappyPlatform _instance = HappyPlatform._internal();
  factory HappyPlatform() => _instance;
  HappyPlatform._internal();

  static final Map<String, Dio> _dioInstances = {};
  static String? _apiBaseUrl;
  static final Map<String, RealtimeDatabase> _realtimeInstances = {};

  /// Initializes the Happy Platform SDK for one or more projects.
  /// This must be called once, typically in your `main.dart`.
  static void initialize({
    required Map<String, String> projects,
    required String apiBaseUrl,
  }) {
    if (_dioInstances.isNotEmpty) {
      print("⚠️ Happy Platform SDK is already initialized.");
      return;
    }
    _apiBaseUrl = apiBaseUrl;
    projects.forEach((projectName, apiKey) {
      final dio = Dio(
        BaseOptions(
          baseUrl: apiBaseUrl,
          headers: {'X-API-Key': apiKey},
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      dio.interceptors
          .add(LogInterceptor(responseBody: false, requestBody: true));
      _dioInstances[projectName] = dio;
    });
    print(
        "✅ Happy Platform SDK Initialized for ${projects.length} project(s).");
  }

  /// Returns an instance of the [Firestore] service for a specific project.
  /// If [projectName] is not provided, it defaults to 'default'.
  static Firestore firestore([String projectName = 'default']) {
    final dio = _dioInstances[projectName];
    if (dio == null) throw Exception('Project "$projectName" not initialized.');
    return Firestore(dio: dio);
  }

  /// Returns a persistent instance of the [RealtimeDatabase] service for a specific project.
  /// If [projectName] is not provided, it defaults to 'default'.
  static RealtimeDatabase realtimeDatabase([String projectName = 'default']) {
    if (_realtimeInstances.containsKey(projectName)) {
      final instance = _realtimeInstances[projectName]!;
      instance.goOnline(); // Hubi inuu `connected` yahay
      return instance;
    }

    final dio = _dioInstances[projectName];
    final apiKey = dio?.options.headers['X-API-Key'];
    if (_apiBaseUrl == null || apiKey == null) {
      throw Exception('Project "$projectName" not initialized.');
    }
    final wsUrl =
        _apiBaseUrl!.replaceFirst('http', 'ws').replaceFirst('/api/v1', '');

    final newInstance =
        RealtimeDatabase._internal(wsUrl: '$wsUrl/ws?apiKey=$apiKey');
    _realtimeInstances[projectName] = newInstance;
    return newInstance;
  }

  // ✅✅✅ QAYBTA CUSUB EE LAGU DARAY ✅✅✅
  /// Returns an instance of the [Auth] service for a specific project.
  /// This is used for managing users from a backend or admin panel, not for client-side login.
  /// If [projectName] is not provided, it defaults to 'default'.
  static Auth auth([String projectName = 'default']) {
    final dio = _dioInstances[projectName];
    if (dio == null) throw Exception('Project "$projectName" not initialized.');
    return Auth._(dio: dio);
  }
}

//==============================================================================
// Qaybta 2: Firestore
//==============================================================================

/// The entry point for all Firestore operations.
class Firestore {
  final Dio dio;
  Firestore({required this.dio});

  /// Returns a [CollectionReference] for the specified [collectionId].
  CollectionReference collection(String collectionId) {
    return CollectionReference(dio: dio, path: collectionId);
  }
}

/// A `Query` refers to a query across a collection of documents.
class Query {
  final Dio dio;
  final String path;
  final Map<String, dynamic> _queryParameters;

  Query({
    required this.dio,
    required this.path,
    Map<String, dynamic>? queryParameters,
  }) : _queryParameters = queryParameters ?? {};

  /// Creates a new query with an additional filter.
  Query where(
    String field, {
    dynamic isEqualTo,
    dynamic isNotEqualTo,
    dynamic isGreaterThan,
    dynamic isLessThan,
    dynamic isGreaterThanOrEqualTo,
    dynamic isLessThanOrEqualTo,
  }) {
    final newParams = Map<String, dynamic>.from(_queryParameters);
    List<String> whereClauses = List<String>.from(newParams['where'] ?? []);
    if (isEqualTo != null) whereClauses.add('$field,==,$isEqualTo');
    if (isNotEqualTo != null) whereClauses.add('$field,!=,$isNotEqualTo');
    if (isGreaterThan != null) whereClauses.add('$field,>,$isGreaterThan');
    if (isLessThan != null) whereClauses.add('$field,<,$isLessThan');
    if (isGreaterThanOrEqualTo != null)
      whereClauses.add('$field,>=,$isGreaterThanOrEqualTo');
    if (isLessThanOrEqualTo != null)
      whereClauses.add('$field,<=,$isLessThanOrEqualTo');
    newParams['where'] = whereClauses;
    return Query(dio: dio, path: path, queryParameters: newParams);
  }

  /// Creates a new query with an ordering constraint.
  Query orderBy(String field, {bool descending = false}) {
    final newParams = Map<String, dynamic>.from(_queryParameters);
    newParams['orderBy'] = '$field,${descending ? 'desc' : 'asc'}';
    return Query(dio: dio, path: path, queryParameters: newParams);
  }

  /// Creates a new query with a document limit.
  Query limit(int count) {
    final newParams = Map<String, dynamic>.from(_queryParameters);
    newParams['limit'] = count;
    return Query(dio: dio, path: path, queryParameters: newParams);
  }

  /// Executes the query and returns a [QuerySnapshot].
  Future<QuerySnapshot> get() async {
    try {
      final response = await dio.get(
        '/firestore/collections/$path/documents',
        queryParameters: _queryParameters,
      );
      return QuerySnapshot.fromResponse(response);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to get documents');
    }
  }
}

/// A `CollectionReference` is a `Query` that can also be used to add new documents.
class CollectionReference extends Query {
  CollectionReference({required super.dio, required super.path});

  /// Returns a [DocumentReference] for the specified [documentId].
  DocumentReference document(String documentId) {
    return DocumentReference(
        dio: dio, collectionPath: path, documentId: documentId);
  }

  /// Adds a new document with a server-generated ID to this collection.
  Future<DocumentReference> add(Map<String, dynamic> data) async {
    try {
      final response =
          await dio.post('/firestore/collections/$path/documents', data: data);
      final newDocId = response.data['id'];
      return DocumentReference(
          dio: dio, collectionPath: path, documentId: newDocId);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to create document');
    }
  }
}

/// A `DocumentReference` refers to a specific document in a collection.
class DocumentReference {
  final Dio dio;
  final String collectionPath;
  final String documentId;
  DocumentReference(
      {required this.dio,
      required this.collectionPath,
      required this.documentId});

  String get id => documentId;

  // ✅✅✅ CUSBOONAYSII UPDATE SI UU U NOQDO SET ✅✅✅
  // `set` wuxuu abuuraa document-ka haddii uusan jirin, wuu beddelaa haddii uu jiro.
  Future<void> set(Map<String, dynamic> data) async {
    try {
      // `PUT` wuxuu la mid yahay `set`
      await dio.put(
        '/firestore/collections/$collectionPath/documents/$documentId',
        data: data,
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to set document');
    }
  }
  // ✅✅✅ KANI WAA FUNCTION-KA SAXDA AH EE `GET` ✅✅✅
  /// Reads the data of the document.
  /// Throws an error if the document does not exist.
  Future<DocumentSnapshot> get() async {
    try {
      // Backend-kaagu waa inuu taageeraa GET hal document.
      final response = await dio
          .get('/firestore/collections/$collectionPath/documents/$documentId');

      // Hubi in jawaabtu tahay Map ka hor intaadan u gudbin fromMap
      if (response.data is Map<String, dynamic>) {
        return DocumentSnapshot.fromMap(response.data as Map<String, dynamic>);
      } else {
        throw Exception("Unexpected response format from server for get()");
      }
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to get document');
    }
  }

  Future<void> delete() async {
    try {
      await dio.delete(
          '/firestore/collections/$collectionPath/documents/$documentId');
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to delete document');
    }
  }

  Future<void> update(Map<String, dynamic> data) async {
    try {
      await dio.put(
        '/firestore/collections/$collectionPath/documents/$documentId',
        data: data,
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to update document');
    }
  }




   // ✅✅✅ KU SOO CELI FUNCTION-KAN CUSUB OO DHAN ✅✅✅
  /// Returns a [CollectionReference] to a sub-collection nested under this document.
  ///
  /// For example: `firestore.collection('posts').document('postId').collection('comments')`
  CollectionReference collection(String subCollectionId) {
    // Samee jidka cusub ee sub-collection-ka
    final newPath = '$collectionPath/$documentId/$subCollectionId';
    return CollectionReference(dio: dio, path: newPath);
  }

}


class QuerySnapshot {
  final List<DocumentSnapshot> docs;
  int get size => docs.length;
  bool get isEmpty => docs.isEmpty;
  QuerySnapshot({required this.docs});

  factory QuerySnapshot.fromResponse(Response response) {
    final List<dynamic> data = (response.data as List<dynamic>?) ?? [];
    final docs =
        data.map((docData) => DocumentSnapshot.fromMap(docData)).toList();
    return QuerySnapshot(docs: docs);
  }
}

class DocumentSnapshot {
  final String id;
  final Map<String, dynamic> data;
  DocumentSnapshot({required this.id, required this.data});

  factory DocumentSnapshot.fromMap(Map<String, dynamic> map) {
    return DocumentSnapshot(
      id: map['id'] as String? ?? '',
      data: map['data'] as Map<String, dynamic>? ?? {},
    );
  }
}

//==============================================================================
// Qaybta 3: Realtime Database
//==============================================================================

class RealtimeDatabase {
  final String wsUrl;
  WebSocketChannel? _channel;
  final StreamController<RealtimeSnapshot> _streamController;
  Timer? _reconnectTimer;
  bool _isConnected = false;

  RealtimeDatabase._internal({required this.wsUrl})
      : _streamController = StreamController.broadcast();

  void _connect() {
    if (_isConnected) return;
    print("🔌 [RTDB] Connecting to: $wsUrl");
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _reconnectTimer?.cancel(); // Jooji isku daygii hore ee reconnect

      _channel!.stream.listen(
        (message) {
          try {
            final decoded = json.decode(message);
            if (decoded['type'] == 'data' || decoded['type'] == 'update') {
              _streamController.add(RealtimeSnapshot.fromJson(decoded));
            }
          } catch (e) {
            _streamController
                .addError(Exception('Failed to parse server message: $e'));
          }
        },
        onDone: () {
          if (_isConnected) {
            _isConnected = false;
            _streamController.addError(Exception('Connection closed.'));
            _tryReconnect();
          }
        },
        onError: (error) {
          _isConnected = false;
          _streamController.addError(error);
          _tryReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _isConnected = false;
      _streamController.addError(Exception('Failed to connect: $e'));
      _tryReconnect();
    }
  }

  void _tryReconnect() {
    if (!_isConnected) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 5), () {
        print("🔄 [RTDB] Attempting to reconnect...");
        _connect();
      });
    }
  }

  DatabaseReference reference([String path = '/']) {
    return DatabaseReference(db: this, path: path);
  }

  void goOffline() {
    _isConnected = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void goOnline() {
    _connect();
  }
}

class DatabaseReference {
  final RealtimeDatabase db;
  final String path;

  DatabaseReference({required this.db, required this.path});

  Stream<RealtimeSnapshot> onValue() {
    _sendMessage({'type': 'subscribe', 'path': path});
    return db._streamController.stream
        .where((snapshot) => snapshot.path == path);
  }

  DatabaseReference push() {
    final newId = const Uuid().v4();
    return DatabaseReference(
        db: db, path: path == '/' ? newId : '$path/$newId');
  }

  Future<void> update(Map<String, dynamic> data) async {
    _sendMessage({'type': 'update', 'path': path, 'payload': data});
  }

  Future<void> set(dynamic data) async {
    _sendMessage({'type': 'set', 'path': path, 'payload': data});
  }

  Future<void> remove() async {
    await set(null);
  }

  void off() {
    _sendMessage({'type': 'unsubscribe', 'path': path});
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (db._channel != null) {
      db._channel!.sink.add(json.encode(message));
    }
  }
}

class RealtimeSnapshot {
  final String path;
  final dynamic value;

  RealtimeSnapshot({required this.path, this.value});

  factory RealtimeSnapshot.fromJson(Map<String, dynamic> json) {
    return RealtimeSnapshot(
      path: json['path'],
      value: json['payload'],
    );
  }
}

//==============================================================================
// ✅✅✅ QAYBTA 4: AUTH - OO SI BUUXDA DIB LOO HABEEYAY ✅✅✅
//==============================================================================

/// The entry point for all authentication operations for a project.
///
/// Use this class to:
/// - Register new users (`registerWithEmailAndPassword`).
/// - Sign in users (`signInWithEmailAndPassword`).
/// - Manage users if you have admin privileges (`admin`).
class Auth {
  final Dio _dio;
  Auth._({required Dio dio}) : _dio = dio;

  String get _projectId {
    // Si toos ah uga soo saar `projectId` URL-ka haddii loo baahdo
    // Laakiin habka ugu fiican waa in backend-ku ka garto API Key-ga.
    // Hadda, waxaan u qaadanaynaa inaan u baahanahay inaan ku darno `projectId` codsiyada.
    // Tani waxay u baahan tahay in la helo hab lagu helo.
    // Xalka ugu fudud: Waa inaan ku darnaa `projectId` marka la wacayo `auth()`
    // Laakiin aan ka dhigno mid fudud: backend-ku ha aqoonsado.
    return '';
  }

  /// Registers a new user with their email, password, and full name.
  ///
  /// This is a public method that any app user can call.
  /// Throws [AuthException] if registration fails.
  Future<AuthUser> registerWithEmailAndPassword({
    required String projectId, // <-- WAA IN LAGU DARAA
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      // ✅✅✅ ISTICMAAL JIDKA SAXDA AH EE BACKEND-KA ✅✅✅
      final response = await _dio.post(
        '/projects/$projectId/register',
        data: {
          'full_name': fullName,
          'email': email,
          'password': password,
        },
      );
      return AuthUser.fromJson(response.data);
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  /// Signs in a user with their email and password.
  ///
  /// Requires the `projectId`.
  /// Throws [AuthException] if sign-in fails.
  Future<AuthUser> signInWithEmailAndPassword({
    required String projectId, // <-- WAA IN LAGU DARAA
    required String email,
    required String password,
  }) async {
    try {
      // ✅✅✅ ISTICMAAL JIDKA SAXDA AH EE BACKEND-KA ✅✅✅
      final response = await _dio.post(
        '/projects/$projectId/login',
        data: {
          'email': email,
          'password': password,
        },
      );
      return AuthUser.fromJson(response.data['user'] ?? response.data);
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  // ✅✅✅ KU DAR FUNCTION-KAN CUSUB OO DHAN ✅✅✅
  /// Fetches a list of all public user profiles in the project.
  /// This is a public method that uses the initialized API Key.
  Future<List<AuthUser>> fetchAllUsers({required String projectId}) async {
    try {
      // Wuxuu la hadlayaa jidka public-ka ah ee aan backend-ka ka samaynay
      final response = await _dio.get('/projects/$projectId/users/public');
      final List<dynamic> data = response.data ?? [];
      return data.map((json) => AuthUser.fromJson(json)).toList();
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  /// Access admin-only functions for user management.
  ///
  /// **Important:** This should only be used in a secure server environment
  /// (like a backend server or admin panel) where you have a developer's
  /// authentication token. **Do not use this in a client-side application.**
  UserManagement admin({required String developerAuthToken}) {
    // Samee Dio instance cusub oo leh token-ka developer-ka
    final adminDio = Dio(BaseOptions(
        baseUrl: _dio.options.baseUrl,
        headers: {'Authorization': 'Bearer $developerAuthToken'}));
    return UserManagement._(dio: adminDio);
  }
}

/// A class for managing users with admin privileges.
class UserManagement {
  final Dio _dio;
  UserManagement._({required Dio dio}) : _dio = dio;

  /// Retrieves a list of all users in the project.
  Future<List<AuthUser>> listUsers(String projectId) async {
    try {
      final response = await _dio.get('/projects/$projectId/users');
      final List<dynamic> data = response.data ?? [];
      return data.map((json) => AuthUser.fromJson(json)).toList();
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  /// Updates a user's `fullName`.
  Future<AuthUser> updateUser({
    required String projectId,
    required String userId,
    required String newFullName,
  }) async {
    try {
      final response = await _dio.put(
        '/projects/$projectId/users/$userId',
        data: {'full_name': newFullName},
      );
      return AuthUser.fromJson(response.data);
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  /// Deletes a user by their unique [userId].
  Future<void> deleteUser({
    required String projectId,
    required String userId,
  }) async {
    try {
      await _dio.delete('/projects/$projectId/users/$userId');
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }
}

/// Represents a user in the Happy Platform authentication system.
class AuthUser {
  final String id;
  final String email;
  final String fullName;
  final String? photoUrl;
  final String provider;
  final DateTime? lastLogin;
  final DateTime createdAt;

  AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.photoUrl,
    required this.provider,
    this.lastLogin,
    required this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'],
      email: json['email'],
      fullName: json['full_name'],
      photoUrl: json['photo_url'],
      provider: json['provider'],
      lastLogin: json['last_login'] != null
          ? DateTime.parse(json['last_login'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

/// A custom exception for authentication-related errors.
/// Provides a clear, user-friendly error message.
class AuthException implements Exception {
  final String message;

  AuthException(this.message);

  factory AuthException.fromDioException(DioException e) {
    if (e.response != null && e.response!.data is Map) {
      final serverError = e.response!.data['error']?.toString();
      if (serverError != null) {
        return AuthException(serverError);
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AuthException(
          "Connection timed out. Please check your internet connection.");
    }
    if (e.type == DioExceptionType.unknown) {
      return AuthException(
          "Network error. Please check your internet connection and try again.");
    }
    return AuthException("An unexpected error occurred. Please try again.");
  }

  @override
  String toString() => message;
}
//==============================================================================
// Qaybta 5: Error Handling Helper (Hore ayuu u jiray, hadda waa qaybta 5-aad)
//==============================================================================

String _handleDioError(DioException e, String defaultMessage) {
  if (e.response != null && e.response!.data is Map) {
    return e.response!.data['error']?.toString() ?? defaultMessage;
  }
  return e.message ?? defaultMessage;
}
