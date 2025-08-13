library happy_platform_sdk;

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

//==============================================================================
// Qaybta 1: Entry Point & Initialization (WAAN FUDUDEEYAY OO ADKEEYAY)
//==============================================================================

/// The main class for interacting with the Happy Platform SDK.
class HappyPlatform {
  static final HappyPlatform _instance = HappyPlatform._internal();
  factory HappyPlatform() => _instance;
  HappyPlatform._internal();

  static Dio? _dio;
  static String? _projectId;
  
  /// Initializes the Happy Platform SDK.
  /// This must be called once before using any other SDK methods.
  static void initialize({
    required String projectId,
    required String apiBaseUrl,
    required String apiKey,
  }) {
    if (_dio != null) {
      print("⚠️ Happy Platform SDK is already initialized.");
      return;
    }
    _projectId = projectId;
    _dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        headers: {'X-API-Key': apiKey},
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    // Waxaad ku dari kartaa LogInterceptor halkan haddii aad u baahato debugging
    // _dio!.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
    print("✅ Happy Platform SDK Initialized for project '$_projectId'.");
  }

  static Dio _getDioInstance() {
    if (_dio == null || _projectId == null) {
      throw HappyPlatformException('SDK not initialized. Call HappyPlatform.initialize() first.');
    }
    return _dio!;
  }

  /// Returns an instance of the [Auth] service.
  static Auth auth() {
    return Auth._(dio: _getDioInstance(), projectId: _projectId!);
  }

  /// Returns an instance of the [Firestore] service.
  static Firestore firestore() {
    final dio = _getDioInstance();
    // Si sax ah u samee WebSocket URL
    final wsUrl = dio.options.baseUrl.replaceFirst('http', 'ws').replaceFirst('/api/v1', '');
    return Firestore._(dio: dio, webSocketUrl: wsUrl);
  }
}

//==============================================================================
// QAYBTA 2: FIRESTORE (OO SI BUUXDA DIB LOO DHISAY OO AWOOD LEH)
//==============================================================================

/// The entry point for all Firestore operations.
class Firestore {
  final Dio dio;
  final String webSocketUrl;

  Firestore._({required this.dio, required this.webSocketUrl});

  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return CollectionReference<Map<String, dynamic>>._(
      dio: dio,
      path: collectionPath,
      webSocketUrl: webSocketUrl,
    );
  }

  WriteBatch batch() => WriteBatch._(dio);

  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final transaction = Transaction._(dio);
    try {
      final result = await transactionHandler(transaction).timeout(timeout);
      if (transaction._writes.isNotEmpty) {
        await dio.post(
          '/firestore/runTransaction',
          data: {'writes': transaction._writes},
        );
      }
      return result;
    } on DioException catch (e) {
      throw _handleDioError(e, 'Transaction failed');
    } catch (e) {
      throw HappyPlatformException("Transaction failed: ${e.toString()}");
    }
  }
}

class Query<T> {
  final Dio dio;
  final String path;
  final String webSocketUrl;
  final List<List<dynamic>> _whereConditions;
  final List<Map<String, dynamic>> _orderByClauses;
  final int? _limit;
  final int? _offset;

  final T Function(DocumentSnapshot<T> snapshot)? _fromFirestore;
  final Map<String, dynamic> Function(T value, SetOptions? options)? _toFirestore;

  Query._({
    required this.dio,
    required this.path,
    required this.webSocketUrl,
    List<List<dynamic>>? whereConditions,
    List<Map<String, dynamic>>? orderByClauses,
    int? limit,
    int? offset,
    T Function(DocumentSnapshot<T>)? fromFirestore,
    Map<String, dynamic> Function(T, SetOptions?)? toFirestore,
  })  : _whereConditions = whereConditions ?? [],
        _orderByClauses = orderByClauses ?? [],
        _limit = limit,
        _offset = offset,
        _fromFirestore = fromFirestore,
        _toFirestore = toFirestore;
  
