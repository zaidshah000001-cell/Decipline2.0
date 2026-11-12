package com.zaid.decipline2

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.util.Log
import java.text.NumberFormat
import java.util.Locale

class SmsAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!alertsEnabled(context)) return
        val parts = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
        } catch (e: RuntimeException) {
            Log.w("SmsAlertReceiver", "SMS notification decoding failed: ${e.javaClass.simpleName}")
            return
        } ?: return

        parts.filterNotNull()
            .groupBy { it.displayOriginatingAddress ?: it.originatingAddress ?: "" }
            .forEach { (sender, msgs) ->
                val body = msgs.joinToString("") { it.displayMessageBody ?: it.messageBody ?: "" }
                val alert = detect(sender, body, homeCurrency(context)) ?: return@forEach
                notify(context, alert, (sender + body).hashCode())
            }
    }

    data class Alert(val amount: String, val debit: Boolean, val bank: String)

    companion object {
        const val CHANNEL_ID = "txn_alerts"
        private const val PREFS = "FlutterSharedPreferences"
        private const val PREF_ALERTS = "flutter.sms.alerts"
        private const val PREF_SMS = "flutter.sms.enabled"
        private const val PREF_CURRENCY = "flutter.currency.home"

        private val dlt = Regex("^[A-Z]{2}-([A-Z0-9]{2,9})(?:-[STG])?$")
        private val amount = Regex(
            "(rs\\.?|inr|₹|(?<![a-z])(?:us|s|a|c)\\$|\\$|€|£|¥|" +
                "(?<![a-z])(?:usd|eur|gbp|aed|sar|qar|kwd|omr|bhd|sgd|myr|cad|aud|jpy)(?![a-z]))" +
                "\\s*([0-9][0-9,]*(?:\\.[0-9]{1,3})?)"
        )
        private val signs = mapOf(
            "₹" to "INR", "us$" to "USD", "s$" to "SGD", "a$" to "AUD", "c$" to "CAD",
            "€" to "EUR", "£" to "GBP", "¥" to "JPY",
        )
        private val debit = Regex("\\b(debited|spent|withdrawn|sent|paid|deducted|purchase)\\b")
        private val credit = Regex("\\b(credited|received|deposited|refunded|reversed|reversal)\\b")
        private val skip = Regex(
            "\\b(otp|one[- ]time password|verification code)\\b|will be (auto[- ]?)?debited|to be debited|" +
                "\\b(due|reminder|failed|declined|unsuccessful|requested|request)\\b|statement|" +
                "\\b(offer|cashback up ?to|pre-?approved|apply now)\\b"
        )

        private val banks = linkedMapOf(
            "HDFC" to "HDFC", "ICICI" to "ICICI", "SBICRD" to "SBI Card", "SBI" to "SBI", "AXIS" to "Axis",
            "KOTAK" to "Kotak", "KMBL" to "Kotak", "IDFC" to "IDFC First", "YESB" to "Yes Bank",
            "INDUS" to "IndusInd", "PNB" to "PNB", "BOB" to "Bank of Baroda", "BARODA" to "Bank of Baroda",
            "CANBNK" to "Canara", "UNION" to "Union Bank", "UBOI" to "Union Bank", "BOI" to "Bank of India",
            "INDBNK" to "Indian Bank", "FED" to "Federal", "AUBANK" to "AU Bank", "RBL" to "RBL",
            "IDBI" to "IDBI", "CITI" to "Citi", "HSBC" to "HSBC", "AMEX" to "Amex", "SCB" to "StanChart",
            "DBS" to "DBS", "IPPB" to "India Post Payments", "PAYTM" to "Paytm", "PYTM" to "Paytm",
            "AIRBNK" to "Airtel Payments", "JUPITR" to "Jupiter", "ONECRD" to "OneCard", "SLICE" to "slice",
            "MOBIKW" to "MobiKwik", "AMZPAY" to "Amazon Pay", "IMEIND" to "IME India",
        )

        private fun alertsEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return prefs.getBoolean(PREF_SMS, true) && prefs.getBoolean(PREF_ALERTS, true)
        }

        private fun homeCurrency(context: Context): String =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(PREF_CURRENCY, null) ?: "INR"

        private fun currencyOf(token: String, home: String): String {
            val t = token.trimEnd('.')
            return when {
                t == "rs" -> if (home in setOf("INR", "PKR", "LKR", "NPR")) home else "INR"
                t == "$" -> if (home in setOf("USD", "CAD", "AUD", "NZD", "SGD", "MXN")) home else "USD"
                else -> signs[t] ?: t.uppercase(Locale.ROOT)
            }
        }

        private fun format(value: Double, code: String): String {
            if (code == "INR") {
                val fmt = NumberFormat.getNumberInstance(Locale.forLanguageTag("en-IN")).apply {
                    minimumFractionDigits = 0
                    maximumFractionDigits = 2
                }
                return "₹" + fmt.format(value)
            }
            val digits = try {
                java.util.Currency.getInstance(code).defaultFractionDigits.coerceAtLeast(0)
            } catch (e: IllegalArgumentException) {
                2
            }
            val fmt = NumberFormat.getNumberInstance(Locale.US).apply {
                minimumFractionDigits = 0
                maximumFractionDigits = digits
            }
            return "$code " + fmt.format(value)
        }

        fun detect(sender: String, body: String, home: String = "INR"): Alert? {
            val header = dlt.find(sender.trim().uppercase(Locale.ROOT))?.groupValues?.get(1) ?: return null
            val bank = banks.entries.firstOrNull { header.contains(it.key) }?.value ?: return null
            val lower = body.lowercase(Locale.ROOT)
            if (skip.containsMatchIn(lower)) return null
            val d = debit.find(lower)
            val c = credit.find(lower)
            if (d == null && c == null) return null
            val isDebit = when {
                Regex("\\b(refund(ed)?|reversed|reversal)\\b").containsMatchIn(lower) -> false
                c == null -> true
                d == null -> false
                else -> d.range.first <= c.range.first
            }
            val match = amount.findAll(lower).firstOrNull { m ->
                val before = lower.substring(maxOf(0, m.range.first - 24), m.range.first)
                !Regex("(bal(ance)?|limit|avl|available|cashback|reward|lien)[\\s:.\\-]*(is\\s*)?$").containsMatchIn(before)
            } ?: return null
            val value = match.groupValues[2].replace(",", "").toDoubleOrNull() ?: return null
            if (value <= 0) return null
            return Alert(format(value, currencyOf(match.groupValues[1], home)), isDebit, bank)
        }

        fun ensureChannel(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Transaction alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "A heads-up when a bank SMS shows money moving"
                }
            )
        }

        private fun notify(context: Context, alert: Alert, id: Int) {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return
            ensureChannel(context)
            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(MainActivity.EXTRA_FROM_ALERT, true)
            }
            val pi = PendingIntent.getActivity(
                context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val verb = if (alert.debit) "debited" else "credited"
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("${alert.amount} $verb · ${alert.bank}")
                .setContentText("Tap to review in Decipline2.0")
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(id, notification)
            } catch (e: SecurityException) {
                Log.w("SmsAlertReceiver", "Notification permission was revoked before posting")
            }
        }
    }
}
