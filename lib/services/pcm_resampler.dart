import 'dart:typed_data';

/// 纯函数：Web Audio 采集到的 Float32 样本的处理工具。
///
/// 浏览器 `ScriptProcessorNode` 给出的原始采样是 Float32（范围约 [-1, 1]），
/// 且采样率/声道数由浏览器决定（常见 44.1k/48k、双声道）。云端 ASR
/// （Qwen3-ASR-Flash）需要 PCM16@16k 单声道，因此这里提供重采样、降混与
/// 量化封装的纯函数，便于单测，并被 `audio_capture_web.dart` 使用。

/// 单声道 Float32 样本的线性插值重采样。
///
/// [inRate] / [outRate] 为输入/输出采样率（Hz）。返回重采样后的单声道 Float32。
/// 空输入或非法速率返回空；输入输出速率一致时原样返回。
Float32List resampleFloat32(
  Float32List input,
  double inRate,
  double outRate,
) {
  if (input.isEmpty || inRate <= 0 || outRate <= 0) return Float32List(0);
  if ((inRate - outRate).abs() < 1e-6) return Float32List.fromList(input);

  final ratio = outRate / inRate;
  final outLen = (input.length * ratio).round();
  final out = Float32List(outLen);
  for (var i = 0; i < outLen; i++) {
    final position = i / ratio;
    final index = position.floor();
    final fraction = position - index;
    final current = input[index];
    final next = index + 1 < input.length ? input[index + 1] : input[index];
    out[i] = current + (next - current) * fraction;
  }
  return out;
}

/// 将单声道 Float32 样本（范围 [-1, 1]）量化为 16-bit PCM 小端字节流。
///
/// 归一化：正样本 *32767、负样本 *32768，覆盖完整 [-32768, 32767] 区间。
Uint8List float32ToPcm16(Float32List samples) {
  final out = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i].clamp(-1.0, 1.0);
    final int16 = (s < 0 ? (s * 32768).round() : (s * 32767).round())
        .clamp(-32768, 32767);
    out.setInt16(i * 2, int16, Endian.little);
  }
  return out.buffer.asUint8List();
}

/// 将多声道 Float32 缓冲降混为单声道（各声道取平均）。
Float32List mixToMono(List<Float32List> channels) {
  if (channels.isEmpty) return Float32List(0);
  if (channels.length == 1) return Float32List.fromList(channels.single);
  final length = channels.map((c) => c.length).reduce((a, b) => a < b ? a : b);
  final out = Float32List(length);
  for (var i = 0; i < length; i++) {
    var sum = 0.0;
    for (final c in channels) {
      sum += c[i];
    }
    out[i] = sum / channels.length;
  }
  return out;
}
