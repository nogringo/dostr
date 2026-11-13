package io.github.nogringo.dostr

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt


/// dostr_flutter native plugin.
///
/// Hosts the NIP-82 in-app update installer. The NIP-55 signer bridge lives
/// in the dostr_nip55 package.
class DartNdkPlugin : FlutterPlugin {
    private lateinit var _updatesChannel : MethodChannel
    private lateinit var _context : Context
    private val _updateLock = Any()
    private val _mainHandler = Handler(Looper.getMainLooper())
    private var _activeUpdate: UpdateDownload? = null

    private class UpdateDownload(
        val result: Result,
        val apk: File,
    ) {
        val cancelled = AtomicBoolean(false)
        val cancellationResults = mutableListOf<Result>()
        @Volatile var input: InputStream? = null
        @Volatile var connection: HttpURLConnection? = null
    }

    private companion object {
        const val MAX_APK_BYTES = 512L * 1024L * 1024L
        const val MAX_REDIRECTS = 5
    }


    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        _updatesChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "ndk/app_updates")
        _updatesChannel.setMethodCallHandler(::onUpdateMethodCall)
        _context = flutterPluginBinding.applicationContext
        pruneUpdateApks(File(_context.cacheDir, "ndk_updates"))
    }

    private fun onUpdateMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getInstalledSoftware" -> result.success(installedSoftware())
            "downloadAndInstall" -> downloadAndInstall(call, result)
            "cancelDownload" -> cancelUpdateDownload(result)
            else -> result.notImplemented()
        }
    }

    private fun installedSoftware(): HashMap<String, Any> {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            _context.packageManager.getPackageInfo(
                _context.packageName,
                android.content.pm.PackageManager.PackageInfoFlags.of(
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES.toLong()
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            _context.packageManager.getPackageInfo(
                _context.packageName,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    android.content.pm.PackageManager.GET_SIGNATURES
                },
            )
        }
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION") packageInfo.versionCode.toLong()
        }
        return hashMapOf(
            "packageId" to packageInfo.packageName,
            "version" to (packageInfo.versionName ?: ""),
            "versionCode" to versionCode,
            "platformVersion" to Build.VERSION.SDK_INT,
            "platforms" to Build.SUPPORTED_ABIS.mapNotNull(::androidPlatform),
            "certificateHashes" to certificateHashes(packageInfo),
        )
    }

    private fun androidPlatform(abi: String): String? = when (abi) {
        "arm64-v8a" -> "android-arm64-v8a"
        "armeabi-v7a" -> "android-armeabi-v7a"
        "x86" -> "android-x86"
        "x86_64" -> "android-x86_64"
        else -> null
    }

    private fun certificateHashes(packageInfo: android.content.pm.PackageInfo): List<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.let { signingInfo ->
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners?.toList()
                } else {
                    signingInfo.signingCertificateHistory?.toList()
                        ?: signingInfo.apkContentsSigners?.toList()
                }
            } ?: emptyList()
        } else {
            @Suppress("DEPRECATION") packageInfo.signatures?.toList() ?: emptyList()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }
    }

    private fun downloadAndInstall(call: MethodCall, result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            result.error(
                "unsupported_platform",
                "In-app APK installation requires Android 7 or newer",
                null,
            )
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !_context.packageManager.canRequestPackageInstalls()) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${_context.packageName}"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            _context.startActivity(intent)
            result.success("permissionRequired")
            return
        }
        val urls = call.argument<List<String>>("urls") ?: emptyList()
        val expectedHash = call.argument<String>("sha256")?.normalizedHash()
        val packageId = call.argument<String>("packageId")
        val versionCode = (call.argument<Number>("versionCode"))?.toLong()
        val expectedSize = (call.argument<Number>("size"))?.toLong()
        val declaredCertificates =
            (call.argument<List<String>>("certificateHashes") ?: emptyList())
                .map { it.normalizedHash() }
                .toSet()
        if (urls.isEmpty() || expectedHash == null || packageId == null || versionCode == null ||
            (expectedSize != null && expectedSize < 0)) {
            result.error("invalid_arguments", "Missing update asset metadata", null)
            return
        }

        val directory = File(_context.cacheDir, "ndk_updates").apply { mkdirs() }
        val operation = synchronized(_updateLock) {
            if (_activeUpdate != null) {
                result.error("update_in_progress", "An update download is already active", null)
                return
            }
            pruneUpdateApks(directory)
            UpdateDownload(
                result,
                File(directory, "update-${System.nanoTime()}.apk"),
            ).also { _activeUpdate = it }
        }

        Thread {
            try {
                val apk = operation.apk
                var lastDownloadError: Throwable? = null
                for (url in urls) {
                    try {
                        downloadUpdateApk(
                            url,
                            apk,
                            operation,
                            expectedHash,
                            expectedSize,
                        )
                        lastDownloadError = null
                        break
                    } catch (error: Throwable) {
                        lastDownloadError = error
                        apk.delete()
                        if (operation.cancelled.get()) break
                    }
                }
                if (lastDownloadError != null) throw lastDownloadError

                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    android.content.pm.PackageManager.GET_SIGNATURES
                }
                val archive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    _context.packageManager.getPackageArchiveInfo(
                        apk.path,
                        android.content.pm.PackageManager.PackageInfoFlags.of(flags.toLong()),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    _context.packageManager.getPackageArchiveInfo(apk.path, flags)
                } ?: error("Android could not parse downloaded APK")
                val archiveVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    archive.longVersionCode
                } else {
                    @Suppress("DEPRECATION") archive.versionCode.toLong()
                }
                check(archive.packageName == packageId) { "APK package ID mismatch" }
                check(archiveVersion == versionCode) { "APK version code mismatch" }
                val archiveCertificates = certificateHashes(archive).map { it.normalizedHash() }.toSet()
                val installedCertificates = (installedSoftware()["certificateHashes"] as List<*>)
                    .filterIsInstance<String>().map { it.normalizedHash() }.toSet()
                check(archiveCertificates.intersect(declaredCertificates).isNotEmpty()) {
                    "APK certificate does not match NIP-82 asset"
                }
                check(archiveCertificates.intersect(installedCertificates).isNotEmpty()) {
                    "APK certificate is incompatible with installed app"
                }

                _mainHandler.post {
                    if (operation.cancelled.get()) {
                        completeUpdateOnMainThread(operation, "cancelled")
                        return@post
                    }
                    try {
                        val uri = FileProvider.getUriForFile(
                            _context,
                            "${_context.packageName}.ndk_updates",
                            apk,
                        )
                        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE, uri).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                        }
                        _context.startActivity(intent)
                        completeUpdateOnMainThread(operation, "awaitingUserAction")
                    } catch (error: Throwable) {
                        completeUpdateOnMainThread(operation, error = error)
                    }
                }
            } catch (error: Throwable) {
                completeUpdate(
                    operation,
                    if (operation.cancelled.get()) "cancelled" else null,
                    if (operation.cancelled.get()) null else error,
                )
            } finally {
                operation.input = null
                operation.connection?.disconnect()
            }
        }.start()
    }

    private fun downloadUpdateApk(
        url: String,
        apk: File,
        operation: UpdateDownload,
        expectedHash: String,
        expectedSize: Long?,
    ) {
        try {
            val connection = openUpdateConnection(url, operation)
            val total = connection.getHeaderField("Content-Length")?.toLongOrNull() ?: -1L
            val byteLimit = minOf(expectedSize ?: MAX_APK_BYTES, MAX_APK_BYTES)
            check(total < 0 || total <= byteLimit) { "APK exceeds download size limit" }
            val digest = MessageDigest.getInstance("SHA-256")
            connection.getInputStream().use { input ->
                operation.input = input
                FileOutputStream(apk).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var downloaded = 0L
                    var lastProgressPercentage = -1
                    while (true) {
                        check(!operation.cancelled.get()) { "Update download cancelled" }
                        val count = input.read(buffer)
                        if (count < 0) break
                        downloaded += count
                        check(downloaded <= byteLimit) { "APK exceeds download size limit" }
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                        if (total > 0) {
                            val percentage = ((downloaded.toDouble() / total) * 100)
                                .roundToInt()
                                .coerceAtMost(99)
                            if (percentage != lastProgressPercentage) {
                                lastProgressPercentage = percentage
                                emitProgress(percentage / 100.0)
                            }
                        }
                    }
                    check(expectedSize == null || downloaded == expectedSize) {
                        "Downloaded APK size mismatch"
                    }
                    if (total > 0) emitProgress(1.0)
                }
            }
            val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
            check(actualHash == expectedHash) { "Downloaded APK SHA-256 mismatch" }
        } finally {
            operation.input = null
            operation.connection?.disconnect()
            operation.connection = null
        }
    }

    private fun cancelUpdateDownload(result: Result) {
        val operation = synchronized(_updateLock) {
            _activeUpdate?.also { it.cancellationResults.add(result) }
        }
        if (operation == null) {
            result.success(null)
            return
        }
        operation.cancelled.set(true)
        runCatching { operation.input?.close() }
        operation.connection?.disconnect()
    }

    private fun openUpdateConnection(rawUrl: String, operation: UpdateDownload): HttpURLConnection {
        var current = URL(rawUrl)
        repeat(MAX_REDIRECTS + 1) { redirectCount ->
            validatePublicHttpsUrl(current)
            val connection = (current.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 15_000
                readTimeout = 30_000
                connect()
            }
            operation.connection = connection
            val status = connection.responseCode
            if (status !in 300..399) return connection
            val location = connection.getHeaderField("Location")
                ?: error("Update redirect has no Location header")
            connection.disconnect()
            check(redirectCount < MAX_REDIRECTS) { "Too many update redirects" }
            current = URL(current, location)
        }
        error("Too many update redirects")
    }

    private fun validatePublicHttpsUrl(url: URL) {
        check(url.protocol.equals("https", ignoreCase = true)) {
            "Update URL must use HTTPS"
        }
        check(url.userInfo == null && url.host.isNotBlank()) { "Invalid update URL" }
        val addresses = InetAddress.getAllByName(url.host)
        check(addresses.isNotEmpty() && addresses.none(::isNonPublicAddress)) {
            "Update URL must resolve to a public address"
        }
    }

    private fun isNonPublicAddress(address: InetAddress): Boolean =
        address.isAnyLocalAddress || address.isLoopbackAddress ||
            address.isLinkLocalAddress || address.isSiteLocalAddress ||
            address.isMulticastAddress

    private fun completeUpdate(
        operation: UpdateDownload,
        value: String? = null,
        error: Throwable? = null,
    ) = _mainHandler.post {
        completeUpdateOnMainThread(operation, value, error)
    }

    private fun completeUpdateOnMainThread(
        operation: UpdateDownload,
        value: String? = null,
        error: Throwable? = null,
    ) {
        val cancellationResults = synchronized(_updateLock) {
            if (_activeUpdate !== operation) return
            _activeUpdate = null
            operation.cancellationResults.toList()
        }
        val cancelled = operation.cancelled.get() || value == "cancelled"
        if (cancelled || error != null) operation.apk.delete()
        if (cancelled) {
            operation.result.success("cancelled")
        } else if (error == null) {
            operation.result.success(value)
        } else {
            operation.result.error("update_failed", error.message ?: error.toString(), null)
        }
        cancellationResults.forEach { it.success(null) }
    }

    private fun emitProgress(progress: Double) {
        _mainHandler.post {
            _updatesChannel.invokeMethod("progress", progress.coerceIn(0.0, 1.0))
        }
    }

    private fun String.normalizedHash(): String =
        lowercase().replace(Regex("[^0-9a-f]"), "")

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        _updatesChannel.setMethodCallHandler(null)
    }
}
