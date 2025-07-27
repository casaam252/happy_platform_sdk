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
      dio.interceptors.add(LogInterceptor(responseBody: false, requestBody: true));
      _dioInstances[projectName] = dio;
    });
    print("✅ Happy Platform SDK Initialized for ${projects.length} project(s).");
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
    final wsUrl = _apiBaseUrl!.replaceFirst('http', 'ws').replaceFirst('/api/v1', '');
    
    final newInstance = RealtimeDatabase._internal(wsUrl: '$wsUrl/ws?apiKey=$apiKey');
    _realtimeInstances[projectName] = newInstance;
    return newInstance;
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
  Query where(String field, {
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
    if (isGreaterThanOrEqualTo != null) whereClauses.add('$field,>=,$isGreaterThanOrEqualTo');
    if (isLessThanOrEqualTo != null) whereClauses.add('$field,<=,$isLessThanOrEqualTo');
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
    return DocumentReference(dio: dio, collectionPath: path, documentId: documentId);
  }

  /// Adds a new document with a server-generated ID to this collection.
  Future<DocumentReference> add(Map<String, dynamic> data) async {
    try {
      final response = await dio.post('/firestore/collections/$path/documents', data: data);
      final newDocId = response.data['id'];
      return DocumentReference(dio: dio, collectionPath: path, documentId: newDocId);
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
  DocumentReference({required this.dio, required this.collectionPath, required this.documentId});

  String get id => documentId;

  Future<void> delete() async {
    try {
      await dio.delete('/firestore/collections/$collectionPath/documents/$documentId');
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

  Future<DocumentSnapshot> get() async {
    throw UnimplementedError('get() on a document is not yet supported on the backend.');
  }

  CollectionReference collection(String subCollectionId) {
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
    final docs = data.map((docData) => DocumentSnapshot.fromMap(docData)).toList();
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
  
  RealtimeDatabase._internal({required this.wsUrl}) : _streamController = StreamController.broadcast();
  
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
             _streamController.addError(Exception('Failed to parse server message: $e'));
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
    return db._streamController.stream.where((snapshot) => snapshot.path == path);
  }

  DatabaseReference push() {
    final newId = const Uuid().v4();
    return DatabaseReference(db: db, path: path == '/' ? newId : '$path/$newId');
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
// Qaybta 4: Error Handling Helper
//==============================================================================

String _handleDioError(DioException e, String defaultMessage) {
  if (e.response != null && e.response!.data is Map) {
    return e.response!.data['error']?.toString() ?? defaultMessage;
  }
  return e.message ?? defaultMessage;
}