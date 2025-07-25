library happy_platform_sdk;

import 'package:dio/dio.dart';

//==============================================================================
// Qaybta 1: Entry Point & Initialization
//==============================================================================

/// The main class for interacting with the Happy Platform SDK.
class HappyPlatform {
  // Singleton pattern to ensure a single instance.
  static final HappyPlatform _instance = HappyPlatform._internal();
  factory HappyPlatform() => _instance;
  HappyPlatform._internal();

  static final Map<String, Dio> _dioInstances = {};

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
    if (projects.isEmpty) {
      throw ArgumentError('The projects map cannot be empty.');
    }

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
    if (dio == null) {
      throw Exception(
        'Project with name "$projectName" was not initialized. '
        'Ensure it is included in the projects map during initialization.',
      );
    }
    return Firestore(dio: dio);
  }
}

//==============================================================================
// Qaybta 2: Firestore Service
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

//==============================================================================
// Qaybta 3: Querying Classes (Query & CollectionReference)
//==============================================================================

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

//==============================================================================
// Qaybta 4: DocumentReference
//==============================================================================

/// A `DocumentReference` refers to a specific document in a collection.
class DocumentReference {
  final Dio dio;
  final String collectionPath;
  final String documentId;

  DocumentReference({
    required this.dio,
    required this.collectionPath,
    required this.documentId,
  });

  /// The ID of this document.
  String get id => documentId;

  /// Deletes the document.
  Future<void> delete() async {
    try {
      await dio.delete('/firestore/collections/$collectionPath/documents/$documentId');
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to delete document');
    }
  }

  /// Updates fields in the document.
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

  /// Reads a single document.
  /// NOTE: This requires a backend endpoint not yet implemented.
  Future<DocumentSnapshot> get() async {
    throw UnimplementedError('get() on a document is not yet supported on the backend.');
  }

  /// Returns a [CollectionReference] for a sub-collection within this document.
  CollectionReference collection(String subCollectionId) {
    final newPath = '$collectionPath/$documentId/$subCollectionId';
    return CollectionReference(dio: dio, path: newPath);
  }
}

//==============================================================================
// Qaybta 5: Data Models (QuerySnapshot & DocumentSnapshot)
//==============================================================================

/// A snapshot of a query, containing a list of [DocumentSnapshot]s.
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

/// A snapshot of a single document, containing its ID and data.
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
// Qaybta 6: Error Handling Helper
//==============================================================================

String _handleDioError(DioException e, String defaultMessage) {
  if (e.response != null && e.response!.data is Map) {
    return e.response!.data['error']?.toString() ?? defaultMessage;
  }
  return e.message ?? defaultMessage;
}