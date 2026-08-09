package com.dailyplanner.daily_planner

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 应用入口 Activity。
 *
 * 额外暴露 daily_planner/vibrate 通道：到点提醒时直接驱动马达震动
 * （VibrationEffect 波形），不依赖系统通知渠道 —— 荣耀等 ROM 对通知
 * 震动的拦截/削弱较多，直驱马达才能保证「震动开关」稳定生效。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "daily_planner/vibrate"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // 开始持续震动：循环波形（震 600ms / 停 400ms），直至 cancel 停止
                "vibrate" -> {
                    val vibrator =
                        getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator.vibrate(
                            VibrationEffect.createWaveform(
                                longArrayOf(0, 600, 400),
                                0
                            )
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(longArrayOf(0, 600, 400), 0)
                    }
                    result.success(null)
                }
                // 停止持续震动（响铃窗口结束 / 用户中断提醒）
                "cancel" -> {
                    val vibrator =
                        getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                    vibrator.cancel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
