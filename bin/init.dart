// ignore_for_file: avoid_print
import 'dart:io';
import 'package:yaml/yaml.dart';

/// CLI tool: `dart run flutter_blackbox:init`
///
/// Reads the user's pubspec.yaml, detects which HTTP/storage/socket
/// libraries they already use, and prints the exact imports and
/// setup boilerplate they need.
///
/// With --generate: writes the full adapter class implementations
/// directly into the user's project so flutter_blackbox itself stays
/// dependency-free.
void main(List<String> args) async {
  final showHelp = args.contains('--help') || args.contains('-h');
  final generateFile = args.contains('--generate') || args.contains('-g');

  if (showHelp) {
    _printHelp();
    return;
  }

  print('');
  print('  🐞 BlackBox Init — Auto-detecting your dependencies...');
  print('');

  // ── 1. Read the user's pubspec.yaml ──────────────────────────────────
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print(
        '  ❌ No pubspec.yaml found. Run this from your Flutter project root.');
    exit(1);
  }

  final content = pubspecFile.readAsStringSync();
  final yaml = loadYaml(content) as YamlMap;
  final deps = yaml['dependencies'] as YamlMap? ?? YamlMap();
  final devDeps = yaml['dev_dependencies'] as YamlMap? ?? YamlMap();
  final allDeps = <String>{
    ...deps.keys.cast<String>(),
    ...devDeps.keys.cast<String>()
  };

  // ── 2. Check flutter_blackbox is present ─────────────────────────────
  if (!allDeps.contains('flutter_blackbox')) {
    print('  ⚠️  flutter_blackbox not found in pubspec.yaml.');
    print('  Run: flutter pub add flutter_blackbox');
    print('');
    exit(1);
  }

  // ── 3. Detect matching libraries ─────────────────────────────────────
  final detections = <_Detection>[];

  if (allDeps.contains('dio')) {
    detections.add(const _Detection(
      library: 'dio',
      description: 'Dio HTTP client',
      setupLine: 'httpAdapters: [DioBlackBoxAdapter(dio)]',
      adapterClass: 'DioBlackBoxAdapter',
    ));
  }
  if (allDeps.contains('http')) {
    detections.add(const _Detection(
      library: 'http',
      description: 'http package',
      setupLine: 'httpAdapters: [HttpBlackBoxAdapter(client)]',
      adapterClass: 'HttpBlackBoxAdapter',
    ));
  }
  if (allDeps.contains('socket_io_client')) {
    detections.add(const _Detection(
      library: 'socket_io_client',
      description: 'Socket.IO client',
      setupLine: 'socketAdapters: [SocketIOBlackBoxAdapter(socket)]',
      adapterClass: 'SocketIOBlackBoxAdapter',
    ));
  }
  if (allDeps.contains('shared_preferences')) {
    detections.add(const _Detection(
      library: 'shared_preferences',
      description: 'SharedPreferences',
      setupLine: 'storageAdapters: [SharedPrefsStorageAdapter()]',
      adapterClass: 'SharedPrefsStorageAdapter',
    ));
  }
  if (allDeps.contains('firebase_crashlytics')) {
    detections.add(const _Detection(
      library: 'firebase_crashlytics',
      description: 'Firebase Crashlytics',
      setupLine: 'observers: [CrashlyticsObserver()]',
      adapterClass: 'CrashlyticsObserver',
    ));
  }

  // ── 4. Report findings ───────────────────────────────────────────────
  final allLibs = [
    'dio',
    'http',
    'socket_io_client',
    'shared_preferences',
    'firebase_crashlytics'
  ];
  final detectedLibs = detections.map((d) => d.library).toSet();

  for (final lib in allLibs) {
    if (detectedLibs.contains(lib)) {
      final d = detections.firstWhere((det) => det.library == lib);
      print('  ✅ Found $lib → ${d.description}');
    } else {
      print('  ⬚  $lib → not found, skipping');
    }
  }

  print('');

  if (detections.isEmpty) {
    print('  ℹ️  No supported libraries detected.');
    print(
        '  BlackBox will work with core features: logs, crashes, performance,');
    print('  rebuild tracking, journey, and QA reports.');
    print('');
    print(
        '  Add a network library (dio or http) to enable network inspection.');
    print('');
    exit(0);
  }

  // ── 5. Print setup boilerplate or generate adapter files ─────────────
  print('  ✨ ${detections.length} adapter(s) detected!\n');

  if (generateFile) {
    // _generateAdapterFile prints its own "Add to your main.dart" instructions
    // using the generated setupBlackBox() helper — no need to also call
    // _printSetupCode, which would duplicate the message with different code.
    _generateAdapterFile(detections);
  } else {
    _printSetupCode(detections);
    print('');
    print(
        '  💡 Tip: Run with --generate to create lib/blackbox_adapters.dart:');
    print('     dart run flutter_blackbox:init --generate');
    print('');
    print('     This generates the adapter implementations into YOUR project');
    print('     so flutter_blackbox stays dependency-free. You only get the');
    print('     packages you actually use. ✨');
    print('');
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Detection {
  const _Detection({
    required this.library,
    required this.description,
    required this.setupLine,
    required this.adapterClass,
  });
  final String library;
  final String description;
  final String setupLine;
  final String adapterClass;
}

// ─────────────────────────────────────────────────────────────────────────────
// Print usage
// ─────────────────────────────────────────────────────────────────────────────

void _printSetupCode(List<_Detection> detections) {
  print('  ┌─────────────────────────────────────────────────────────┐');
  print('  │  Add to your main.dart:                                 │');
  print('  └─────────────────────────────────────────────────────────┘');
  print('');
  print("  import 'package:flutter/foundation.dart';");
  print("  import 'package:flutter_blackbox/flutter_blackbox.dart';");
  print("  import 'blackbox_adapters.dart'; // generated by --generate");
  print('');
  print('  void main() {');
  print('    BlackBox.setup(');

  // Group httpAdapters into one named argument to avoid duplicate-key errors.
  final httpSetupLines = detections
      .where((d) => d.library == 'dio' || d.library == 'http')
      .map((d) =>
          d.setupLine.replaceFirst('httpAdapters: [', '').replaceFirst(']', ''))
      .toList();
  if (httpSetupLines.isNotEmpty) {
    print('      httpAdapters: [${httpSetupLines.join(', ')}],');
  }

  // Non-HTTP adapters (socket, storage, …) keep their own named argument.
  for (final d
      in detections.where((d) => d.library != 'dio' && d.library != 'http')) {
    print('      ${d.setupLine},');
  }

  print('      trigger: const BlackBoxTrigger.floatingButton(),');
  print('      enabled: kDebugMode,');
  print('    );');
  print('    runApp(const BlackBoxOverlay(child: MyApp()));');
  print('  }');
}

// ─────────────────────────────────────────────────────────────────────────────
// Generate lib/blackbox_adapters.dart with full implementations
// ─────────────────────────────────────────────────────────────────────────────

void _generateAdapterFile(List<_Detection> detections) {
  final buffer = StringBuffer();

  buffer.writeln(
      '// Auto-generated by: dart run flutter_blackbox:init --generate');
  buffer.writeln('// Re-run to regenerate after adding new libraries.');
  buffer.writeln('// ignore_for_file: depend_on_referenced_packages');
  buffer.writeln('');

  // ── 1. Collect all imports first (deduplicated) so they appear at the
  //       top of the file before any class declarations — required by Dart.
  final seenImports = <String>{};
  void addImport(String imp) {
    if (seenImports.add(imp)) buffer.writeln(imp);
  }

  addImport("import 'package:flutter_blackbox/flutter_blackbox.dart';");
  for (final d in detections) {
    switch (d.library) {
      case 'dio':
        addImport("import 'dart:convert';");
        addImport("import 'package:dio/dio.dart';");
      case 'http':
        addImport("import 'dart:convert';");
        addImport("import 'package:http/http.dart' as http;");
      case 'socket_io_client':
        addImport(
            "import 'package:socket_io_client/socket_io_client.dart' as io;");
      case 'shared_preferences':
        addImport(
            "import 'package:shared_preferences/shared_preferences.dart';");
      case 'firebase_crashlytics':
        addImport(
            "import 'package:firebase_crashlytics/firebase_crashlytics.dart';");
    }
  }
  buffer.writeln('');

  // ── 2. Write class bodies (without import statements).
  for (final d in detections) {
    switch (d.library) {
      case 'dio':
        buffer.writeln(_dioBody());
      case 'http':
        buffer.writeln(_httpBody());
      case 'socket_io_client':
        buffer.writeln(_socketIoBody());
      case 'shared_preferences':
        buffer.writeln(_sharedPrefsBody());
      case 'firebase_crashlytics':
        buffer.writeln(_crashlyticsObserverBody());
    }
  }

  // Build setupBlackBox() function
  final hasDio = detections.any((d) => d.library == 'dio');
  final hasHttp = detections.any((d) => d.library == 'http');
  final params = <String>[
    if (hasDio) 'required Dio dio',
    if (hasHttp) 'http.Client? httpClient',
    if (detections.any((d) => d.library == 'socket_io_client'))
      'io.Socket? socket',
  ];

  buffer.writeln('/// Call this in your main() before runApp().');
  buffer.writeln('///');
  buffer.writeln('/// ```dart');
  buffer.writeln('/// void main() {');
  if (hasDio) {
    buffer.writeln('///   setupBlackBox(dio: myDio);');
  } else {
    buffer.writeln('///   setupBlackBox();');
  }
  buffer.writeln('///   runApp(const BlackBoxOverlay(child: MyApp()));');
  buffer.writeln('/// }');
  buffer.writeln('/// ```');
  buffer.writeln('void setupBlackBox({${params.join(', ')}}) {');
  buffer.writeln('  BlackBox.setup(');

  // Merge all HTTP adapters into one list to avoid duplicate named-argument errors
  final httpAdapterEntries = <String>[
    if (hasDio) 'DioBlackBoxAdapter(dio)',
    if (hasHttp) 'HttpBlackBoxAdapter(httpClient)',
  ];
  if (httpAdapterEntries.isNotEmpty) {
    buffer.writeln('    httpAdapters: [${httpAdapterEntries.join(', ')}],');
  }
  if (detections.any((d) => d.library == 'socket_io_client')) {
    buffer.writeln(
        '    socketAdapters: socket != null ? [SocketIOBlackBoxAdapter(socket)] : [],');
  }
  if (detections.any((d) => d.library == 'shared_preferences')) {
    buffer.writeln('    storageAdapters: [SharedPrefsStorageAdapter()],');
  }
  if (detections.any((d) => d.library == 'firebase_crashlytics')) {
    buffer.writeln('    observers: [CrashlyticsObserver()],');
  }

  buffer.writeln('    logAdapter: PrintLogAdapter(),');
  buffer.writeln('    trigger: const BlackBoxTrigger.floatingButton(),');
  buffer.writeln('    enabled: true, // wrap with kDebugMode if needed');
  buffer.writeln('  );');
  buffer.writeln('}');

  const outputPath = 'lib/blackbox_adapters.dart';
  final file = File(outputPath);

  if (file.existsSync()) {
    print('');
    print('  ⚠️  $outputPath already exists. Deleting and regenerating...');
    file.deleteSync();
  }

  file.writeAsStringSync(buffer.toString());
  print('');
  print('  📝 Generated: $outputPath');
  print('');
  print('  Add to your main.dart:');
  print("    import 'package:flutter_blackbox/flutter_blackbox.dart';");
  print("    import 'blackbox_adapters.dart';");
  print('');
  print('    void main() {');
  if (hasDio) {
    print('      setupBlackBox(dio: myDio);');
  } else {
    print('      setupBlackBox();');
  }
  print('      runApp(const BlackBoxOverlay(child: MyApp()));');
  print('    }');
  print('');
}

// ─────────────────────────────────────────────────────────────────────────────
// Adapter Templates
// ─────────────────────────────────────────────────────────────────────────────

// Returns only the class body (no import statements — those are
// written once at the top of the file by _generateAdapterFile).
String _dioBody() => r"""
// ── DioBlackBoxAdapter ────────────────────────────────────────────────────────
// Connects your Dio instance to BlackBox's network inspector and mock engine.
// Auto-generated — safe to modify.

class DioBlackBoxAdapter extends BlackBoxHttpAdapter {
  DioBlackBoxAdapter(this._dio);

  final Dio _dio;
  _BlackBoxDioInterceptor? _interceptor;

  @override
  String get name => 'dio';

  @override
  void attach() {
    _interceptor = _BlackBoxDioInterceptor(adapter: this);
    _dio.interceptors.add(_interceptor!);
  }

  @override
  void detach() {
    if (_interceptor != null) {
      _dio.interceptors.remove(_interceptor!);
      _interceptor = null;
    }
  }
}

class _BlackBoxDioInterceptor extends Interceptor {
  _BlackBoxDioInterceptor({required this.adapter});

  final DioBlackBoxAdapter adapter;
  int _idCounter = 0;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final id = 'dio_${_idCounter++}_${DateTime.now().millisecondsSinceEpoch}';
    options.extra['blackbox_request_id'] = id;
    options.extra['blackbox_start_ms'] = DateTime.now().millisecondsSinceEpoch;

    adapter.onRequest(NetworkRequest(
      id: id,
      method: options.method,
      url: '${options.baseUrl}${options.path}',
      timestamp: DateTime.now(),
      headers: _sanitiseHeaders(options.headers),
      body: _encodeBody(options.data),
      queryParameters:
          options.queryParameters.map((k, v) => MapEntry(k, v.toString())),
    ));

    final fullUrl = '${options.baseUrl}${options.path}';
    final mock = await adapter.intercept(options.method, fullUrl);

    if (mock != null) {
      final startMs = options.extra['blackbox_start_ms'] as int;
      final durationMs = DateTime.now().millisecondsSinceEpoch - startMs;
      final mockBody = mock.body;
      adapter.onResponse(NetworkResponse(
        requestId: id,
        statusCode: mock.statusCode,
        durationMs: durationMs,
        body: mockBody,
        headers: mock.headers,
        responseSizeBytes: _estimateSize(mockBody),
      ));
      return handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: mock.statusCode,
          data: mock.body,
          headers: Headers.fromMap(
              mock.headers.map((k, v) => MapEntry(k, [v]))),
        ),
        true,
      );
    }

    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final body = _encodeBody(response.data);
    _recordResponse(
      requestOptions: response.requestOptions,
      statusCode: response.statusCode ?? 0,
      headers: _sanitiseHeaders(
          Map<String, dynamic>.from(response.headers.map)),
      body: body,
      responseSizeBytes: _estimateSize(body),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final id = err.requestOptions.extra['blackbox_request_id'] as String?;
    final startMs = err.requestOptions.extra['blackbox_start_ms'] as int?;
    if (id == null) {
      handler.next(err);
      return;
    }
    final durationMs =
        startMs != null ? DateTime.now().millisecondsSinceEpoch - startMs : 0;

    NetworkFailureType type = NetworkFailureType.connection;
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout) {
      type = NetworkFailureType.timeout;
    } else if (err.type == DioExceptionType.badResponse) {
      type = NetworkFailureType.server;
    }

    final errBody = err.response?.data;
    adapter.onResponse(NetworkResponse(
      requestId: id,
      statusCode: err.response?.statusCode ?? 0,
      headers: err.response != null
          ? _sanitiseHeaders(
              Map<String, dynamic>.from(err.response!.headers.map))
          : const {},
      body: errBody,
      durationMs: durationMs,
      failureType: type,
      responseSizeBytes: _estimateSize(errBody),
    ));
    handler.next(err);
  }

  void _recordResponse({
    required RequestOptions requestOptions,
    required int statusCode,
    required Map<String, String> headers,
    dynamic body,
    int? responseSizeBytes,
  }) {
    final id = requestOptions.extra['blackbox_request_id'] as String?;
    final startMs = requestOptions.extra['blackbox_start_ms'] as int?;
    if (id == null) return;
    final durationMs =
        startMs != null ? DateTime.now().millisecondsSinceEpoch - startMs : 0;
    adapter.onResponse(NetworkResponse(
      requestId: id,
      statusCode: statusCode,
      durationMs: durationMs,
      headers: headers,
      body: body,
      responseSizeBytes: responseSizeBytes,
    ));
  }

  int? _estimateSize(dynamic body) {
    if (body == null) return null;
    try {
      if (body is String) return body.length;
      return jsonEncode(body).length;
    } catch (_) {
      return body.toString().length;
    }
  }

  Map<String, String> _sanitiseHeaders(Map<String, dynamic> raw) {
    const redacted = {'authorization', 'cookie', 'set-cookie', 'x-api-key'};
    return {
      for (final e in raw.entries)
        e.key: redacted.contains(e.key.toLowerCase())
            ? '*** redacted ***'
            : e.value.toString(),
    };
  }

  dynamic _encodeBody(dynamic body) {
    if (body == null) return null;
    if (body is String) return body;
    if (body is Map || body is List) return body;
    try {
      return jsonDecode(body.toString());
    } catch (_) {
      return body.toString();
    }
  }
}
""";

String _httpBody() => r"""
// ── HttpBlackBoxAdapter ───────────────────────────────────────────────────────
// Observes all requests made through an http.Client.
// Auto-generated — safe to modify.

class HttpBlackBoxAdapter extends BlackBoxHttpAdapter {
  HttpBlackBoxAdapter([http.Client? client])
      : _client = client ?? http.Client() {
    this.client = _BlackBoxObservingClient(this, _client);
  }

  final http.Client _client;
  late final _BlackBoxObservingClient client;
  int _idCounter = 0;

  @override
  String get name => 'http';

  Future<http.StreamedResponse> observeSend(http.BaseRequest request) async {
    final id = 'http_${_idCounter++}_${DateTime.now().millisecondsSinceEpoch}';
    final startMs = DateTime.now().millisecondsSinceEpoch;
    final url = request.url.toString();

    onRequest(NetworkRequest(
      id: id,
      method: request.method,
      url: url,
      timestamp: DateTime.now(),
      headers: _sanitiseHeaders(request.headers),
      queryParameters: request.url.queryParameters,
    ));

    final mock = await intercept(request.method, url);
    if (mock != null) {
      final durationMs = DateTime.now().millisecondsSinceEpoch - startMs;
      final bodyBytes = _encodeBody(mock.body);
      onResponse(NetworkResponse(
        requestId: id,
        statusCode: mock.statusCode,
        durationMs: durationMs,
        headers: mock.headers,
        body: mock.body,
        responseSizeBytes: bodyBytes.length,
      ));
      return http.StreamedResponse(
        Stream.value(bodyBytes),
        mock.statusCode,
        headers: mock.headers,
        request: request,
      );
    }

    try {
      final response = await _client.send(request);
      final durationMs = DateTime.now().millisecondsSinceEpoch - startMs;
      final bytes = await response.stream.toBytes();
      String? bodyStr;
      try {
        bodyStr = utf8.decode(bytes);
      } catch (_) {
        bodyStr = '<binary data: ${bytes.length} bytes>';
      }
      onResponse(NetworkResponse(
        requestId: id,
        statusCode: response.statusCode,
        durationMs: durationMs,
        headers: response.headers,
        body: bodyStr,
        responseSizeBytes: bytes.length,
      ));
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
        request: request,
      );
    } on Exception catch (e) {
      final durationMs = DateTime.now().millisecondsSinceEpoch - startMs;
      onResponse(NetworkResponse(
        requestId: id,
        statusCode: 0,
        headers: const {},
        durationMs: durationMs,
        failureType: NetworkFailureType.connection,
        body: e.toString(),
      ));
      rethrow;
    }
  }

  Map<String, String> _sanitiseHeaders(Map<String, String> headers) {
    const redacted = {'authorization', 'cookie', 'set-cookie', 'x-api-key'};
    return {
      for (final e in headers.entries)
        e.key: redacted.contains(e.key.toLowerCase())
            ? '*** redacted ***'
            : e.value,
    };
  }

  List<int> _encodeBody(dynamic body) {
    if (body == null) return [];
    if (body is String) return utf8.encode(body);
    return utf8.encode(jsonEncode(body));
  }
}

class _BlackBoxObservingClient extends http.BaseClient {
  _BlackBoxObservingClient(this._adapter, this._inner);
  final HttpBlackBoxAdapter _adapter;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _adapter.observeSend(request);
  }

  @override
  void close() => _inner.close();
}
""";

String _socketIoBody() => r"""
// ── SocketIOBlackBoxAdapter ───────────────────────────────────────────────────
// Captures all incoming socket events via socket.onAny().
// Auto-generated — safe to modify.

class SocketIOBlackBoxAdapter extends BlackBoxSocketAdapter {
  SocketIOBlackBoxAdapter(this._socket);

  final io.Socket _socket;

  @override
  String get name => 'socket_io';

  @override
  void attach() {
    _socket.onAny((String event, dynamic data) {
      onEvent(SocketEvent(
        id: 'soc_${DateTime.now().microsecondsSinceEpoch}',
        eventName: event,
        data: data,
        timestamp: DateTime.now(),
        direction: SocketDirection.incoming,
      ));
    });
  }

  @override
  void detach() => _socket.offAny();
}
""";

String _sharedPrefsBody() => r"""
// ── SharedPrefsStorageAdapter ─────────────────────────────────────────────────
// Exposes SharedPreferences in the BlackBox Storage panel.
// Auto-generated — safe to modify.

class SharedPrefsStorageAdapter extends BlackBoxStorageAdapter {
  @override
  String get name => 'SharedPreferences';

  @override
  Future<Map<String, dynamic>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    return {for (final key in prefs.getKeys()) key: prefs.get(key)};
  }

  @override
  Future<void> write(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is List<String>) {
      await prefs.setStringList(key, value);
    } else {
      await prefs.setString(key, value.toString());
    }
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
""";

String _crashlyticsObserverBody() => r"""
// ── CrashlyticsObserver ───────────────────────────────────────────────────────
// Forwards BlackBox crashes to Firebase Crashlytics.
// Auto-generated — safe to modify.

class CrashlyticsObserver extends BlackBoxObserver {
  @override
  void onCrash(CrashEntry crash) {
    FirebaseCrashlytics.instance.recordError(
      crash.message,
      crash.stackTrace,
      reason: 'Caught by Flutter BlackBox 🐞',
      information: [
        if (crash.library != null) 'Library: ${crash.library}',
      ],
    );
  }
}
""";

void _printHelp() {
  print('');
  print('  🐞 BlackBox Init');
  print('  ─────────────────────────────────────────────');
  print('');
  print('  Auto-detects your project dependencies and generates');
  print('  the adapter implementations directly into your project.');
  print('');
  print('  This keeps flutter_blackbox dependency-free — you only');
  print('  get the packages you actually use. ✨');
  print('');
  print('  Usage:');
  print('    dart run flutter_blackbox:init              Detect & print setup');
  print(
      '    dart run flutter_blackbox:init --generate   Generate lib/blackbox_adapters.dart');
  print('    dart run flutter_blackbox:init --help       Show this help');
  print('');
  print('  Supported libraries:');
  print('    • dio                  → DioBlackBoxAdapter');
  print('    • http                 → HttpBlackBoxAdapter');
  print('    • socket_io_client     → SocketIOBlackBoxAdapter');
  print('    • shared_preferences   → SharedPrefsStorageAdapter');
  print('    • firebase_crashlytics → CrashlyticsObserver');
  print('');
}
