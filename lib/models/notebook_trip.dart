/// 旅游行程。语音走对应 prompt 解析为单条嵌套行程对象；价格不在语音中产出，
/// 由用户在 App 内手动补充（默认 0），本地汇总金额。
///
/// 交通方式 / 计费类型枚举取值见 [dictionary.dart]（单一来源，与账本共用）：
/// - [kTransportModes]：交通方式（单选，可空）。
/// - [kBillingTypes]：计费类型（多选）。
export 'dictionary.dart' show kTransportModes, kBillingTypes;

class NotebookTrip {
  final String id;
  final String title;
  final String city;
  final String homeCity;
  final String startDate; // yyyy-MM-dd，可选
  final String endDate;
  final TripTransport? intercityTransport;
  final TripHotel? hotel;
  final List<TripTransport> transports;
  final List<TripDay> days;

  NotebookTrip({
    required this.id,
    this.title = '',
    this.city = '',
    this.homeCity = '',
    this.startDate = '',
    this.endDate = '',
    this.intercityTransport,
    this.hotel,
    this.transports = const [],
    this.days = const [],
  });

  /// 打卡点总数（跨所有天）。
  int get checkpointCount =>
      days.fold(0, (sum, d) => sum + d.checkpoints.length);

  /// 本地估算总额：城际大交通 + 住宿 + 其余交通 + 各打卡点计费。
  /// 金额默认 0（语音不产出价格），用户在 App 内补充后实时汇总。
  num get totalCost {
    num sum = 0;
    final inter = intercityTransport;
    if (inter != null) {
      sum += inter.amount * (inter.isRoundTrip ? 2 : 1) * inter.times;
    }
    if (hotel != null) sum += hotel!.amount * hotel!.nights;
    for (final t in transports) {
      sum += t.amount * (t.isRoundTrip ? 2 : 1) * t.times;
    }
    for (final d in days) {
      for (final c in d.checkpoints) {
        for (final b in c.billings) sum += b.amount;
      }
    }
    return sum;
  }

  /// 不可变更新：仅覆盖传入的字段，其余保持原值。
  NotebookTrip copyWith({
    String? id,
    String? title,
    String? city,
    String? homeCity,
    String? startDate,
    String? endDate,
    TripTransport? intercityTransport,
    TripHotel? hotel,
    List<TripTransport>? transports,
    List<TripDay>? days,
  }) =>
      NotebookTrip(
        id: id ?? this.id,
        title: title ?? this.title,
        city: city ?? this.city,
        homeCity: homeCity ?? this.homeCity,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        intercityTransport: intercityTransport ?? this.intercityTransport,
        hotel: hotel ?? this.hotel,
        transports: transports ?? this.transports,
        days: days ?? this.days,
      );

