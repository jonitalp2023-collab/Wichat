package com.wichat.app

import android.annotation.SuppressLint
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.media.MediaRecorder
import android.util.Base64
import java.io.File
import android.webkit.JavascriptInterface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import android.webkit.CookieManager
import android.webkit.SslErrorHandler
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.PermissionRequest
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import android.net.http.SslError
import org.json.JSONObject

class MainActivity : Activity() {

    private lateinit var web: WebView
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private var pendingAudioPermissionRequest: PermissionRequest? = null
    private var nativeAudioRecorder: MediaRecorder? = null
    private var nativeAudioFile: File? = null
    private var pendingNativeAudioStart = false

    private val fcmBridge = FcmBridge()
    private var pendingPushIntent: Intent? = null
    private var pushNavigationAttempts = 0

    companion object {
        @Volatile
        var isAppInForeground = false
            private set

        private const val FILE_CHOOSER_REQUEST_CODE = 4102
        private const val AUDIO_PERMISSION_REQUEST_CODE = 4104
        private const val NATIVE_AUDIO_PERMISSION_REQUEST_CODE = 4105
        private const val CHAT_HOST = "jonitalp2023-collab.github.io"
        private const val ASSET_HOST = "appassets.androidplatform.net"
        private const val CHAT_URL = "https://appassets.androidplatform.net/assets/index.html"
        private const val REMOTE_BASE_URL = "https://jonitalp2023-collab.github.io/Wichat/releases/"
        private const val UPDATE_MANIFEST_URL = "https://jonitalp2023-collab.github.io/Wichat/version.json"
        private const val UPDATE_PREFS = "chatargentina_updates"
        private const val UPDATE_VERSION_KEY = "web_version_v2"
        private const val BUNDLED_WEB_VERSION = "1.4.1"
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingPushIntent = intent?.takeIf { it.hasExtra("push_kind") }
        createNotificationChannel()

        web = WebView(this)
        val assetLoader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this))
            .build()

        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            allowFileAccess = false
            allowContentAccess = false
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                safeBrowsingEnabled = true
            }
        }

        CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(web, false)
        }
        WebView.setWebContentsDebuggingEnabled(false)

        web.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                processPendingPushNavigation()
            }

            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: android.webkit.WebResourceResponse?
            ) {
                super.onReceivedHttpError(view, request, errorResponse)
                val uri = request?.url ?: return
                val statusCode = errorResponse?.statusCode ?: return
                if (request.isForMainFrame && statusCode >= 400 && isRemoteReleaseUrl(uri)) {
                    // La versión remota ya no existe: volver al contenido incluido en el APK.
                    getSharedPreferences(UPDATE_PREFS, MODE_PRIVATE).edit()
                        .remove(UPDATE_VERSION_KEY).apply()
                    view?.post { view.loadUrl(CHAT_URL) }
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: android.webkit.WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                val uri = request?.url ?: return
                if (request.isForMainFrame && isRemoteReleaseUrl(uri)) {
                    getSharedPreferences(UPDATE_PREFS, MODE_PRIVATE).edit()
                        .remove(UPDATE_VERSION_KEY).apply()
                    view?.post { view.loadUrl(CHAT_URL) }
                }
            }

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?
            ): android.webkit.WebResourceResponse? {
                val uri = request?.url ?: return null
                return assetLoader.shouldInterceptRequest(uri)
            }

            @Suppress("DEPRECATION")
            override fun shouldInterceptRequest(
                view: WebView?,
                url: String?
            ): android.webkit.WebResourceResponse? {
                val uri = url?.let(Uri::parse) ?: return null
                return assetLoader.shouldInterceptRequest(uri)
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val uri = request?.url ?: return true
                return routeNavigation(uri, view)
            }

            @Suppress("DEPRECATION")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                val uri = url?.let(Uri::parse) ?: return true
                return routeNavigation(uri, view)
            }

            override fun onReceivedSslError(
                view: WebView?,
                handler: SslErrorHandler?,
                error: SslError?
            ) {
                handler?.cancel()
            }
        }

        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                runOnUiThread {
                    val originHost = request.origin.host.orEmpty()
                    val trustedOrigin = originHost.equals(ASSET_HOST, ignoreCase = true) ||
                        originHost.equals(CHAT_HOST, ignoreCase = true)
                    val wantsAudio = request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)
                    if (!trustedOrigin || !wantsAudio) {
                        request.deny()
                        return@runOnUiThread
                    }
                    if (ContextCompat.checkSelfPermission(
                            this@MainActivity,
                            android.Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                    ) {
                        request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                    } else {
                        pendingAudioPermissionRequest?.deny()
                        pendingAudioPermissionRequest = request
                        ActivityCompat.requestPermissions(
                            this@MainActivity,
                            arrayOf(android.Manifest.permission.RECORD_AUDIO),
                            AUDIO_PERMISSION_REQUEST_CODE
                        )
                    }
                }
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                if (pendingAudioPermissionRequest == request) pendingAudioPermissionRequest = null
            }

            override fun onShowFileChooser(
                webView: WebView?,
                callback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                filePathCallback?.onReceiveValue(null)
                filePathCallback = callback

                return try {
                    val chooserIntent = fileChooserParams?.createIntent()
                        ?: throw ActivityNotFoundException("No se pudo preparar el selector de archivos")
                    startActivityForResult(chooserIntent, FILE_CHOOSER_REQUEST_CODE)
                    true
                } catch (_: Exception) {
                    filePathCallback?.onReceiveValue(null)
                    filePathCallback = null
                    false
                }
            }
        }

        web.addJavascriptInterface(fcmBridge, "ChatArgentinaNative")
        setContentView(web)
        // Restaurar el WebView evita recargar el chat al recrearse la Activity.
        val restored = savedInstanceState != null && web.restoreState(savedInstanceState) != null
        if (!restored) {
            val installedWebVersion = getSharedPreferences(UPDATE_PREFS, MODE_PRIVATE)
                .getString(UPDATE_VERSION_KEY, null)
            if (installedWebVersion.isNullOrBlank()) {
                web.loadUrl(CHAT_URL)
            } else {
                web.loadUrl(REMOTE_BASE_URL + installedWebVersion + "/index.html")
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent?.hasExtra("push_kind") == true) {
            pendingPushIntent = intent
            pushNavigationAttempts = 0
            processPendingPushNavigation()
        }
    }

    // Espera hasta que el usuario haya ingresado al chat, incluso con inicio en frío.
    private fun processPendingPushNavigation() {
        val push = pendingPushIntent ?: return
        if (!::web.isInitialized) return
        val kind = push.getStringExtra("push_kind").orEmpty()
        val roomId = push.getStringExtra("push_room_id").orEmpty()
        val targetSenderId = push.getStringExtra("push_sender_id").orEmpty()
        val senderNickname = push.getStringExtra("push_sender_nickname").orEmpty()
        if (kind != "private" && kind != "room") {
            pendingPushIntent = null
            return
        }
        val script = if (kind == "private") {
            "(function(){if(typeof senderId==='undefined'||!senderId||typeof openPrivateChat!=='function')return false;showMainTab('chat');openPrivateChat({id:" +
                JSONObject.quote(targetSenderId) + ",nick:" + JSONObject.quote(senderNickname.ifBlank { "Usuario" }) +
                "});return true;})();"
        } else {
            "(function(){if(typeof senderId==='undefined'||!senderId||typeof switchRoom!=='function')return false;showMainTab('chat');switchRoom(" +
                JSONObject.quote(roomId) + ");return true;})();"
        }
        web.evaluateJavascript(script) { result ->
            if (result == "true") {
                pendingPushIntent = null
                pushNavigationAttempts = 0
            } else if (pendingPushIntent === push && pushNavigationAttempts < 180) {
                pushNavigationAttempts++
                web.postDelayed({ processPendingPushNavigation() }, 1000)
            }
        }
    }

    private fun notifyWebAudioStarted(success: Boolean, error: String = "") {
        if (!::web.isInitialized) return
        val quoted = JSONObject.quote(error)
        web.post { web.evaluateJavascript("window.onNativeVoiceRecordingStarted($success,$quoted);", null) }
    }

    private fun notifyWebAudioFinished(base64: String, mime: String, error: String = "") {
        if (!::web.isInitialized) return
        val encoded = JSONObject.quote(base64)
        val quotedMime = JSONObject.quote(mime)
        val quotedError = JSONObject.quote(error)
        web.post {
            web.evaluateJavascript(
                "window.onNativeVoiceRecordingFinished($encoded,$quotedMime,$quotedError);",
                null
            )
        }
    }

    private fun startNativeAudioCapture() {
        if (nativeAudioRecorder != null) return
        val output = File(cacheDir, "chatargentina_voice_${System.currentTimeMillis()}.m4a")
        val recorder = MediaRecorder()
        try {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(96000)
            recorder.setAudioSamplingRate(44100)
            recorder.setMaxDuration(60000)
            recorder.setOutputFile(output.absolutePath)
            recorder.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) {
                    finishNativeAudioCapture()
                }
            }
            recorder.setOnErrorListener { _, _, _ ->
                finishNativeAudioCapture()
            }
            recorder.prepare()
            recorder.start()
            nativeAudioRecorder = recorder
            nativeAudioFile = output
            notifyWebAudioStarted(true)
        } catch (error: Exception) {
            try { recorder.reset(); recorder.release() } catch (_: Exception) {}
            output.delete()
            notifyWebAudioStarted(false, error.message ?: "No se pudo iniciar el micrófono.")
        }
    }

    private fun finishNativeAudioCapture() {
        val recorder = nativeAudioRecorder ?: return
        val output = nativeAudioFile
        nativeAudioRecorder = null
        nativeAudioFile = null
        var failure: String? = null
        try {
            recorder.stop()
        } catch (error: Exception) {
            failure = "La grabación fue demasiado corta o se interrumpió."
        } finally {
            try { recorder.reset(); recorder.release() } catch (_: Exception) {}
        }
        if (failure != null || output == null || !output.exists() || output.length() < 900) {
            output?.delete()
            notifyWebAudioFinished("", "audio/mp4", failure ?: "El audio quedó demasiado corto.")
            return
        }
        try {
            val encoded = Base64.encodeToString(output.readBytes(), Base64.NO_WRAP)
            output.delete()
            notifyWebAudioFinished(encoded, "audio/mp4")
        } catch (error: Exception) {
            output.delete()
            notifyWebAudioFinished("", "audio/mp4", error.message ?: "No se pudo preparar el audio.")
        }
    }

    private fun isRemoteReleaseUrl(uri: Uri): Boolean {
        return uri.scheme.equals("https", ignoreCase = true) &&
            uri.host.equals(CHAT_HOST, ignoreCase = true) &&
            uri.path.orEmpty().startsWith("/Wichat/releases/")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ChatFirebaseMessagingService.CHANNEL_ID,
                "Mensajes de ChatArgentina",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Notificaciones de nuevos mensajes" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    // Las notificaciones se solicitan cuando el usuario ya ingresó al chat.
    // FCM permanece desactivado hasta que el usuario concede el permiso.
    private fun requestFcmTokenWithPermission() {
        runOnUiThread {
            if (Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                val notificationPrefs = getSharedPreferences(
                    "chatargentina_notifications",
                    MODE_PRIVATE
                )
                if (notificationPrefs.getBoolean("permission_asked", false)) {
                    return@runOnUiThread
                }
                notificationPrefs.edit().putBoolean("permission_asked", true).apply()
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    4103
                )
                return@runOnUiThread
            }
            registerFcmToken()
        }
    }

    private fun registerFcmToken() {
        FirebaseMessaging.getInstance().setAutoInitEnabled(true)
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) return@addOnCompleteListener
            val token = task.result ?: return@addOnCompleteListener
            val quoted = JSONObject.quote(token)
            if (::web.isInitialized) web.post {
                web.evaluateJavascript("if(window.onNativeFcmToken){window.onNativeFcmToken($quoted);}", null)
            }
        }
    }

    @Deprecated("Deprecated in Android, kept for notification permission callback compatibility")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NATIVE_AUDIO_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            val shouldStart = pendingNativeAudioStart
            pendingNativeAudioStart = false
            if (granted && shouldStart) startNativeAudioCapture()
            else notifyWebAudioStarted(false, "No se concedió el permiso de micrófono.")
            return
        }
        if (requestCode == AUDIO_PERMISSION_REQUEST_CODE) {
            val request = pendingAudioPermissionRequest
            pendingAudioPermissionRequest = null
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                request?.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
            } else {
                request?.deny()
            }
            return
        }
        if (requestCode != 4103) return
        getSharedPreferences("chatargentina_notifications", MODE_PRIVATE)
            .edit().putBoolean("permission_asked", true).apply()
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            registerFcmToken()
        } else {
            FirebaseMessaging.getInstance().setAutoInitEnabled(false)
        }
    }

    inner class FcmBridge {
        @JavascriptInterface
        fun getAvailableWebUpdate(): String {
            return try {
                val connection = java.net.URL(UPDATE_MANIFEST_URL).openConnection() as java.net.HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.setRequestProperty("Cache-Control", "no-cache")
                val body = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                connection.disconnect()
                val manifest = JSONObject(body)
                val latest = manifest.optString("version", "")
                val installed = getSharedPreferences(UPDATE_PREFS, MODE_PRIVATE)
                    .getString(UPDATE_VERSION_KEY, BUNDLED_WEB_VERSION) ?: BUNDLED_WEB_VERSION
                if (!latest.matches(Regex("""\d+\.\d+\.\d+""")) || latest == installed) {
                    JSONObject().put("available", false).toString()
                } else {
                    JSONObject().put("available", true)
                        .put("version", latest)
                        .put("notes", manifest.optString("notes", "Mejoras y correcciones."))
                        .toString()
                }
            } catch (_: Exception) {
                JSONObject().put("available", false).toString()
            }
        }

        @JavascriptInterface
        fun applyWebUpdate(version: String) {
            if (!version.matches(Regex("""\d+\.\d+\.\d+"""))) return
            getSharedPreferences(UPDATE_PREFS, MODE_PRIVATE).edit()
                .putString(UPDATE_VERSION_KEY, version).apply()
            runOnUiThread { recreate() }
        }

        @JavascriptInterface
        fun startVoiceRecording() {
            runOnUiThread {
                if (nativeAudioRecorder != null) return@runOnUiThread
                if (ContextCompat.checkSelfPermission(
                        this@MainActivity,
                        android.Manifest.permission.RECORD_AUDIO
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    pendingNativeAudioStart = true
                    ActivityCompat.requestPermissions(
                        this@MainActivity,
                        arrayOf(android.Manifest.permission.RECORD_AUDIO),
                        NATIVE_AUDIO_PERMISSION_REQUEST_CODE
                    )
                } else {
                    startNativeAudioCapture()
                }
            }
        }

        @JavascriptInterface
        fun stopVoiceRecording() {
            runOnUiThread { finishNativeAudioCapture() }
        }

        @JavascriptInterface
        fun requestFcmToken() {
            requestFcmTokenWithPermission()
        }
    }

    private fun routeNavigation(uri: Uri, view: WebView?): Boolean {

        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()

        // Si un enlace relativo apunta al directorio /assets/ (sin index.html),
        // abrir explícitamente la pantalla principal en vez de mostrar un error WebView.
        if (scheme == "https" && host == ASSET_HOST && uri.path == "/assets/") {
            view?.loadUrl(CHAT_URL)
            return true
        }

        // Los recursos locales seguros y la web oficial permanecen dentro del WebView.
        if (scheme == "https" && (host == ASSET_HOST || host == CHAT_HOST)) return false

        // El resto de destinos no confiables nunca se carga dentro del WebView.
        return openExternal(uri)
    }

    private fun openExternal(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase()
        if (scheme != "https" && scheme != "mailto" && scheme != "tel") return true

        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            true
        } catch (_: ActivityNotFoundException) {
            true
        } catch (_: SecurityException) {
            true
        }
    }

    @Deprecated("Deprecated in Android, kept for WebView file chooser compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FILE_CHOOSER_REQUEST_CODE) return

        val callback = filePathCallback ?: return
        val results = if (resultCode == Activity.RESULT_OK) {
            WebChromeClient.FileChooserParams.parseResult(resultCode, data)
        } else {
            null
        }
        callback.onReceiveValue(results)
        filePathCallback = null
    }

    override fun onPause() {
        isAppInForeground = false
        if (::web.isInitialized) {
            // Mantener vivo el WebView al cambiar a otra aplicación.
            // No pausar sus procesos: al volver se conserva la pantalla y el chat.
            web.evaluateJavascript(
                "if(window.chatAppOnBackground){window.chatAppOnBackground();}",
                null
            )
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
        if (::web.isInitialized) {
            web.onResume()
            web.evaluateJavascript(
                "if(window.chatAppOnForeground){window.chatAppOnForeground();}",
                null
            )
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        if (::web.isInitialized) web.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (::web.isInitialized && web.canGoBack()) {
            web.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        filePathCallback?.onReceiveValue(null)
        filePathCallback = null
        pendingAudioPermissionRequest?.deny()
        pendingAudioPermissionRequest = null
        try { nativeAudioRecorder?.stop() } catch (_: Exception) {}
        try { nativeAudioRecorder?.release() } catch (_: Exception) {}
        nativeAudioRecorder = null
        nativeAudioFile?.delete()
        nativeAudioFile = null
        if (::web.isInitialized) {
            web.stopLoading()
            web.webChromeClient = null
            web.webViewClient = WebViewClient()
            web.destroy()
        }
        super.onDestroy()
    }
}
