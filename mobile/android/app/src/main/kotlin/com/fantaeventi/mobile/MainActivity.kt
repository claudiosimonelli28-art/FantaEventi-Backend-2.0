package com.fantaeventi.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SETTINGS_CHANNEL = "com.fantaeventi.mobile/settings"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openNotificationSettings") {
                val channelId = call.argument<String>("channelId")
                try {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && channelId != null) {
                        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                        }
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java) ?: return

            // Pulisci vecchi canali sperimentali
            try {
                notificationManager.deleteNotificationChannel("fantaeventi_bonus_channel")
                notificationManager.deleteNotificationChannel("fantaeventi_malus_channel")
                notificationManager.deleteNotificationChannel("fantaeventi_bonus_channel_v2")
                notificationManager.deleteNotificationChannel("fantaeventi_malus_channel_v2")
            } catch (_: Exception) {}

            val channels = listOf(
                NotificationChannel(
                    "fantaeventi_bonus",
                    "🏆 Assegnazione Bonus",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Suono e notifiche quando ricevi un bonus o punti positivi"
                    enableVibration(true)
                },
                NotificationChannel(
                    "fantaeventi_malus",
                    "💀 Assegnazione Malus",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Suono e notifiche quando ricevi un malus o penalità"
                    enableVibration(true)
                },
                NotificationChannel(
                    "fantaeventi_var",
                    "⚖️ VAR & Giudice Arbitro",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Suono e notifiche per verifiche VAR, testimonianze e sentenze"
                    enableVibration(true)
                },
                NotificationChannel(
                    "fantaeventi_invites",
                    "🎉 Inviti & Amicizie",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifiche per nuovi inviti ad eventi o richieste di amicizia"
                    enableVibration(true)
                },
                NotificationChannel(
                    "fantaeventi_channel",
                    "🔔 Notifiche Generali",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Canale per votazioni di gruppo e aggiornamenti generali"
                    enableVibration(true)
                }
            )

            channels.forEach { notificationManager.createNotificationChannel(it) }
        }
    }
}

