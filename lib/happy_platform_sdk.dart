
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

  // Hadda waxaan haynaa hal Dio instance oo kaliya
  static Dio? _dio;
  static String? _apiKey;
  static String? _projectId;
  static RealtimeDatabase? _realtimeInstance;

  /// Initializes the Happy Platform SDK for a single project.
  /// This must be called once, typically in your `main.dart`.
  static void initialize({
    required String projectId,
    required String apiBaseUrl,
    required String apiKey,
  }) {
    if (_dio != null) {
      print("⚠️ Happy Platform SDK is already initialized.");
      return;
    }
    _apiKey = apiKey;
    _projectId = projectId;
    _dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        headers: {'X-API-Key': apiKey},
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    _dio!.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
    print("✅ Happy Platform SDK Initialized for project '$_projectId'.");
  }

  // Helper function si looga fogaado ku celcelin
  static Dio _getDioInstance() {
    if (_dio == null) {
      throw Exception('HappyPlatform not initialized. Please call HappyPlatform.initialize() first.');
    }
    return _dio!;
  }

  /// Returns an instance of the [Auth] service.
  static Auth auth() {
    if (_projectId == null) {
      throw Exception('HappyPlatform not initialized. Please call HappyPlatform.initialize() first.');
    }
    // Sii projectId si uu Auth u isticmaalo
    return Auth._(dio: _getDioInstance(), projectId: _projectId!);
  }

  /// Returns an instance of the [Firestore] service.
  static Firestore firestore() {
    final dio = _getDioInstance();
    final wsUrl = dio.options.baseUrl.replaceFirst('http', 'ws').replaceFirst('/api/v1', '');
    return Firestore(dio: dio, webSocketUrl: wsUrl);
  }

  /// Returns a persistent instance of the [RealtimeDatabase] service.
  static RealtimeDatabase realtimeDatabase() {
    if (_realtimeInstance != null) {
      return _realtimeInstance!;
    }
    
    final dio = _getDioInstance();
    final wsBaseUrl = dio.options.baseUrl.replaceFirst('http', 'ws').replaceFirst('/api/v1', '');
    final fullWsUrl = '$wsBaseUrl/ws?apiKey=$_apiKey';

    _realtimeInstance = RealtimeDatabase(wsUrl: fullWsUrl);
    return _realtimeInstance!;
  }
}

//==============================================================================
// Qaybta 2: Firestore (Qaybtan waa la hagaajiyay)
//==============================================================================
class Firestore {
  final Dio dio;
  final String webSocketUrl;

  Firestore({required this.dio, required this.webSocketUrl});

  CollectionReference<Map<String, dynamic>> collection(String collectionId) {
    return CollectionReference<Map<String, dynamic>>(
      dio: dio,
      path: collectionId,
      webSocketUrl: webSocketUrl,
    );
  }
}

class Query<T> {
  final Dio dio;
  final String path;
  final String webSocketUrl;
  final Map<String, dynamic> _queryParameters;
  final T Function(DocumentSnapshot<T> snapshot, SnapshotOptions? options)?
      fromFirestore;
  final Map<String, dynamic> Function(T value, SetOptions? options)?
      toFirestore;

  Query({
    required this.dio,
    required this.path,
    required this.webSocketUrl,
    Map<String, dynamic>? queryParameters,
    this.fromFirestore,
    this.toFirestore,
  }) : _queryParameters = queryParameters ?? {};

  Query<T> where(String field, {dynamic isEqualTo, dynamic isNotEqualTo}) {
    final newParams = Map<String, dynamic>.from(_queryParameters);
    List<String> whereClauses = List<String>.from(newParams['where'] ?? []);
    if (isEqualTo != null) whereClauses.add('$field,==,$isEqualTo');
    if (isNotEqualTo != null) whereClauses.add('$field,!=,$isNotEqualTo');
    newParams['where'] = whereClauses;
    return Query<T>(
        dio: dio,
        path: path,
        webSocketUrl: webSocketUrl,
        queryParameters: newParams,
        fromFirestore: fromFirestore,
        toFirestore: toFirestore);
  }

