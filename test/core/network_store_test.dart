import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/src/core/network/curl_exporter.dart';
import 'package:flutter_blackbox/src/core/network/har_exporter.dart';
import 'package:flutter_blackbox/src/core/network/network_request.dart';
import 'package:flutter_blackbox/src/core/network/network_response.dart';
import 'package:flutter_blackbox/src/core/network/network_store.dart';

void main() {
  group('NetworkStore', () {
    late NetworkStore store;

    setUp(() => store = NetworkStore(capacity: 5));
    tearDown(() => store.dispose());

    NetworkRequest req(String id) => NetworkRequest(
          id: id,
          method: 'GET',
          url: 'https://api.example.com/$id',
          timestamp: DateTime.now(),
        );

    NetworkResponse res(String requestId, int code) => NetworkResponse(
          requestId: requestId,
          statusCode: code,
          durationMs: 120,
          headers: const {},
        );

    test('records request as pending entry', () {
      store.onRequest(req('r1'));
      expect(store.entries.length, 1);
      expect(store.entries.first.isPending, isTrue);
    });

    test('pairs response with request', () {
      store.onRequest(req('r1'));
      store.onResponse(res('r1', 200));

      expect(store.entries.first.response?.statusCode, 200);
      expect(store.entries.first.isPending, isFalse);
    });

    test('ignores response with unknown requestId', () {
      store.onRequest(req('r1'));
      store.onResponse(res('unknown', 200)); // no matching request

      expect(store.entries.first.isPending, isTrue);
    });

    test('respects capacity — drops oldest', () {
      for (var i = 0; i < 7; i++) {
        store.onRequest(req('r$i'));
      }
      expect(store.entries.length, 5);
      expect(store.entries.first.request.id, 'r2');
    });

    test('clear empties store', () {
      store.onRequest(req('r1'));
      store.clear();
      expect(store.entries, isEmpty);
    });

    test('stream emits the latest state after throttling', () async {
      final counts = <int>[];
      final sub = store.stream.listen((e) => counts.add(e.length));

      store.onRequest(req('r1'));
      store.onResponse(res('r1', 201));

      // Wait for the 250ms throttle timer to finish
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(counts, [1]); // Both events throttled into a single emission
      await sub.cancel();
    });

    test('completed stream emits every response in a burst', () async {
      final completed = <String>[];
      final sub = store.completedStream.listen(
        (entry) => completed.add(entry.request.id),
      );
      for (var i = 0; i < 3; i++) {
        store.onRequest(req('r$i'));
        store.onResponse(res('r$i', 200));
      }

      await Future<void>.delayed(Duration.zero);

      expect(completed, ['r0', 'r1', 'r2']);
      await sub.cancel();
    });

    test('completed stream emits a request only once', () async {
      final completed = <String>[];
      final sub = store.completedStream.listen(
        (entry) => completed.add(entry.request.id),
      );
      store.onRequest(req('r1'));

      store.onResponse(res('r1', 200));
      store.onResponse(res('r1', 201));

      expect(completed, ['r1']);
      expect(store.entries.single.response?.statusCode, 201);
      await sub.cancel();
    });

    test('clear preserves listeners and immediately emits empty state',
        () async {
      final counts = <int>[];
      final sub = store.stream.listen((entries) => counts.add(entries.length));
      store.onRequest(req('r1'));

      store.clear();
      await Future<void>.delayed(Duration.zero);
      store.onRequest(req('r2'));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(counts, [0, 1]);
      await sub.cancel();
    });

    test('snapshots caller-owned payloads before retention', () {
      final body = <String, Object?>{
        'items': <Object?>[1, 2],
      };
      final headers = <String, dynamic>{
        'x-list': <Object?>['a']
      };
      store.onRequest(NetworkRequest(
        id: 'r1',
        method: 'POST',
        url: 'https://api.example.com',
        timestamp: DateTime.now(),
        headers: headers,
        body: body,
      ));

      (body['items'] as List<Object?>).add(3);
      (headers['x-list'] as List<Object?>).add('b');

      expect(jsonDecode(store.entries.single.request.body as String), {
        'items': [1, 2],
      });
      expect(store.entries.single.request.headers['x-list'], ['a']);
    });

    test('bounds cyclic bodies without throwing', () {
      final body = <Object?>[];
      body.add(body);

      expect(
        () => store.onRequest(NetworkRequest(
          id: 'r1',
          method: 'POST',
          url: 'https://api.example.com',
          timestamp: DateTime.now(),
          body: body,
        )),
        returnsNormally,
      );
      expect(store.truncatedPayloadCount, greaterThan(0));
      expect(store.approximateRetainedBytes, greaterThan(0));
    });

    test('keeps encoded bodies within the byte limit after JSON escaping', () {
      final body = {
        'items': List<String>.filled(200, '\u0000' * 1000),
      };

      store.onRequest(NetworkRequest(
        id: 'r1',
        method: 'POST',
        url: 'https://api.example.com',
        timestamp: DateTime.now(),
        body: body,
      ));

      final stored = store.entries.single.request.body as String;
      expect(utf8.encode(stored).length, lessThanOrEqualTo(100 * 1024));
      expect(() => jsonDecode(stored), returnsNormally);
      expect(store.truncatedPayloadCount, greaterThan(0));
    });

    test('toJson serialises both request and response', () {
      store.onRequest(req('r1'));
      store.onResponse(res('r1', 200));

      final json = store.toJson();
      expect(json.first['request']['id'], 'r1');
      expect(json.first['response']['statusCode'], 200);
    });

    test('NetworkResponse.isSuccess', () {
      expect(res('r', 200).isSuccess, isTrue);
      expect(res('r', 404).isSuccess, isFalse);
      expect(res('r', 500).isSuccess, isFalse);
    });

    test('NetworkResponse.isClientError', () {
      expect(res('r', 400).isClientError, isTrue);
      expect(res('r', 404).isClientError, isTrue);
      expect(res('r', 500).isClientError, isFalse);
    });

    test('NetworkResponse.isServerError', () {
      expect(res('r', 500).isServerError, isTrue);
      expect(res('r', 503).isServerError, isTrue);
      expect(res('r', 200).isServerError, isFalse);
    });
    test('NetworkResponse.formattedSize', () {
      final r1 = NetworkResponse(
        requestId: 'r1',
        headers: const {},
        durationMs: 10,
        responseSizeBytes: 500,
      );
      expect(r1.formattedSize, '500 B');

      final r2 = NetworkResponse(
        requestId: 'r2',
        headers: const {},
        durationMs: 10,
        responseSizeBytes: 1024 + 512,
      );
      expect(r2.formattedSize, '1.5 KB');

      final r3 = NetworkResponse(
        requestId: 'r3',
        headers: const {},
        durationMs: 10,
        responseSizeBytes: 1024 * 1024 * 2,
      );
      expect(r3.formattedSize, '2.0 MB');
    });

    test('HarExporter handles unencodable/arbitrary bodies gracefully', () {
      final request = NetworkRequest(
        id: 'r_har',
        method: 'POST',
        url: 'https://api.example.com/test',
        timestamp: DateTime.now(),
        headers: {'Content-Type': 'application/json'},
        body: {'key': 'value'},
      );
      final response = NetworkResponse(
        requestId: 'r_har',
        statusCode: 200,
        headers: {'content-type': 'application/json'},
        durationMs: 150,
        body: '{"status": "ok"}',
      );
      final entry = NetworkEntry(request: request)..response = response;

      final har = HarExporter.toHar([entry]);
      expect(har, contains('"version": "0.8.0"'));
      expect(har, contains('https://api.example.com/test'));
    });

    test('CurlExporter handles non-encodable bodies gracefully', () {
      final request = NetworkRequest(
        id: 'r_curl',
        method: 'POST',
        url: 'https://api.example.com/login',
        timestamp: DateTime.now(),
        headers: {'Authorization': 'Bearer token123'},
        queryParameters: {'v': '1'},
        body: {'username': 'test'},
      );
      final curl = CurlExporter.toCurl(request);
      expect(
          curl, contains("curl -X POST 'https://api.example.com/login?v=1'"));
      expect(curl, contains("-H 'Authorization: Bearer token123'"));
      expect(curl, contains("-d '{\"username\":\"test\"}'"));
    });
  });
}
