import 'package:flutter_test/flutter_test.dart';
import 'package:tandem/models.dart';
import 'package:tandem/pc_client.dart';
import 'package:tandem/util.dart';

void main() {
  const fp = 'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';
  String code({String v = '1', String h = '192.168.1.20', String p = '48200', String s = 'a1b2c3d4e5f60718293a4b5c6d7e8f90'}) =>
      '{"v":$v,"n":"My PC","h":"$h","p":$p,"s":"$s","f":"$fp"}';

  test('accepts the desktop pairing payload', () {
    final q = QrPayload.tryParse(code());
    expect(q, isNotNull);
    expect(q!.host, '192.168.1.20');
    expect(q.port, 48200);
  });

  test('rejects anything else', () {
    expect(QrPayload.tryParse('https://example.com'), isNull);
    expect(QrPayload.tryParse(code(v: '2')), isNull);
    expect(QrPayload.tryParse(code(h: 'evil.example.com')), isNull);
    expect(QrPayload.tryParse(code(p: '70000')), isNull);
    expect(QrPayload.tryParse(code(s: 'XYZ')), isNull);
    expect(QrPayload.tryParse('{"v":1}'), isNull);
  });

  test('fingerprints compare regardless of case and colons', () {
    expect(normFp(fp), normFp(fp.toLowerCase().replaceAll(':', '')));
  });

  test('queue items survive a database round trip', () {
    final item = QueueItem(kind: ItemKind.file, name: 'a.jpg', path: '/x/a.jpg', size: 10, createdAt: DateTime.fromMillisecondsSinceEpoch(1000));
    final back = QueueItem.fromMap({...item.toMap(), 'id': 7});
    expect(back.id, 7);
    expect(back.status, ItemStatus.queued);
    expect(back.name, 'a.jpg');
  });

  test('formatting helpers', () {
    expect(fmtSize(512), '512 B');
    expect(fmtSize(1258291), '1.2 MB');
    expect(firstUrl('Read this https://example.com/a?b=1 now'), 'https://example.com/a?b=1');
    expect(firstUrl('no link here'), isNull);
  });
}