  Map<String, dynamic> _buildQueryParameters() {
    final params = <String, dynamic>{};
    if (_whereConditions.isNotEmpty) {
      params['where'] = _whereConditions.map((c) => '${c[0]},${c[1]},${c[2]}').toList();
    }
    if (_orderByClauses.isNotEmpty) {
       params['orderBy'] = _orderByClauses.map((c) => '${c['field']},${c['direction']}').first;
    }
    if (_limit != null) params['limit'] = _limit;
    if (_offset != null) params['offset'] = _offset;
    return params;
  }

  Query<T> _copyWith({
    List<List<dynamic>>? whereConditions,
    List<Map<String, dynamic>>? orderByClauses,
    int? limit,
    int? offset,
  }) {
    return Query._(
      dio: dio,
      path: path,
      webSocketUrl: webSocketUrl,
      whereConditions: whereConditions ?? _whereConditions,
      orderByClauses: orderByClauses ?? _orderByClauses,
      limit: limit ?? _limit,
      offset: offset ?? _offset,
      fromFirestore: _fromFirestore,
      toFirestore: _toFirestore,
    );
  }

  Query<T> where(String field, {
    dynamic isEqualTo,
    dynamic isNotEqualTo,
    dynamic isLessThan,
    dynamic isLessThanOrEqualTo,
    dynamic isGreaterThan,
    dynamic isGreaterThanOrEqualTo,
    List<dynamic>? whereIn,
    List<dynamic>? whereNotIn,
    dynamic arrayContains,
    List<dynamic>? arrayContainsAny,
  }) {
    final newConditions = List<List<dynamic>>.from(_whereConditions);
    if (isEqualTo != null) newConditions.add([field, '==', isEqualTo]);
    if (isNotEqualTo != null) newConditions.add([field, '!=', isNotEqualTo]);
    if (isLessThan != null) newConditions.add([field, '<', isLessThan]);
    if (isLessThanOrEqualTo != null) newConditions.add([field, '<=', isLessThanOrEqualTo]);
    if (isGreaterThan != null) newConditions.add([field, '>', isGreaterThan]);
    if (isGreaterThanOrEqualTo != null) newConditions.add([field, '>=', isGreaterThanOrEqualTo]);
    if (whereIn != null) newConditions.add([field, 'in', whereIn.join(';')]);
    if (whereNotIn != null) newConditions.add([field, 'not-in', whereNotIn.join(';')]);
    if (arrayContains != null) newConditions.add([field, 'array-contains', arrayContains]);
    if (arrayContainsAny != null) newConditions.add([field, 'array-contains-any', arrayContainsAny.join(';')]);

    return _copyWith(whereConditions: newConditions);
  }

  Query<T> orderBy(String field, {bool descending = false}) {
     final newOrderBy = List<Map<String, dynamic>>.from(_orderByClauses);
     newOrderBy.add({'field': field, 'direction': descending ? 'desc' : 'asc'});
     return _copyWith(orderByClauses: newOrderBy);
  }

  Query<T> limit(int count) => _copyWith(limit: count);

  Future<QuerySnapshot<T>> get([GetOptions? options]) async {
    if (options?.source == Source.cache) {
      print("⚠️ Cache-first not yet implemented. Fetching from server.");
    }
    try {
      final response = await dio.get(
        '/firestore/collections/$path/documents',
        queryParameters: _buildQueryParameters(),
      );
      return QuerySnapshot<T>._fromResponse(response, _fromFirestore);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to get documents');
    }
  }

