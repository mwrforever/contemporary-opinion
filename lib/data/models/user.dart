/// 本地账户用户模型：对应 users 表。
///
/// passwordHash 为 PBKDF2-HMAC-SHA256 存储串（见 PasswordHasher），
/// 任何导出/日志均禁止携带该字段明文。
class User {
  const User({
    this.id,
    required this.username,
    required this.passwordHash,
    this.nickname,
    this.avatarPath,
    this.defaultRingSeconds,
    required this.createdAt,
  });

  final int? id;
  final String username;
  final String passwordHash;
  final String? nickname;
  final String? avatarPath;

  /// 新建任务默认响铃时长（秒），空则用全局默认
  final int? defaultRingSeconds;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'username': username,
        'password_hash': passwordHash,
        'nickname': nickname,
        'avatar_path': avatarPath,
        'default_ring_seconds': defaultRingSeconds,
        'created_at': createdAt.toIso8601String(),
      };

  factory User.fromMap(Map<String, dynamic> map) => User(
        id: map['id'] as int?,
        username: map['username'] as String,
        passwordHash: map['password_hash'] as String,
        nickname: map['nickname'] as String?,
        avatarPath: map['avatar_path'] as String?,
        defaultRingSeconds: map['default_ring_seconds'] as int?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  /// 复制并更新资料字段（id/username/passwordHash/createdAt 不可变）
  User copyWith({
    String? nickname,
    String? avatarPath,
    int? defaultRingSeconds,
  }) =>
      User(
        id: id,
        username: username,
        passwordHash: passwordHash,
        nickname: nickname ?? this.nickname,
        avatarPath: avatarPath ?? this.avatarPath,
        defaultRingSeconds: defaultRingSeconds ?? this.defaultRingSeconds,
        createdAt: createdAt,
      );
}
