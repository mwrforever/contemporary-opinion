import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 密码哈希：本地账户的生产级最小实现。
///
/// 存储格式：`pbkdf2$迭代次数$盐base64$摘要base64`，
/// 校验时按存储参数重算并恒定时间比较，避免时序侧信道。
/// 默认迭代 60000 次、盐 16 随机字节（OWASP 推荐基线）。
String generateSalt({int length = 16}) {
  final rng = Random.secure();
  final bytes = List<int>.generate(length, (_) => rng.nextInt(256));
  return base64Encode(bytes);
}

/// 计算 PBKDF2-HMAC-SHA256 摘要；[salt] 未传时自动生成随机盐。
String hash(
  String password, {
  String? salt,
  int iterations = 60000,
}) {
  final s = salt ?? generateSalt();
  final hmac = Hmac(sha256, utf8.encode(password));
  var u = hmac.convert(base64Decode(s)).bytes;
  final result = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return 'pbkdf2\$$iterations\$$s\$${base64Encode(result)}';
}

/// 校验密码与存储串是否匹配；格式非法或参数异常一律返回 false。
bool verify(String password, String stored) {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations <= 0) return false;
  return _constEq(
    hash(password, salt: parts[2], iterations: iterations),
    stored,
  );
}

/// 恒定时间字符串比较：长度不同直接失败，其余按位异或累计
bool _constEq(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
