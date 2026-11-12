package com.zaid.decipline2

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val SMS_REQUEST = 9101
        const val NOTIFY_REQUEST = 9102
        const val EXTRA_FROM_ALERT = "from_sms_alert"
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pckt/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                "hasReceivePermission" -> result.success(hasReceivePermission())
                "requestPermission" -> {
                    if (hasSmsPermission() && hasReceivePermission()) {
                        result.success(true)
                    } else {
                        pendingPermission?.success(false)
                        pendingPermission = result
                        requestPermissions(
                            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
                            SMS_REQUEST,
                        )
                    }
                }
                "readInbox" -> {
                    val since = call.argument<Number>("sinceMillis")?.toLong() ?: 0L
                    val limit = call.argument<Int>("limit") ?: 5000
                    io.execute {
                        try {
                            val rows = readInbox(since, limit)
                            main.post { result.success(rows) }
                        } catch (e: SecurityException) {
                            main.post { result.error("PERMISSION", e.message, null) }
                        } catch (e: Exception) {
                            main.post { result.error("READ_FAILED", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pckt/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_REQUEST)
                    }
                    result.success(null)
                }
                "notificationsAllowed" -> result.success(
                    Build.VERSION.SDK_INT < 33 ||
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun hasSmsPermission() =
        checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    private fun hasReceivePermission() =
        checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_REQUEST) {
            pendingPermission?.success(hasSmsPermission())
            pendingPermission = null
        }
    }

    private fun readInbox(since: Long, limit: Int): List> {
        val out = ArrayList>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { c ->
            val id = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val addr = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val body = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val date = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (c.moveToNext() && out.size < limit) {
                out.add(
                    mapOf(
                        "id" to c.getLong(id).toString(),
                        "address" to (c.getString(addr) ?: ""),
                        "body" to (c.getString(body) ?: ""),
                        "date" to c.getLong(date),
                    )
                )
            }
        } ?: throw IllegalStateException("SMS inbox query returned no cursor")
        return out
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }
}