  Query<T> orderBy(String field, {bool descending = false}) {
    final newParams = Map<String, dynamic>.from(_queryParameters);
    newParams['orderBy'] = '$field,${descending ? 'desc' : 'asc'}';
    return Query<T>(
        dio: dio,
        path: path,
        webSocketUrl: webSocketUrl,
        queryParameters: newParams,
        fromFirestore: fromFirestore,
        toFirestore: toFirestore);
  }

  Query<T> limit(int count) {
    final newParams = Map<String, dynamic>.from(_queryParameters);
    newParams['limit'] = count;
    return Query<T>(
        dio: dio,
        path: path,
        webSocketUrl: webSocketUrl,
        queryParameters: newParams,
        fromFirestore: fromFirestore,
        toFirestore: toFirestore);
  }

  Future<QuerySnapshot<T>> get() async {
    try {
      final response = await dio.get('/firestore/collections/$path/documents',
          queryParameters: _queryParameters);
      return QuerySnapshot<T>.fromResponse(response, fromFirestore);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to get documents');
    }
  }
}

class CollectionReference<T> extends Query<T> {
  CollectionReference({
    required super.dio,
    required super.path,
    required super.webSocketUrl,
    super.fromFirestore,
    super.toFirestore,
  });

  DocumentReference<T> document(String documentId) {
    return DocumentReference<T>(
      dio: dio,
      collectionPath: path,
      documentId: documentId,
      webSocketUrl: webSocketUrl,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
  }

  // ✅✅✅ HALKAN WAA LA HAGAAJIYAY ✅✅✅
  /// Adds a new document to this collection with the given [data].
  Future<DocumentReference<T>> add(T data) async {
    final Map<String, dynamic> mapData;

    if (toFirestore != null) {
      // Habka 1: Haddii `withConverter` la isticmaalay, u beddel `Object` -> `Map`.
      mapData = toFirestore!(data, null);
    } else if (data is Map<String, dynamic>) {
      // Habka 2: Haddii aan `withConverter` la isticmaalin, hubi in xogtu tahay `Map`.
      mapData = data;
    } else {
      // Haddii kale, tuur qalad cad.
      throw Exception(
          'Cannot add typed data of type `${data.runtimeType}` without a `toFirestore` converter. '
          'Use .withConverter() on the collection reference, or provide a Map<String, dynamic>.');
    }

    try {
      final response = await dio.post('/firestore/collections/$path/documents',
          data: mapData);
      final newDocId = response.data['id'] as String;
      return DocumentReference<T>(
        dio: dio,
        collectionPath: path,
        documentId: newDocId,
        webSocketUrl: webSocketUrl,
        fromFirestore: fromFirestore,
        toFirestore: toFirestore,
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to create document');
    }
  }

  CollectionReference<R> withConverter<R>({
    required R Function(DocumentSnapshot<R> snapshot, SnapshotOptions? options)
        fromFirestore,
    required Map<String, dynamic> Function(R value, SetOptions? options)
        toFirestore,
  }) {
    return CollectionReference<R>(
      dio: dio,
      path: path,
      webSocketUrl: webSocketUrl,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
  }
}

class DocumentReference<T> {
  final Dio dio;
  final String collectionPath;
  final String documentId;
  final String webSocketUrl;
  final T Function(DocumentSnapshot<T>, SnapshotOptions?)? fromFirestore;
  final Map<String, dynamic> Function(T, SetOptions?)? toFirestore;

  DocumentReference({
    required this.dio,
    required this.collectionPath,
    required this.documentId,
    required this.webSocketUrl,
    this.fromFirestore,
    this.toFirestore,
  });

  String get id => documentId;
  String get _documentPath =>
      '/firestore/collections/$collectionPath/documents/$documentId';

  Future<DocumentSnapshot<T>> get() async {
    try {
      final response = await dio.get(_documentPath);
      return DocumentSnapshot<T>.fromResponse(response, fromFirestore);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return DocumentSnapshot<T>(
            id: documentId, dataMap: null, fromFirestore: fromFirestore);
      }
      throw _handleDioError(e, 'Failed to get document');
    }
  }

  // ✅✅✅ HALKAN WAA LA HAGAAJIYAY ✅✅✅
  /// Overwrites the document with the given [data].
  Future<void> set(T data, [SetOptions? options]) async {
    final Map<String, dynamic> mapData;

    if (toFirestore != null) {
      // Habka 1: Haddii `withConverter` la isticmaalay.
      mapData = toFirestore!(data, options);
    } else if (data is Map<String, dynamic>) {
      // Habka 2: Haddii xogtu tahay `Map` caadi ah.
      mapData = data;
    } else {
      // Haddii kale, tuur qalad.
      throw Exception(
          'Cannot set typed data of type `${data.runtimeType}` without a `toFirestore` converter. '
          'Use .withConverter() on the collection reference, or provide a Map<String, dynamic>.');
    }

    try {
      await dio.put(_documentPath, data: mapData);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to set document');
    }
  }

  /// Updates parts of the document with the given [data].
  Future<void> update(Map<String, Object?> data) async {
    try {
      await dio.patch(_documentPath, data: data);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to update document data');
    }
  }

  Future<void> delete() async {
    try {
      await dio.delete(_documentPath);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to delete document');
    }
  }

  Stream<DocumentSnapshot<T>> snapshots() {
    // ... (Koodhkaagii hore ee qaybtan waa sax)
    final streamController = StreamController<DocumentSnapshot<T>>();
    late WebSocketChannel channel;
    void connect() {
      try {
        final wsPath = '$webSocketUrl$_documentPath';
        channel = WebSocketChannel.connect(Uri.parse(wsPath));
        channel.stream.listen(
          (message) {
            final data = json.decode(message) as Map<String, dynamic>;
            streamController
                .add(DocumentSnapshot<T>.fromMap(data, fromFirestore));
          },
          onDone: () => connect(),
          onError: (error) {
            streamController.addError(error);
            connect();
          },
        );
      } catch (e) {
        streamController.addError(e);
      }
    }

    connect();
    streamController.onCancel = () => channel.sink.close();
    return streamController.stream;
  }
}

class QuerySnapshot<T> {
  // ... (Koodhkaagii hore waa sax)
  final List<DocumentSnapshot<T>> docs;
  int get size => docs.length;
  bool get isEmpty => docs.isEmpty;

  QuerySnapshot({required this.docs});

  factory QuerySnapshot.fromResponse(Response response,
      T Function(DocumentSnapshot<T>, SnapshotOptions?)? fromFirestore) {
    final List<dynamic> dataList = (response.data as List<dynamic>?) ?? [];
    final docs = dataList
        .map((docData) => DocumentSnapshot<T>.fromMap(docData, fromFirestore))
        .toList();
    return QuerySnapshot<T>(docs: docs);
  }
}

class DocumentSnapshot<T> {
  // ... (Koodhkaagii hore waa sax)
  final String id;
  final Map<String, dynamic>? _dataMap;
  final T Function(DocumentSnapshot<T>, SnapshotOptions?)? _fromFirestore;

  DocumentSnapshot({
    required this.id,
    required Map<String, dynamic>? dataMap,
    T Function(DocumentSnapshot<T>, SnapshotOptions?)? fromFirestore,
  })  : _dataMap = dataMap,
        _fromFirestore = fromFirestore;

  bool get exists => _dataMap != null;

  T? data() {
    if (!exists) return null;
    if (_fromFirestore != null) {
      return _fromFirestore!(this, null);
    }
    return _dataMap as T;
  }

  factory DocumentSnapshot.fromMap(
    Map<String, dynamic> map,
    T Function(DocumentSnapshot<T>, SnapshotOptions?)? fromFirestore,
  ) {
    return DocumentSnapshot<T>(
      id: map['id'] as String? ?? '',
      dataMap: map['data'] as Map<String, dynamic>?,
      fromFirestore: fromFirestore,
    );
  }

  factory DocumentSnapshot.fromResponse(
    Response response,
    T Function(DocumentSnapshot<T>, SnapshotOptions?)? fromFirestore,
  ) {
    if (response.data is Map<String, dynamic>) {
      return DocumentSnapshot<T>.fromMap(
          response.data as Map<String, dynamic>, fromFirestore);
    }
    throw Exception("Unexpected response format from server. Expected a Map.");
  }
}

class SnapshotOptions {}

class SetOptions {}

HappyPlatformException _handleDioError(DioException e, String defaultMessage) {
  if (e.response != null && e.response!.data is Map) {
    final error = e.response!.data['error'];
    if (error != null) {
      return HappyPlatformException(error.toString());
    }
  }
  return HappyPlatformException(e.message ?? defaultMessage);
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

  // ✅ Waa inuu noqdaa mid public ah
  RealtimeDatabase({required this.wsUrl})
      : _streamController = StreamController.broadcast();

  // Xaaladda Isku Xirka
  RealtimeConnectionState _connectionState =
      RealtimeConnectionState.disconnected;
  final StreamController<RealtimeConnectionState> _connectionStateController =
      StreamController.broadcast();

  /// A stream that emits the current connection state.
  /// KANI WAA GETTER-KII MAQNAA EE AAD U BAAHNAYD
  Stream<RealtimeConnectionState> get onConnectionStateChanged =>
      _connectionStateController.stream;

  /// The current connection state.
  RealtimeConnectionState get connectionState => _connectionState;

  /// Returns a [DatabaseReference] for the given [path].

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
    goOnline();
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

/// Represents the connection state of the Realtime Database client.
enum RealtimeConnectionState {
  connected,
  connecting,
  disconnected,
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
  final String projectId;

  Auth._({required Dio dio, required this.projectId}) : _dio = dio;

  /// Registers a new user for the initialized project.
  Future<AuthUser> registerWithEmailAndPassword({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/projects/$projectId/register',
        data: {'full_name': fullName, 'email': email, 'password': password},
      );
      return AuthUser.fromJson(response.data);
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  /// Signs in a user for the initialized project.
  Future<AuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/projects/$projectId/login',
        data: {'email': email, 'password': password},
      );
      return AuthUser.fromJson(response.data['user'] ?? response.data);
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  /// Fetches all public user profiles for the initialized project.
  Future<List<AuthUser>> fetchAllUsers() async {
    try {
      final response = await _dio.get('/projects/$projectId/users/public');
      final List<dynamic> data = response.data ?? [];
      return data.map((json) => AuthUser.fromJson(json)).toList();
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }


   // ✅✅✅ FUNCTION CUSUB: UPDATE PROFILE (ISTICMAALAHA LAFTIISA) ✅✅✅
  /// Updates the profile of the currently authenticated user.
  ///
  /// Provide only the fields you want to change.
  /// To change the password, you must provide the [currentPassword].
  Future<AuthUser> updateProfile({
    String? fullName,
    String? email,
    String? currentPassword,
    String? newPassword,
  }) async {
    // Diyaari xogta la dirayo
    final Map<String, dynamic> data = {};
    if (fullName != null) data['full_name'] = fullName;
    if (email != null) data['email'] = email;
    if (currentPassword != null) data['current_password'] = currentPassword;
    if (newPassword != null) data['new_password'] = newPassword;

    if (data.isEmpty) {
      throw AuthException("No update information provided.");
    }

    try {
      // Endpoint-kani wuxuu u baahan yahay in user-ku uu authenticated yahay
      final response = await _dio.put(
        '/projects/$projectId/user/profile', // Tusaale endpoint
        data: data,
      );
      return AuthUser.fromJson(response.data);
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  // ✅✅✅ FUNCTION CUSUB: DELETE ACCOUNT (ISTICMAALAHA LAFTIISA) ✅✅✅
  /// Permanently deletes the account of the currently authenticated user.
  ///
  /// This action is irreversible. It requires the user's current password
  /// for security verification.
  Future<void> deleteAccount({required String currentPassword}) async {
    try {
      await _dio.post(
        '/projects/$projectId/user/delete', // Tusaale endpoint
        data: {'password': currentPassword},
      );
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

// Waa fiican tahay inaad lahaato exception u gaar ah SDK-ga
// Qaybta 5: Error Handling (Sideedii hore)
class HappyPlatformException implements Exception {
  final String message;
  HappyPlatformException(this.message);
  @override
  String toString() => message;
}

