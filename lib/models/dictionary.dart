/// 公共字典单一来源（G4）。
///
/// 交通方式与计费类型的取值与顺序为全应用约定，旅游行程、收支账本等子功能
/// 统一引用此处，禁止在各自文件中硬编码副本（详见 docs/system_design_incremental）。

/// 交通方式（单选，可空）。
const List<String> kTransportModes = <String>[
  '飞机',
  '高铁',
  '火车',
  '汽车',
  '地铁',
  '公交',
  '打车',
  '其他',
];

/// 计费类型（多选）。
const List<String> kBillingTypes = <String>[
  '门票',
  '餐饮',
  '购物',
  '交通',
  '其他',
];
