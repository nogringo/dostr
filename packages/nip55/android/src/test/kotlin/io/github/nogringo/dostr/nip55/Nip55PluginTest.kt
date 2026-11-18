package io.github.nogringo.dostr.nip55

import android.app.Activity
import android.app.Application
import android.content.ComponentName
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowContentResolver
import java.util.concurrent.Executor

@RunWith(RobolectricTestRunner::class)
class Nip55PluginTest {
    private val signerPackage = "com.example.signer"
    private val userPubkey = "953f12b4f6966a289fde9adfc511e00a66cfa4cb9d69551dee51f3f387e8e277"
    private val peerPubkey = "e247d5da03bab4206b4d6ef5d9db0e175e0dbf51585fa16345dd53abdd2d9259"

    private lateinit var application: Application
    private lateinit var activity: Activity
    private lateinit var activityBinding: ActivityPluginBinding
    private lateinit var plugin: Nip55Plugin
    private val backgroundTasks = ArrayList<Runnable>()

    private class RecordedResult : MethodChannel.Result {
        var replies = 0
        var value: Any? = null
        var errorCode: String? = null

        override fun success(result: Any?) {
            replies++
            value = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            replies++
            this.errorCode = errorCode
        }

        override fun notImplemented() {
            replies++
        }
    }

    private class FakeSignerProvider(private val answer: () -> Cursor?) : ContentProvider() {
        var projections = ArrayList<List<String>>()

        override fun query(
            uri: Uri,
            projection: Array<out String>?,
            selection: String?,
            selectionArgs: Array<out String>?,
            sortOrder: String?,
        ): Cursor? {
            projections.add(projection?.toList() ?: emptyList())
            return answer()
        }

        override fun onCreate() = true
        override fun getType(uri: Uri): String? = null
        override fun insert(uri: Uri, values: ContentValues?): Uri? = null
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
        override fun update(
            uri: Uri,
            values: ContentValues?,
            selection: String?,
            selectionArgs: Array<out String>?,
        ) = 0
    }

    @Before
    fun setUp() {
        application = RuntimeEnvironment.getApplication()
        plugin = Nip55Plugin(Executor { backgroundTasks.add(it) })

        val engineBinding = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(engineBinding.binaryMessenger).thenReturn(mock(BinaryMessenger::class.java))
        `when`(engineBinding.applicationContext).thenReturn(application)
        plugin.onAttachedToEngine(engineBinding)

        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        activityBinding = mock(ActivityPluginBinding::class.java)
        `when`(activityBinding.activity).thenReturn(activity)
        plugin.onAttachedToActivity(activityBinding)
    }

