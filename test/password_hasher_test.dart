// 密码哈希 PBKDF2-HMAC-SHA256 单元测试：同盐稳定、盐随机、校验正确、畸形串拒绝
import 'dart:convert';

import 'package:daily_planner/services/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 固定盐：必须是合法 base64，否则 base64Decode 会抛 FormatException
  final fixedSalt = base64Encode(utf8.encode('fixed-salt-0123456789'));

  test('同密码同盐哈希一致，盐不同哈希不同', () {
    final h1 = hash('mima123456', salt: fixedSalt);
    final h2 = hash('mima123456', salt: fixedSalt);
    final h3 = hash('mima123456');
    expect(h1, h2);
    expect(h1, isNot(h3));
  });

  test('verify：正确密码通过、错误密码拒绝', () {
    final stored = hash('mima123456', salt: fixedSalt);
    expect(verify('mima123456', stored), isTrue);
    expect(verify('wrong-password', stored), isFalse);
  });

  test('verify：畸形存储串一律拒绝', () {
    expect(verify('x', 'plain'), isFalse);
    expect(verify('x', 'pbkdf2\$abc\$salt'), isFalse);
    expect(verify('x', 'pbkdf2\$0\$c2FsdA==\$aGVsbG8='), isFalse);
  });

  test('盐为 16 随机字节，默认迭代次数 60000', () {
    final salt = generateSalt();
    expect(base64Decode(salt).length, 16);
    final stored = hash('mima123456');
    expect(stored.split(r'$')[1], '60000');
  });
}