  Stream<QuerySnapshot<T>> snapshots() {
    // Tani waa hirgelin fudud oo 'polling' ah
    final streamController = StreamController<QuerySnapshot<T>>.broadcast();
    Timer? timer;

    void fetchData() async {
       try {
         final snapshot = await get();
         if (!streamController.isClosed) streamController.add(snapshot);
       } catch (e) {
         if (!streamController.isClosed) streamController.addError(e);
       }
    }
    
    fetchData();
    timer = Timer.periodic(const Duration(seconds: 15), (timer) => fetchData());

    streamController.onCancel = () {
      timer?.cancel();
      streamController.close();
    };

    return streamController.stream;
  }
}
/// A CollectionReference can be used for adding documents, getting document references, and querying for documents.
class CollectionReference<T> extends Query<T> {
  CollectionReference._({
    required Dio dio,
    required String path,
    required String webSocketUrl,
    T Function(DocumentSnapshot<T>)? fromFirestore,
    Map<String, dynamic> Function(T, SetOptions?)? toFirestore,
  }) : super._(
          dio: dio,
          path: path,
          webSocketUrl: webSocketUrl,
          fromFirestore: fromFirestore,
          toFirestore: toFirestore,
        );

  /// Returns a [DocumentReference] with the provided [documentId].
  DocumentReference<T> doc([String? documentId]) {
    final id = documentId ?? const Uuid().v4();
    
    // =========================================================================
    // ====================> HALKAN WAA XALKA OO DHAN <=========================
    // =========================================================================
    // Waa inaad u gudbisaa `_fromFirestore` iyo `_toFirestore` DocumentReference-ka.
    return DocumentReference<T>._(
      dio: dio,
      collectionPath: path,
      documentId: id,
      webSocketUrl: webSocketUrl,
      fromFirestore: _fromFirestore, 
      toFirestore: _toFirestore,   
    );
    // =========================================================================
  }

  /// Adds a new document to this collection with the given data.
  Future<DocumentReference<T>> add(T data) async {
    final docRef = doc(); // Samee ID cusub
    await docRef.set(data);
    return docRef;
  }

  /// Returns a new [CollectionReference] that utilizes the specified converter.
  CollectionReference<R> withConverter<R>({
    required R Function(DocumentSnapshot<R> snapshot) fromFirestore,
    required Map<String, dynamic> Function(R value, SetOptions? options) toFirestore,
  }) {
    return CollectionReference<R>._(
      dio: dio,
      path: path,
      webSocketUrl: webSocketUrl,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
  }
}

/// A DocumentReference refers to a document location in a Firestore database.
class DocumentReference<T> {
  final Dio dio;
  final String collectionPath;
  final String documentId;
  final String webSocketUrl;
  
  // Hadda waa `nullable` si aysan dhibaato u keenin.
  final T Function(DocumentSnapshot<T>)? _fromFirestore;
  final Map<String, dynamic> Function(T, SetOptions?)? _toFirestore;
  
   DocumentReference._({
    required this.dio,
    required this.collectionPath,
    required this.documentId,
    required this.webSocketUrl,
    // Waa inaad u gudbisaa `_fromFirestore` iyo `_toFirestore` si toos ah
    T Function(DocumentSnapshot<T>)? fromFirestore,
    Map<String, dynamic> Function(T, SetOptions?)? toFirestore,
  }) : _fromFirestore = fromFirestore, 
       _toFirestore = toFirestore;
  // =========================================================================

  String get id => documentId;
  String get _documentPath => '/firestore/collections/$collectionPath/documents/$documentId';
  
  Future<DocumentSnapshot<T>> get([GetOptions? options]) async {
     try {
      final response = await dio.get(_documentPath);
      return DocumentSnapshot<T>._fromResponse(response, _fromFirestore);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return DocumentSnapshot<T>._(id: documentId, dataMap: null, fromFirestore: _fromFirestore);
      }
      throw _handleDioError(e, 'Failed to get document');
    }
  }

  Future<void> set(T data, [SetOptions? options]) async {
    final mapData = _toFirestore != null
        ? _toFirestore!(data, options)
        : data as Map<String, dynamic>;
    
    try {
      if (options?.merge == true) {
        await dio.patch(_documentPath, data: mapData);
      } else {
        await dio.put(_documentPath, data: mapData);
      }
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to set document');
    }
  }
  
