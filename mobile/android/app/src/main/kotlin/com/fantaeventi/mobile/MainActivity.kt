package com.fantaeventi.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java) ?: return

            try {
                notificationManager.deleteNotificationChannel("fantaeventi_bonus_channel")
                notificationManager.deleteNotificationChannel("fantaeventi_malus_channel")
                notificationManager.deleteNotificationChannel("fantaeventi_bonus_channel_v2")
                notificationManager.deleteNotificationChannel("fantaeventi_malus_channel_v2")
            } catch (_: Exception) {}

            val defaultChannel = NotificationChannel(
                "fantaeventi_channel",
                "Notifiche FantaEventi",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Canale per tutte le notifiche di gioco, inviti, votazioni e VAR"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(defaultChannel)
        }
    }
}
