package io.github.nogringo.dostr.nip55

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors


/// NIP-55 "Android Signer Application" bridge for external signer apps.
///
/// A request is first sent silently to the Content Resolver of the signer app
/// captured at login, off the main thread. When the signer app cannot answer
/// it there, it opens the signer app with an Intent and waits for
/// [onActivityResult].
class Nip55Plugin(
    private val backgroundExecutor: Executor = Executors.newSingleThreadExecutor(),
) : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var _channel : MethodChannel
    private lateinit var _context : Context
    private var _activityBinding: ActivityPluginBinding? = null
    private val _mainHandler = Handler(Looper.getMainLooper())

    private class Nip55Request(
        val type: String,
        val currentUser: String,
        val pubkey: String,
        val id: String,
        val uriData: String,
        val permissions: String,
        val signerPackage: String,
    )

    private data class PendingIntentResult(
        val result: MethodChannel.Result,
        val id: String,
    )

    private val _pendingIntentResults = HashMap<Int, PendingIntentResult>()
    private val _pendingIntentRequestCodesById = HashMap<String, Int>()
    private var _nextIntentRequestCode = 1

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        _channel = MethodChannel(flutterPluginBinding.binaryMessenger, "dostr_nip55")
        _channel.setMethodCallHandler(this)
        _context = flutterPluginBinding.applicationContext
    }

    private fun isSignerInstalled(signerPackage: String?): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("$nostrSignerScheme:"))
        if (!signerPackage.isNullOrEmpty()) {
            intent.setPackage(signerPackage)
        }
        return _context.packageManager.queryIntentActivities(intent, 0).isNotEmpty()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val params = call.arguments as? Map<*, *>
        when (call.method) {
            nostrSignerScheme -> {
                if (params == null) {
                    result.error("BAD_ARGUMENTS", "A NIP-55 request needs a map of arguments", null)
                    return
                }
                val request = Nip55Request(
                    type = params[keyType] as? String ?: "",
                    currentUser = params[keyCurrentUser] as? String ?: "",
                    pubkey = params[keyPubKey] as? String
                        ?: params["pubkey"] as? String
                        ?: "",
                    id = params[keyId] as? String ?: "",
                    uriData = params[keyUriData] as? String ?: "",
                    permissions = params[keyPermissions] as? String ?: "",
                    signerPackage = params[keyPackage] as? String ?: "",
                )

                // NIP-55: get_public_key is Intent-only, and the Content
                // Resolver is addressed by the signer package.
                if (request.type == "get_public_key" || request.signerPackage.isEmpty()) {
                    launchSigner(request, result)
                    return
                }
                backgroundExecutor.execute {
                    val answer = queryContentResolver(request)
                    _mainHandler.post {
                        if (answer != null) {
                            result.success(answer)
                        } else {
                            launchSigner(request, result)
                        }
                    }
                }
            }

            "isAppInstalled" -> {
                result.success(isSignerInstalled(params?.get(keyPackage) as? String))
            }

            "cancel" -> {
                val requestCode = (params?.get(keyId) as? String)
                    ?.let { _pendingIntentRequestCodesById[it] }
                val pending = requestCode?.let { removePendingIntentResult(it) }
                pending?.result?.error("CANCELLED", "The request was cancelled", null)
                result.success(pending != null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun launchSigner(request: Nip55Request, result: Result) {
        val activity = _activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "There is no activity to open the signer app from", null)
            return
        }

        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("$nostrSignerScheme:${request.uriData}")
        )
        if (request.type != "get_public_key") {
            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        intent.putExtra(keyType, request.type)
        intent.putExtra(keyCurrentUser, request.currentUser)
        intent.putExtra(keyPubKey, request.pubkey)
        intent.putExtra("pubkey", request.pubkey)
        intent.putExtra(keyId, request.id)
        intent.putExtra(keyPermissions, request.permissions)
        // Without a package, as at login, the user picks the signer app.
        if (request.signerPackage.isNotEmpty()) {
            intent.setPackage(request.signerPackage)
            intent.putExtra(keyPackage, request.signerPackage)
        }

        var requestCode: Int? = null
        try {
            requestCode = reserveIntentRequestCode(result, request.id)
            activity.startActivityForResult(intent, requestCode)
        } catch (e: Exception) {
            Log.d("Nip55Plugin", "cannot open the signer app '${request.signerPackage}': ${e.message}")
            if (requestCode != null) {
                removePendingIntentResult(requestCode)
            }
            result.error("LAUNCH_FAILED", e.message ?: "Cannot open the signer app", null)
        }
    }

    private fun reserveIntentRequestCode(result: MethodChannel.Result, id: String): Int {
        repeat(65535) {
            val requestCode = _nextIntentRequestCode
            _nextIntentRequestCode = if (_nextIntentRequestCode == 65535) {
                1
            } else {
                _nextIntentRequestCode + 1
            }
            if (!_pendingIntentResults.containsKey(requestCode)) {
                _pendingIntentResults[requestCode] = PendingIntentResult(result, id)
                if (id.isNotEmpty()) {
                    _pendingIntentRequestCodesById[id] = requestCode
                }
                return requestCode
            }
        }
        throw IllegalStateException("Too many pending NIP-55 signer intents")
    }

    private fun removePendingIntentResult(requestCode: Int): PendingIntentResult? {
        val pending = _pendingIntentResults.remove(requestCode)
        if (pending != null && pending.id.isNotEmpty()) {
            _pendingIntentRequestCodesById.remove(pending.id)
        }
        return pending
    }

    private fun completePendingIntentResult(requestCode: Int, data: HashMap<String, String?>): Boolean {
        val pending = removePendingIntentResult(requestCode) ?: return false
        pending.result.success(data)
        return true
    }

    private fun completePendingIntentResultById(id: String, data: HashMap<String, String?>): Boolean {
        val requestCode = _pendingIntentRequestCodesById[id] ?: return false
        return completePendingIntentResult(requestCode, data)
    }

    private fun buildResultMapFromJson(resultJson: JSONObject): HashMap<String, String?> {
        val dataMap: HashMap<String, String?> = HashMap()
        if (resultJson.has(keyResult)) {
            val signerResult = resultJson.optString(keyResult, "")
            dataMap[keyResult] = signerResult
            dataMap[keySignature] = signerResult
        }
        if (resultJson.has(keySignature)) {
            dataMap[keySignature] = resultJson.optString(keySignature, "")
        }
        if (resultJson.has(keyPackage)) {
            dataMap[keyPackage] = resultJson.optString(keyPackage, "")
        }
        if (resultJson.has(keyId)) {
            dataMap[keyId] = resultJson.optString(keyId, "")
        }
        if (resultJson.has(keyEvent)) {
            dataMap[keyEvent] = resultJson.optString(keyEvent, "")
        }
        if (resultJson.has(keyRejected)) {
            dataMap[keyRejected] = resultJson.optString(keyRejected, "")
        }
        return dataMap
    }

    private fun buildResultMapFromIntent(intent: Intent): HashMap<String, String?> {
        val dataMap: HashMap<String, String?> = HashMap()
        if (intent.hasExtra(keyResult)) {
            val signerResult = intent.getStringExtra(keyResult)
            dataMap[keyResult] = signerResult
            dataMap[keySignature] = signerResult
        }
        if (intent.hasExtra(keySignature)) {
            dataMap[keySignature] = intent.getStringExtra(keySignature)
        }
        if (intent.hasExtra(keyPackage)) {
            dataMap[keyPackage] = intent.getStringExtra(keyPackage)
        }
        if (intent.hasExtra(keyId)) {
            dataMap[keyId] = intent.getStringExtra(keyId)
        }
        if (intent.hasExtra(keyEvent)) {
            dataMap[keyEvent] = intent.getStringExtra(keyEvent)
        }
        if (intent.hasExtra(keyRejected)) {
            dataMap[keyRejected] = intent.getBooleanExtra(keyRejected, false).toString()
        }
        return dataMap
    }

    private fun completeBatchedResults(intent: Intent): Boolean {
        if (!intent.hasExtra(keyResults)) {
            return false
        }

        val resultsJson = intent.getStringExtra(keyResults) ?: return false
        return try {
            val results = JSONArray(resultsJson)
            var completedAny = false
            for (index in 0 until results.length()) {
                val item = results.optJSONObject(index) ?: continue
                val id = item.optString(keyId, "")
                if (id.isEmpty()) {
                    continue
                }
                val dataMap = buildResultMapFromJson(item)
                completedAny = completePendingIntentResultById(id, dataMap) || completedAny
            }
            completedAny
        } catch (e: Exception) {
            Log.d("Nip55Plugin", "cannot parse the batched NIP-55 results: ${e.message}")
            false
        }
    }

    // NIP-55: a result code other than RESULT_OK means the signer app failed,
    // not that the user refused.
    override fun onActivityResult(requestCode: Int, resultCode: Int, intent: Intent?): Boolean {
        if (!_pendingIntentResults.containsKey(requestCode)) {
            return false
        }

        if (resultCode == Activity.RESULT_OK && intent != null) {
            if (completeBatchedResults(intent)) {
                completePendingIntentResult(requestCode, HashMap())
                return true
            }

            val dataMap = buildResultMapFromIntent(intent)
            val id = dataMap[keyId]
            if (!id.isNullOrEmpty() && completePendingIntentResultById(id, dataMap)) {
                return true
            }
            completePendingIntentResult(requestCode, dataMap)
            return true
        }

        completePendingIntentResult(requestCode, HashMap())
        return true
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        _channel.setMethodCallHandler(null)
        (backgroundExecutor as? ExecutorService)?.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        _activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        _activityBinding?.removeActivityResultListener(this)
        _activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    /// The answer of the signer app, or null when it cannot answer silently
    /// and the Intent must ask the user. NIP-55: a `rejected` column means the
    /// user always rejects this request, so the Intent must not ask again.
    /// Adapted from https://github.com/0xchat-app/nostr-dart/blob/main/android/src/main/kotlin/com/oxchat/nostrcore/ChatcorePlugin.kt
    private fun queryContentResolver(request: Nip55Request): HashMap<String, String?>? {
        try {
            _context.contentResolver.query(
                Uri.parse("content://${request.signerPackage}.${request.type.uppercase()}"),
                arrayOf(request.uriData, request.pubkey, request.currentUser),
                null,
                null,
                null
            ).use {
                if (it == null) {
                    return null
                }
                if (it.getColumnIndex(keyRejected) >= 0) {
                    return hashMapOf(keyRejected to "true")
                }
                if (!it.moveToFirst()) {
                    return null
                }

                val dataMap: HashMap<String, String?> = HashMap()
                val resultIndex = it.getColumnIndex(keyResult)
                if (resultIndex >= 0) {
                    val result = it.getString(resultIndex)
                    dataMap[keyResult] = result
                    dataMap[keySignature] = result
                }
                val signatureIndex = it.getColumnIndex(keySignature)
                if (signatureIndex >= 0) {
                    dataMap[keySignature] = it.getString(signatureIndex)
                }
                val eventIndex = it.getColumnIndex(keyEvent)
                if (eventIndex >= 0) {
                    dataMap[keyEvent] = it.getString(eventIndex)
                }
                return if (dataMap[keySignature].isNullOrEmpty()) null else dataMap
            }
        } catch (e: Exception) {
            Log.d("Nip55Plugin", "Content Resolver query failed: ${e.message}")
            return null
        }
    }
}
