import 'dart:convert';

import 'package:dialysis_care/services/backend_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes fragmented NDJSON chat events in order', () async {
    const payload =
        '{"type":"status","data":"Searching evidence…"}\n'
        '{"type":"chunk","data":"ADPKD "}\n'
        'not-json\n'
        '{"type":"chunk","data":"is inherited."}\n'
        '{"type":"sources","data":[{"author":"Torres","year":"2022","title":"ADPKD review"}]}\n'
        '{"type":"validation","data":{"passed":true,"overall_score":0.92,"checks":{"relevance":{"passed":true,"score":0.95}},"warnings":[]}}\n'
        '{"type":"done"}\n'
        '{"type":"chunk","data":"ignored"}\n';
    final bytes = utf8.encode(payload);
    final fragments = <List<int>>[
      bytes.sublist(0, 17),
      bytes.sublist(17, 51),
      bytes.sublist(51, 93),
      bytes.sublist(93),
    ];

    final events = await decodeChatStream(
      Stream.fromIterable(fragments),
    ).toList();

    expect(events.map((event) => event.type), [
      ChatStreamEventType.status,
      ChatStreamEventType.chunk,
      ChatStreamEventType.chunk,
      ChatStreamEventType.sources,
      ChatStreamEventType.validation,
      ChatStreamEventType.done,
    ]);
    expect(events.first.status, 'Searching evidence…');
    expect(events[1].chunk, 'ADPKD ');
    expect(events[2].chunk, 'is inherited.');
    expect(events[3].sourceCitations, ['Torres (2022)']);
    expect(events[3].sourceTitles, ['ADPKD review']);
    expect(events[4].validation?.passed, isTrue);
    expect(events[4].validation?.overallScore, 0.92);
    expect(events[4].validation?.checks['relevance']?.score, 0.95);
  });

  test('ignores empty and unknown events', () async {
    final events = await decodeChatStream(
      Stream.value(
        utf8.encode(
          '\n{"type":"future-event","data":"ignored"}\n{"type":"done"}\n',
        ),
      ),
    ).toList();

    expect(events, hasLength(1));
    expect(events.single.type, ChatStreamEventType.done);
  });
}