    private fun installSigner(packageName: String) {
        val component = ComponentName(packageName, "$packageName.SignerActivity")
        val packageManager = shadowOf(application.packageManager)
        packageManager.addActivityIfNotPresent(component)
        packageManager.addIntentFilterForActivity(
            component,
            IntentFilter(Intent.ACTION_VIEW).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
                addDataScheme(nostrSignerScheme)
            },
        )
    }

    private fun registerProvider(type: String, answer: () -> Cursor?): FakeSignerProvider {
        val provider = FakeSignerProvider(answer)
        ShadowContentResolver.registerProviderInternal("$signerPackage.$type", provider)
        return provider
    }

    private fun call(method: String, arguments: Map<String, Any?>?): RecordedResult {
        val result = RecordedResult()
        plugin.onMethodCall(MethodCall(method, arguments?.let { HashMap(it) }), result)
        runBackgroundTasks()
        return result
    }

    private fun runBackgroundTasks() {
        while (backgroundTasks.isNotEmpty()) {
            backgroundTasks.removeAt(0).run()
        }
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun encrypt(id: String, withPackage: Boolean = true) = call(
        "nostrsigner",
        mapOf(
            "type" to "nip44_encrypt",
            "uri_data" to "hello",
            "current_user" to userPubkey,
            "pubkey" to peerPubkey,
            "id" to id,
            "package" to if (withPackage) signerPackage else null,
        ),
    )

    private fun nextStartedSigner() = shadowOf(activity).nextStartedActivityForResult

    @Test
    fun answersFromTheContentResolverWithoutOpeningTheSignerApp() {
        val provider = registerProvider("NIP44_ENCRYPT") {
            MatrixCursor(arrayOf("result")).apply { addRow(arrayOf("ciphertext")) }
        }

        val result = encrypt("req-1")

        assertEquals(listOf("hello", peerPubkey, userPubkey), provider.projections.single())
        assertEquals("ciphertext", (result.value as Map<*, *>)["signature"])
        assertNull(nextStartedSigner())
    }

    @Test
    fun queriesTheContentResolverOnTheBackgroundExecutor() {
        val provider = registerProvider("NIP44_ENCRYPT") {
            MatrixCursor(arrayOf("result")).apply { addRow(arrayOf("ciphertext")) }
        }
        val result = RecordedResult()

        plugin.onMethodCall(
            MethodCall(
                "nostrsigner",
                hashMapOf("type" to "nip44_encrypt", "id" to "req-1", "package" to signerPackage),
            ),
            result,
        )

        assertTrue(provider.projections.isEmpty())
        assertEquals(1, backgroundTasks.size)
        runBackgroundTasks()
        assertEquals(1, result.replies)
    }

    @Test
    fun answersRejectedWithoutOpeningTheSignerAppWhenTheUserAlwaysRejects() {
        registerProvider("NIP44_ENCRYPT") { MatrixCursor(arrayOf("rejected")) }

        val result = encrypt("req-1")

        assertEquals(mapOf("rejected" to "true"), result.value)
        assertNull(nextStartedSigner())
    }

    @Test
    fun opensTheSignerAppWhenTheContentResolverCannotAnswer() {
        registerProvider("NIP44_ENCRYPT") { null }

        val result = encrypt("req-1")

        assertEquals(0, result.replies)
        val started = nextStartedSigner()
        assertEquals(Uri.parse("nostrsigner:hello"), started.intent.data)
        assertEquals(signerPackage, started.intent.`package`)
        assertEquals("nip44_encrypt", started.intent.getStringExtra("type"))
        assertEquals("req-1", started.intent.getStringExtra("id"))
        assertEquals(userPubkey, started.intent.getStringExtra("current_user"))
        assertEquals(peerPubkey, started.intent.getStringExtra("pubkey"))
        assertEquals(peerPubkey, started.intent.getStringExtra("pubKey"))

        plugin.onActivityResult(
            started.requestCode,
            Activity.RESULT_OK,
            Intent().putExtra("result", "ciphertext").putExtra("id", "req-1"),
        )

        assertEquals("ciphertext", (result.value as Map<*, *>)["signature"])
    }

    @Test
    fun opensTheSignerAppWhenTheContentResolverAnswersAnEmptyResult() {
        registerProvider("NIP44_ENCRYPT") {
            MatrixCursor(arrayOf("result")).apply { addRow(arrayOf("")) }
        }

        encrypt("req-1")

        assertEquals("nip44_encrypt", nextStartedSigner().intent.getStringExtra("type"))
    }

    @Test
    fun logsInThroughTheIntentOnly() {
        val provider = registerProvider("GET_PUBLIC_KEY") { null }

        call(
            "nostrsigner",
            mapOf("type" to "get_public_key", "uri_data" to "login", "package" to signerPackage),
        )

        assertTrue(provider.projections.isEmpty())
        assertEquals("get_public_key", nextStartedSigner().intent.getStringExtra("type"))
    }

    @Test
    fun skipsTheContentResolverWithoutAPackage() {
        val provider = registerProvider("NIP44_ENCRYPT") { null }

        encrypt("req-1", withPackage = false)

        assertTrue(provider.projections.isEmpty())
        assertNull(nextStartedSigner().intent.`package`)
    }

    @Test
    fun failsWithoutAnActivity() {
        plugin.onDetachedFromActivity()

        val result = encrypt("req-1")

        assertEquals("NO_ACTIVITY", result.errorCode)
        verify(activityBinding).removeActivityResultListener(plugin)
    }

    @Test
    fun failsWhenTheSignerAppCannotBeOpened() {
        shadowOf(application).checkActivities(true)

        val result = encrypt("req-1")

        assertEquals("LAUNCH_FAILED", result.errorCode)
    }

    @Test
    fun answersNoResultWhenTheSignerAppDoesNotReturnOk() {
        val result = encrypt("req-1")

        plugin.onActivityResult(nextStartedSigner().requestCode, Activity.RESULT_CANCELED, null)

        assertEquals(emptyMap<String, String?>(), result.value)
    }

    @Test
    fun passesOnARefusal() {
        val result = encrypt("req-1")

        plugin.onActivityResult(
            nextStartedSigner().requestCode,
            Activity.RESULT_OK,
            Intent().putExtra("rejected", true),
        )

        assertEquals(mapOf("rejected" to "true"), result.value)
    }

    @Test
    fun completesEachRequestOfBatchedResults() {
        val first = encrypt("req-1")
        nextStartedSigner()
        val second = encrypt("req-2")
        val results = JSONArray()
            .put(JSONObject().put("id", "req-1").put("result", "one"))
            .put(JSONObject().put("id", "req-2").put("result", "two"))

        plugin.onActivityResult(
            nextStartedSigner().requestCode,
            Activity.RESULT_OK,
            Intent().putExtra("results", results.toString()),
        )

        assertEquals("one", (first.value as Map<*, *>)["signature"])
        assertEquals("two", (second.value as Map<*, *>)["signature"])
    }

    @Test
    fun cancelStopsWaitingForTheSignerApp() {
        val result = encrypt("req-1")
        val requestCode = nextStartedSigner().requestCode

        val cancel = call("cancel", mapOf("id" to "req-1"))

        assertEquals(true, cancel.value)
        assertEquals("CANCELLED", result.errorCode)
        assertFalse(plugin.onActivityResult(requestCode, Activity.RESULT_OK, Intent()))
        assertEquals(false, call("cancel", mapOf("id" to "req-1")).value)
    }

    @Test
    fun cancelDuringTheContentResolverQueryDoesNotOpenTheSignerApp() {
        registerProvider("NIP44_ENCRYPT") { null }
        val result = RecordedResult()
        plugin.onMethodCall(
            MethodCall(
                "nostrsigner",
                hashMapOf("type" to "nip44_encrypt", "id" to "req-1", "package" to signerPackage),
            ),
            result,
        )

        val cancel = call("cancel", mapOf("id" to "req-1"))

        assertEquals(true, cancel.value)
        assertEquals("CANCELLED", result.errorCode)
        assertEquals(1, result.replies)
        assertNull(nextStartedSigner())
    }

    @Test
    fun checksTheSignerAppOfThePackage() {
        assertEquals(false, call("isAppInstalled", null).value)

        installSigner(signerPackage)

        assertEquals(true, call("isAppInstalled", null).value)
        assertEquals(true, call("isAppInstalled", mapOf("package" to signerPackage)).value)
        assertEquals(false, call("isAppInstalled", mapOf("package" to "com.example.other")).value)
    }
}
