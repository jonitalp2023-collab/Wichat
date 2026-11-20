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
import android.webkit.JavascriptInterface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.SslErrorHandler
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import android.net.http.SslError
import org.json.JSONObject

class MainActivity : Activity() {

    private lateinit var web: WebView
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pauseWebViewRunnable: Runnable? = null
    private var filePathCallback: ValueCallback<Array<Uri>>? = null

    private val fcmBridge = FcmBridge()

    companion object {
        @Volatile
        var isAppInForeground = false
            private set

        private const val FILE_CHOOSER_REQUEST_CODE = 4102
        private const val CHAT_HOST = "jonitalp2023-collab.github.io"
        private const val ASSET_HOST = "appassets.androidplatform.net"
        private const val CHAT_URL = "https://appassets.androidplatform.net/assets/index.html"
        private const val REMOTE_BASE_URL = "https://jonitalp2023-collab.github.io/Wichat/releases/"
        private const val UPDATE_MANIFEST_URL = "https://jonitalp2023-collab.github.io/Wichat/version.json"
        private const val UPDATE_PREFS = "chatargentina_updates"
        private const val UPDATE_VERSION_KEY = "web_version"
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        requestNotificationPermissionIfNeeded()

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
                return routeNavigation(uri)
            }

            @Suppress("DEPRECATION")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                val uri = url?.let(Uri::parse) ?: return true
                return routeNavigation(uri)
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
        val installedWebVersion = getSharedPreferences(UPDATE_PREFS, MODE_PRIVATE)
            .getString(UPDATE_VERSION_KEY, null)
        if (installedWebVersion.isNullOrBlank()) {
            web.loadUrl(CHAT_URL)
        } else {
            web.loadUrl(REMOTE_BASE_URL + installedWebVersion + "/index.html")
        }
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

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4103)
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
                    .getString(UPDATE_VERSION_KEY, "local") ?: "local"
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
        fun requestFcmToken() {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (!task.isSuccessful) return@addOnCompleteListener
                val token = task.result ?: return@addOnCompleteListener
                val quoted = JSONObject.quote(token)
                if (::web.isInitialized) web.post {
                    web.evaluateJavascript("if(window.onNativeFcmToken){window.onNativeFcmToken($quoted);}", null)
                }
            }
        }
    }

    private fun routeNavigation(uri: Uri): Boolean {

        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()

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
            web.evaluateJavascript(
                "if(window.chatAppOnBackground){window.chatAppOnBackground();}",
                null
            )
            pauseWebViewRunnable = Runnable {
                if (::web.isInitialized) web.onPause()
            }
            mainHandler.postDelayed(pauseWebViewRunnable!!, 400)
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        isAppInForeground = true
        pauseWebViewRunnable?.let { mainHandler.removeCallbacks(it) }
        pauseWebViewRunnable = null
        if (::web.isInitialized) {
            web.onResume()
            web.evaluateJavascript(
                "if(window.chatAppOnForeground){window.chatAppOnForeground();}",
                null
            )
        }
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
        pauseWebViewRunnable?.let { mainHandler.removeCallbacks(it) }
        if (::web.isInitialized) {
            web.stopLoading()
            web.webChromeClient = null
            web.webViewClient = WebViewClient()
            web.destroy()
        }
        super.onDestroy()
    }
}
