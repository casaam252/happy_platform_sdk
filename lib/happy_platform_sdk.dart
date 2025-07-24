// Kani waa file-ka ugu weyn ee dadku ay 'import'-garayn doonaan
// Waxay bixisaa class-ka ugu muhiimsan ee HappyPlatform
library happy_platform_sdk;

import 'package:dio/dio.dart';

// Qaybta 1: Class-ka Ugu Weyn ee Dejinta (Setup)
// User-ku wuxuu u yeerayaa tan hal mar oo keliya app-kiisa.
class HappyPlatform {
  // Singleton pattern si aan hal instance oo keliya u samayno
  static final HappyPlatform _instance = HappyPlatform._internal();
  factory HappyPlatform() => _instance;
  HappyPlatform._internal();

  static final Map<String, Dio> _dioInstances = {};
  // Dio instance-ka waxaa loo keydinayaa si guud

  /// Initializes the Happy Platform SDK.
  ///
  /// This must be called once, typically in your `main.dart`, before using any other SDK methods.
  /// [apiKey] waa furahaaga gaarka ah ee project-kaaga.
  /// [apiBaseUrl] waa ciwaanka server-kaaga Happy Platform.
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

    // Abuur Dio instance u gaar ah project kasta
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

// Qaybta 2: Class-ka Maareeya Adeegga Firestore
// (ISMA BEDDELIN)
class Firestore {
  final Dio dio;
  Firestore({required this.dio});

  CollectionReference collection(String collectionId) {
    return CollectionReference(dio: dio, path: collectionId);
  }
}
class CollectionReference {
  final Dio dio;
  final String path;
  CollectionReference({required this.dio, required this.path});

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

  Future<QuerySnapshot> get() async {
    try {
      final response = await dio.get('/firestore/collections/$path/documents');
      return QuerySnapshot.fromResponse(response);
    } on DioException catch (e) {
      throw _handleDioError(e, 'Failed to get documents');
    }
  }
}


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
      await dio.delete(
          '/firestore/collections/$collectionPath/documents/$documentId');
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
  ///
  /// NOTE: This requires a new endpoint on the backend:
  /// `GET /firestore/collections/{collectionName}/documents/{documentId}`
  Future<DocumentSnapshot> get() async {
    throw UnimplementedError(
        'get() on a document is not yet supported on the backend.');
  }

  /// Returns a [CollectionReference] for a sub-collection within this document.
  CollectionReference collection(String subCollectionId) {
    // Tani waxay u baahan tahay in backend-ka la cusbooneysiiyo si uu u aqbalo waddooyin dhaadheer
    // Tusaale: users/userID123/posts
    final newPath = '$collectionPath/$documentId/$subCollectionId';
    return CollectionReference(dio: dio, path: newPath);
  }
}

// Qaybta 5: Classes-ka Caawimaadda ah ee Natiijooyinka
/// A snapshot of a query, containing a list of [DocumentSnapshot]s.
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

// Qaybta 6: Shaqo Caawimaad ah oo Maareysa Khaladaadka
String _handleDioError(DioException e, String defaultMessage) {
  if (e.response != null && e.response!.data is Map) {
    return e.response!.data['error'] ?? defaultMessage;
  }
  return e.message ?? defaultMessage;
}
