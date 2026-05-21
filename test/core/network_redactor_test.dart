import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/src/core/network/network_redactor.dart';

void main() {
  group('NetworkRedactor', () {
    late NetworkRedactor redactor;

    setUp(() => redactor = NetworkRedactor());

    group('Header redaction', () {
      test('masks Authorization header', () {
        final headers = {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer abc123secret',
          'Accept': '*/*',
        };
        final result = redactor.redactHeaders(headers);
        expect(result['Authorization'], NetworkRedactor.redactedPlaceholder);
        expect(result['Content-Type'], 'application/json');
        expect(result['Accept'], '*/*');
      });

      test('masks headers case-insensitively', () {
        final headers = {
          'authorization': 'Bearer token',
          'X-API-KEY': 'secret-key',
          'x-auth-token': 'tok123',
        };
        final result = redactor.redactHeaders(headers);
        expect(result['authorization'], NetworkRedactor.redactedPlaceholder);
        expect(result['X-API-KEY'], NetworkRedactor.redactedPlaceholder);
        expect(result['x-auth-token'], NetworkRedactor.redactedPlaceholder);
      });

      test('returns empty map unchanged', () {
        final result = redactor.redactHeaders({});
        expect(result, isEmpty);
      });

      test('leaves non-sensitive headers untouched', () {
        final headers = {
          'Content-Type': 'text/html',
          'X-Request-Id': '12345',
        };
        final result = redactor.redactHeaders(headers);
        expect(result, headers);
      });
    });

    group('Body redaction', () {
      test('redacts password field in Map', () {
        final body = {
          'username': 'john',
          'password': 'secret123',
          'email': 'john@example.com',
        };
        final result = redactor.redactBody(body) as Map<String, dynamic>;
        expect(result['password'], NetworkRedactor.redactedPlaceholder);
        expect(result['username'], 'john');
        expect(result['email'], 'john@example.com');
      });

      test('redacts nested sensitive fields recursively', () {
        final body = {
          'user': {
            'name': 'Jane',
            'credentials': {
              'token': 'jwt-secret',
              'api_key': 'key123',
            },
          },
          'data': 'safe',
        };
        final result = redactor.redactBody(body) as Map<String, dynamic>;
        final user = result['user'] as Map<String, dynamic>;
        final creds = user['credentials'] as Map<String, dynamic>;
        expect(creds['token'], NetworkRedactor.redactedPlaceholder);
        expect(creds['api_key'], NetworkRedactor.redactedPlaceholder);
        expect(user['name'], 'Jane');
        expect(result['data'], 'safe');
      });

      test('redacts sensitive fields in List items', () {
        final body = [
          {'username': 'a', 'secret': 'shhh'},
          {'username': 'b', 'secret': 'shh2'},
        ];
        final result = redactor.redactBody(body) as List;
        expect(
            (result[0] as Map)['secret'], NetworkRedactor.redactedPlaceholder);
        expect(
            (result[1] as Map)['secret'], NetworkRedactor.redactedPlaceholder);
        expect((result[0] as Map)['username'], 'a');
      });

      test('returns null unchanged', () {
        expect(redactor.redactBody(null), isNull);
      });

      test('returns non-JSON string unchanged', () {
        expect(redactor.redactBody('hello world'), 'hello world');
      });

      test('returns numbers unchanged', () {
        expect(redactor.redactBody(42), 42);
      });

      test('redacts fields case-insensitively', () {
        final body = {
          'PASSWORD': 'secret',
          'Token': 'tok',
          'normal': 'ok',
        };
        final result = redactor.redactBody(body) as Map<String, dynamic>;
        expect(result['PASSWORD'], NetworkRedactor.redactedPlaceholder);
        expect(result['Token'], NetworkRedactor.redactedPlaceholder);
        expect(result['normal'], 'ok');
      });
    });

    group('Custom patterns', () {
      test('uses custom sensitive headers', () {
        final custom = NetworkRedactor(
          sensitiveHeaders: ['x-custom-secret'],
          sensitiveBodyFields: const [],
        );
        final headers = {
          'Authorization': 'still-visible',
          'X-Custom-Secret': 'masked',
        };
        final result = custom.redactHeaders(headers);
        expect(result['Authorization'], 'still-visible');
        expect(result['X-Custom-Secret'], NetworkRedactor.redactedPlaceholder);
      });

      test('uses custom sensitive body fields', () {
        final custom = NetworkRedactor(
          sensitiveHeaders: const [],
          sensitiveBodyFields: ['my_secret_field'],
        );
        final body = {
          'password': 'still-visible-because-not-in-custom',
          'my_secret_field': 'masked',
        };
        final result = custom.redactBody(body) as Map<String, dynamic>;
        expect(result['password'], 'still-visible-because-not-in-custom');
        expect(result['my_secret_field'], NetworkRedactor.redactedPlaceholder);
      });
    });
  });
}