  Future<void> update(Map<Object, Object?> data) async {
     try {
      await dio.patch(_documentPath, data: data);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to update document');
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
     final streamController = StreamController<DocumentSnapshot<T>>.broadcast();
     Timer? timer;
     void fetchData() async {
       try {
         final snapshot = await get();
         if (!streamController.isClosed) streamController.add(snapshot);
       } catch(e) {
         if (!streamController.isClosed) streamController.addError(e);
       }
     }
     fetchData();
     timer = Timer.periodic(const Duration(seconds: 15), (_) => fetchData());
     streamController.onCancel = () => timer?.cancel();
     return streamController.stream;
  }
}

class QuerySnapshot<T> {
  final List<DocumentSnapshot<T>> docs;
  int get size => docs.length;
  bool get isEmpty => docs.isEmpty;

  QuerySnapshot._({required this.docs});

  factory QuerySnapshot._fromResponse(Response response,
      T Function(DocumentSnapshot<T>)? fromFirestore) {
    final List<dynamic> dataList = (response.data as List<dynamic>?) ?? [];
    final docs = dataList
        .map((docData) => DocumentSnapshot<T>._fromMap(docData, fromFirestore))
        .toList();
    return QuerySnapshot._(docs: docs);
  }
}

class DocumentSnapshot<T> {
  final String id;
  final Map<String, dynamic>? _dataMap;
  final T Function(DocumentSnapshot<T>)? _fromFirestore;

  DocumentSnapshot._({
    required this.id,
    required Map<String, dynamic>? dataMap,
    T Function(DocumentSnapshot<T>)? fromFirestore,
  })  : _dataMap = dataMap,
        _fromFirestore = fromFirestore;

  bool get exists => _dataMap != null;

  T? data() {
    if (!exists) return null;
    if (_fromFirestore != null) {
      return _fromFirestore!(this);
    }
    return _dataMap as T;
  }

  factory DocumentSnapshot._fromMap(
    Map<String, dynamic> map,
    T Function(DocumentSnapshot<T>)? fromFirestore,
  ) {
    return DocumentSnapshot._(
      id: map['id'] as String? ?? '',
      dataMap: map['data'] as Map<String, dynamic>?,
      fromFirestore: fromFirestore,
    );
  }

  factory DocumentSnapshot._fromResponse(
    Response response,
    T Function(DocumentSnapshot<T>)? fromFirestore,
  ) {
    if (response.data is Map<String, dynamic>) {
      return DocumentSnapshot._fromMap(
          response.data as Map<String, dynamic>, fromFirestore);
    }
    throw HappyPlatformException("Unexpected response format. Expected a Map.");
  }
}

class WriteBatch {
  final Dio _dio;
  final List<Map<String, dynamic>> _writes = [];

  WriteBatch._(this._dio);

  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    final mapData = document._toFirestore != null
        ? document._toFirestore!(data, options)
        : data as Map<String, dynamic>;
    _writes.add({'type': options?.merge == true ? 'update' : 'set', 'path': document._documentPath, 'data': mapData});
  }

  void update(DocumentReference document, Map<Object, Object?> data) {
    _writes.add({'type': 'update', 'path': document._documentPath, 'data': data});
  }

  void delete(DocumentReference document) {
     _writes.add({'type': 'delete', 'path': document._documentPath});
  }

  Future<void> commit() async {
    try {
      await _dio.post('/firestore/batchWrite', data: {'writes': _writes});
    } on DioException catch (e) {
      throw _handleDioError(e, 'Batch write failed');
    }
  }
}

class Transaction {
  final Dio _dio;
  final List<Map<String, dynamic>> _writes = [];
  Transaction._(this._dio);

  Future<DocumentSnapshot<T>> get<T>(DocumentReference<T> document) {
    if (_writes.isNotEmpty) {
      throw HappyPlatformException('Firestore transactions require all reads to be executed before all writes.');
    }
    return document.get();
  }

  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    final mapData = document._toFirestore != null
        ? document._toFirestore!(data, options)
        : data as Map<String, dynamic>;
    _writes.add({'type': options?.merge == true ? 'update' : 'set', 'path': document._documentPath, 'data': mapData});
  }

  void update(DocumentReference document, Map<Object, Object?> data) {
    _writes.add({'type': 'update', 'path': document._documentPath, 'data': data});
  }

  void delete(DocumentReference document) {
     _writes.add({'type': 'delete', 'path': document._documentPath});
  }
}

