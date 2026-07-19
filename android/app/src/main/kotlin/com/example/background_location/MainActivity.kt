package com.example.background_location

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.background_location_tracker/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryLevel" -> {
                    val level = getBatteryLevel()
                    if (level != -1) {
                        result.success(level)
                    } else {
                        result.error("UNAVAILABLE", "Battery level not available.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getBatteryLevel(): Int {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        if (level in 0..100) return level

        // Fallback for devices/emulators where BATTERY_PROPERTY_CAPACITY
        // isn't populated: read the sticky ACTION_BATTERY_CHANGED intent.
        val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus = registerReceiver(null, intentFilter)
        val rawLevel = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        return if (rawLevel >= 0 && scale > 0) (rawLevel * 100 / scale) else -1
    }
}

