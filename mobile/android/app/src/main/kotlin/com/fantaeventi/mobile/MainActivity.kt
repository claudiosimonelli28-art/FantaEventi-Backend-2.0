package com.fantaeventi.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.media.AudioAttributes
import android.net.Uri
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

            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            // 1. Canale Predefinito FantaEventi
            val defaultChannel = NotificationChannel(
                "fantaeventi_channel",
                "Notifiche FantaEventi",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Canale per notifiche su inviti, proposte bonus, votazioni e VAR"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(defaultChannel)

            // 2. Canale Assegnazione Bonus (suono fanta_bonus)
            val bonusSoundUri = Uri.parse("${ContentResolver.SCHEME_ANDROID_RESOURCE}://${packageName}/raw/fanta_bonus")
            val bonusChannel = NotificationChannel(
                "fantaeventi_bonus_channel",
                "Assegnazione Bonus 🏆",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifiche con suono speciale per i bonus assegnati"
                enableVibration(true)
                setSound(bonusSoundUri, audioAttributes)
            }
            notificationManager.createNotificationChannel(bonusChannel)

            // 3. Canale Assegnazione Malus (suono fanta_malus)
            val malusSoundUri = Uri.parse("${ContentResolver.SCHEME_ANDROID_RESOURCE}://${packageName}/raw/fanta_malus")
            val malusChannel = NotificationChannel(
                "fantaeventi_malus_channel",
                "Assegnazione Malus 💀",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifiche con suono speciale per i malus assegnati"
                enableVibration(true)
                setSound(malusSoundUri, audioAttributes)
            }
            notificationManager.createNotificationChannel(malusChannel)
        }
    }
}