typedef TransactionHandler<T> = Future<T> Function(Transaction transaction);

// Helper Classes
class FieldValue { FieldValue._(); static FieldValue serverTimestamp() => FieldValue._(); static FieldValue delete() => FieldValue._(); }
class GetOptions { final Source source; const GetOptions({this.source = Source.server}); }
class SetOptions { final bool merge; const SetOptions({this.merge = false}); }
enum Source { server, cache, serverAndCache }


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
// ✅✅✅ QAYBTA 3: AUTH - OO SI BUUXDA DIB LOO HABEEYAY ✅✅✅
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
  /// Registers a new user. All parameters are optional.
  Future<AuthUser> registerWithEmailAndPassword({
    String? fullName, // <-- Waa laga saaray 'required'
    String? email,    // <-- Waa laga saaray 'required'
    String? password, // <-- Waa laga saaray 'required'
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

  /// Signs in a user. All parameters are optional.
  Future<AuthUser> signInWithEmailAndPassword({
    String? email,    // <-- Waa laga saaray 'required'
    String? password, // <-- Waa laga saaray 'required'
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

    /// Updates a user's profile using their email and current password for verification.
  /// This method does NOT require a JWT token.
  Future<AuthUser> updateUserByPassword({
    String? email,           // <-- Waa laga saaray 'required'
    String? currentPassword, // <-- Waa laga saaray 'required'
    String? newFullName,
    String? newEmail,
    String? newPassword,
  }) async {
    final Map<String, dynamic> data = {};
    // Si caqli ah ugu dar xogta haddii la bixiyo oo keliya
    if (email != null) data['email'] = email;
    if (currentPassword != null) data['current_password'] = currentPassword;
    if (newFullName != null) data['new_full_name'] = newFullName;
    if (newEmail != null) data['new_email'] = newEmail;
    if (newPassword != null) data['new_password'] = newPassword;
    
    if (data.isEmpty) {
      throw AuthException("You must provide some information to update.");
    }

    try {
      final response = await _dio.put(
        '/projects/$projectId/manage-user/update',
        data: data,
      );
      return AuthUser.fromJson(response.data);
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  /// Permanently deletes a user account using their email and password for verification.
  /// This method does NOT require a JWT token.
  Future<void> deleteUserByPassword({
    String? email,    // <-- Waa laga saaray 'required'
    String? password, // <-- Waa laga saaray 'required'
  }) async {
    try {
      await _dio.post(
        '/projects/$projectId/manage-user/delete',
        data: {'email': email, 'password': password},
      );
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

  //==============================================================================
  // QAYBTA HORE: TOKEN-BASED USER MANAGEMENT (WAAY SIDII HORE U JIRTAA)
  //==============================================================================
  
  // Waan ka tagaynaa function-nadii hore ee token-ka isticmaalayay si haddii aad mustaqbalka
  // u baahato ay diyaar kuu ahaadaan.

  /// Updates the profile of the currently authenticated user (requires token).
  Future<AuthUser> updateProfile({
    String? fullName,
    String? email,
  }) async {
    final Map<String, dynamic> data = {};
    if (fullName != null) data['full_name'] = fullName;
    if (email != null) data['email'] = email; // Server-ku waa inuu tan taageeraa

    if (data.isEmpty) throw AuthException("No update information provided.");

    try {
      final response = await _dio.put('/projects/$projectId/user/profile', data: data);
      return AuthUser.fromJson(response.data);
    } on DioException catch (e) {
      throw AuthException.fromDioException(e);
    }
  }

  /// Permanently deletes the account of the currently authenticated user (requires token).
  Future<void> deleteAccount() async {
    try {
      // Endpoint-kan wuxuu u baahan yahay token, body-giisuna wuu madhan yahay
      await _dio.post('/projects/$projectId/user/delete');
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

