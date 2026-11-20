package com.wichat.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
    private var pendingAuthCallback: String? = null

    companion object {
        private const val FILE_CHOOSER_REQUEST_CODE = 4102
        private const val CHAT_HOST = "jonitalp2023-collab.github.io"
        private const val ASSET_HOST = "appassets.androidplatform.net"
        private const val SUPABASE_HOST = "pqnnzkqxkndzelsbtxvv.supabase.co"
        private const val CHAT_URL = "https://appassets.androidplatform.net/assets/index.html"
        private const val AUTH_SCHEME = "com.wichat.app"
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        pendingAuthCallback = authCallbackFrom(intent?.data)

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

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                deliverPendingAuthCallback()
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

        setContentView(web)
        web.loadUrl(CHAT_URL)
    }

    private fun authCallbackFrom(uri: Uri?): String? {
        if (uri?.scheme != AUTH_SCHEME ||
            uri.host != "auth" ||
            uri.path != "/callback"
        ) return null
        return uri.toString()
    }

    private fun routeNavigation(uri: Uri): Boolean {
        if (authCallbackFrom(uri) != null) {
            pendingAuthCallback = uri.toString()
            deliverPendingAuthCallback()
            return true
        }

        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()

        // Los recursos locales seguros y la web oficial permanecen dentro del WebView.
        if (scheme == "https" && (host == ASSET_HOST || host == CHAT_HOST)) return false

        // Google OAuth debe abrirse en el navegador del sistema, no en un WebView embebido.
        if (scheme == "https" && host == SUPABASE_HOST &&
            uri.path?.startsWith("/auth/v1/authorize") == true
        ) {
            return openExternal(uri)
        }

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

    private fun deliverPendingAuthCallback() {
        val callback = pendingAuthCallback ?: return
        if (!::web.isInitialized) return
        pendingAuthCallback = null
        val safeUrl = JSONObject.quote(callback)
        web.post {
            web.evaluateJavascript(
                "if (window.handleGoogleAuthCallback) window.handleGoogleAuthCallback($safeUrl);",
                null
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingAuthCallback = authCallbackFrom(intent.data)
        deliverPendingAuthCallback()
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
        pauseWebViewRunnable?.let { mainHandler.removeCallbacks(it) }
        pauseWebViewRunnable = null
        if (::web.isInitialized) {
            web.onResume()
            web.evaluateJavascript(
                "if(window.chatAppOnForeground){window.chatAppOnForeground();}",
                null
            )
            deliverPendingAuthCallback()
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
