import 'dart:async';

import 'package:flutter_blackbox/src/companion/firebase_streamer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('stop clears a bounded queue while a send is still active', () async {
    final activePost = Completer<http.Response>();
    var postStarted = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        postStarted = true;
        return activePost.future;
      }
      return http.Response('{}', 200);
    });
    final streamer = FirebaseStreamer.test(client);
    await streamer.start('ABC123');

    streamer.broadcast('logs', {'message': 'first'});
    await Future<void>.delayed(Duration.zero);
    expect(postStarted, isTrue);

    for (var i = 0; i < 150; i++) {
      streamer.broadcast('logs', {'message': 'event $i'});
    }
    expect(streamer.droppedEventCount, greaterThan(0));
    expect(streamer.queuedBytes, greaterThan(0));

    streamer.stop();
    expect(streamer.isStreaming, isFalse);
    expect(streamer.queuedBytes, 0);

    activePost.complete(http.Response('{}', 200));
    await Future<void>.delayed(Duration.zero);
    expect(streamer.queuedBytes, 0);
  });
}