  factory NotebookTrip.fromJson(Map<String, dynamic> m) => NotebookTrip(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        city: (m['city'] ?? '') as String,
        homeCity: (m['home_city'] ?? m['homeCity'] ?? '') as String,
        startDate: (m['start_date'] ?? m['startDate'] ?? '') as String,
        endDate: (m['end_date'] ?? m['endDate'] ?? '') as String,
        intercityTransport: _transport(m['intercity_transport'] ?? m['intercityTransport']),
        hotel: _hotel(m['hotel']),
        transports: _transportList(m['transports']),
        days: _days(m['days']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'city': city,
        'homeCity': homeCity,
        'startDate': startDate,
        'endDate': endDate,
        'intercityTransport': intercityTransport?.toJson(),
        'hotel': hotel?.toJson(),
        'transports': transports.map((t) => t.toJson()).toList(),
        'days': days.map((d) => d.toJson()).toList(),
      };

  static TripTransport? _transport(dynamic v) =>
      v is Map ? TripTransport.fromJson(Map<String, dynamic>.from(v)) : null;

  static TripHotel? _hotel(dynamic v) =>
      v is Map ? TripHotel.fromJson(Map<String, dynamic>.from(v)) : null;

  static List<TripTransport> _transportList(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => TripTransport.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  static List<TripDay> _days(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => TripDay.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }
}

class TripTransport {
  final String mode; // transport_modes 类型名
  final bool isRoundTrip;
  final int times;
  final String note;
  final num amount; // 默认 0，用户手动填写

  TripTransport({
    this.mode = '其他',
    this.isRoundTrip = false,
    this.times = 1,
    this.note = '',
    this.amount = 0,
  });

  factory TripTransport.fromJson(Map<String, dynamic> m) => TripTransport(
        mode: (m['mode'] ?? '其他') as String,
        isRoundTrip: m['is_round_trip'] is bool
            ? m['is_round_trip'] as bool
            : (m['isRoundTrip'] is bool ? m['isRoundTrip'] as bool : false),
        times: m['times'] is num ? (m['times'] as num).toInt() : 1,
        note: (m['note'] ?? '') as String,
        amount: m['amount'] is num ? m['amount'] as num : 0,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'isRoundTrip': isRoundTrip,
        'times': times,
        'note': note,
        'amount': amount,
      };
}

class TripHotel {
  final String name;
  final int nights;
  final String note;
  final num amount; // 每晚价格，默认 0

  TripHotel({
    this.name = '',
    this.nights = 1,
    this.note = '',
    this.amount = 0,
  });

  factory TripHotel.fromJson(Map<String, dynamic> m) => TripHotel(
        name: (m['name'] ?? '') as String,
        nights: m['nights'] is num ? (m['nights'] as num).toInt() : 1,
        note: (m['note'] ?? '') as String,
        amount: m['amount'] is num ? m['amount'] as num : 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'nights': nights,
        'note': note,
        'amount': amount,
      };
}

class TripDay {
  final String date;
  final String label;
  final List<TripCheckpoint> checkpoints;

  TripDay({
    this.date = '',
    this.label = '',
    this.checkpoints = const [],
  });

  /// 不可变更新：仅覆盖传入的字段，其余保持原值。
  TripDay copyWith({
    String? date,
    String? label,
    List<TripCheckpoint>? checkpoints,
  }) =>
      TripDay(
        date: date ?? this.date,
        label: label ?? this.label,
        checkpoints: checkpoints ?? this.checkpoints,
      );

  factory TripDay.fromJson(Map<String, dynamic> m) => TripDay(
        date: (m['date'] ?? '') as String,
        label: (m['label'] ?? '') as String,
        checkpoints: _checkpoints(m['checkpoints']),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'label': label,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
      };

  static List<TripCheckpoint> _checkpoints(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => TripCheckpoint.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }
}

class TripCheckpoint {
  final String name;
  final TripTransport? transport;
  final List<TripBilling> billings;
  final bool done;
  final int rating; // 1-5，0 未评分
  final String note;

  TripCheckpoint({
    required this.name,
    this.transport,
    this.billings = const [],
    this.done = false,
    this.rating = 0,
    this.note = '',
  });

  /// 不可变更新：仅覆盖传入的字段，其余保持原值。
  TripCheckpoint copyWith({
    String? name,
    TripTransport? transport,
    List<TripBilling>? billings,
    bool? done,
    int? rating,
    String? note,
  }) =>
      TripCheckpoint(
        name: name ?? this.name,
        transport: transport ?? this.transport,
        billings: billings ?? this.billings,
        done: done ?? this.done,
        rating: rating ?? this.rating,
        note: note ?? this.note,
      );

  factory TripCheckpoint.fromJson(Map<String, dynamic> m) => TripCheckpoint(
        name: (m['name'] ?? '') as String,
        transport: m['transport'] is Map
            ? TripTransport.fromJson(Map<String, dynamic>.from(m['transport']))
            : null,
        billings: _billings(m['billings']),
        done: m['done'] is bool ? m['done'] as bool : false,
        rating: m['rating'] is num ? (m['rating'] as num).toInt() : 0,
        note: (m['note'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'transport': transport?.toJson(),
        'billings': billings.map((b) => b.toJson()).toList(),
        'done': done,
        'rating': rating,
        'note': note,
      };

  static List<TripBilling> _billings(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => TripBilling.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }
}

class TripBilling {
  final String type; // billing_types 类型名
  final String note;
  final num amount; // 默认 0，用户手动填写

  TripBilling({
    this.type = '其他',
    this.note = '',
    this.amount = 0,
  });

  factory TripBilling.fromJson(Map<String, dynamic> m) => TripBilling(
        type: (m['type'] ?? '其他') as String,
        note: (m['note'] ?? '') as String,
        amount: m['amount'] is num ? m['amount'] as num : 0,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'note': note,
        'amount': amount,
      };
}
