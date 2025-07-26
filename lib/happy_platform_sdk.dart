library happy_platform_sdk;

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

//==============================================================================
// Qaybta 1: Entry Point & Initialization
//==============================================================================

class HappyPlatform {
  static final HappyPlatform _instance = HappyPlatform._internal();
  factory HappyPlatform() => _instance;
  HappyPlatform._internal();

  static final Map<String, Dio> _dioInstances = {};
  static String? _apiBaseUrl;

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
        ),
      );
      dio.interceptors.add(LogInterceptor(responseBody: false, requestBody: true));
      _dioInstances[projectName] = dio;
    });
    print("✅ Happy Platform SDK Initialized for ${projects.length} project(s).");
  }

  static Firestore firestore([String projectName = 'default']) {
    final dio = _dioInstances[projectName];
    if (dio == null) throw Exception('Project "$projectName" not initialized.');
    return Firestore(dio: dio);
  }

  static RealtimeDatabase realtimeDatabase([String projectName = 'default']) {
    final dio = _dioInstances[projectName];
    final apiKey = dio?.options.headers['X-API-Key'];
    if (_apiBaseUrl == null || apiKey == null) {
      throw Exception('Project "$projectName" not initialized.');
    }
    final wsUrl = _apiBaseUrl!
        .replaceFirst('http', 'ws')
        .replaceFirst('/api/v1', '');
    return RealtimeDatabase(wsUrl: '$wsUrl/ws?apiKey=$apiKey');
  }
}

//==============================================================================
// Qaybta 2: Firestore
//==============================================================================

class Firestore {
  final Dio dio;
  Firestore({required this.dio});

  CollectionReference collection(String collectionId) {
    return CollectionReference(dio: dio, path: collectionId);
  }
}

class Query {
  final Dio dio;
  final String path;
  final Map<String, dynamic> _queryParameters;

  Query({
    required this.dio,
    required this.path,
    Map<String, dynamic>? queryParameters,
  }) : _queryParameters = queryParameters ?? {};

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

  Query orderBy(String field, {bool descending = false}) {
    final newParams = Map<String, dynamic>.from(_queryParameters);
    newParams['orderBy'] = '$field,${descending ? 'desc' : 'asc'}';
    return Query(dio: dio, path: path, queryParameters: newParams);
  }
  
  Query limit(int count) {
    final newParams = Map<String, dynamic>.from(_queryParameters);
    newParams['limit'] = count;
    return Query(dio: dio, path: path, queryParameters: newParams);
  }

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

class CollectionReference extends Query {
  CollectionReference({required super.dio, required super.path});

  DocumentReference document(String documentId) {
    return DocumentReference(dio: dio, collectionPath: path, documentId: documentId);
  }

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

  RealtimeDatabase({required this.wsUrl}) : _streamController = StreamController.broadcast() {
    _connect();
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen((message) {
        try {
          final decoded = json.decode(message);
          if (decoded['type'] == 'data' || decoded['type'] == 'update') {
            _streamController.add(RealtimeSnapshot.fromJson(decoded));
          }
        } catch (e) {
          _streamController.addError('Failed to parse server message: $e');
        }
      },
      onError: (error) => _streamController.addError(error),
      onDone: () => _streamController.addError('Connection closed.'),
      );
    } catch (e) {
      _streamController.addError('Failed to connect to WebSocket: $e');
    }
  }

  DatabaseReference reference(String path) {
    return DatabaseReference(
      path: path,
      channel: _channel,
      stream: _streamController.stream,
    );
  }

  void goOffline() {
    _channel?.sink.close();
  }

  void goOnline() {
    if (_channel == null || _channel?.closeCode != null) {
      _connect();
    }
  }
}

// **CLASS-KA OO LA ISKU DARAY OO LA SAXAY**
class DatabaseReference {
  final String path;
  final WebSocketChannel? channel;
  final Stream<RealtimeSnapshot> stream;

  DatabaseReference({
    required this.path,
    required this.channel,
    required this.stream,
  });

  Stream<RealtimeSnapshot> onValue() {
    channel?.sink.add(json.encode({'type': 'subscribe', 'path': path}));
    return stream.where((snapshot) => snapshot.path == path);
  }

  Future<void> set(dynamic data) async {
    channel?.sink.add(json.encode({'type': 'set', 'path': path, 'payload': data}));
  }

  void off() {
    channel?.sink.add(json.encode({'type': 'unsubscribe', 'path': path}));
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