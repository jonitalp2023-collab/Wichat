package com.wichat.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient

class MainActivity : Activity() {

    private lateinit var web: WebView
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pauseWebViewRunnable: Runnable? = null
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    private val fileChooserRequestCode = 1001

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        web = WebView(this)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true

        // Consultar siempre la versión actual de GitHub Pages
        web.settings.cacheMode = WebSettings.LOAD_NO_CACHE

        web.webViewClient = WebViewClient()
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                this@MainActivity.filePathCallback?.onReceiveValue(null)
                this@MainActivity.filePathCallback = filePathCallback

                return try {
                    val chooserIntent = fileChooserParams?.createIntent()
                        ?: Intent(Intent.ACTION_GET_CONTENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "image/*"
                        }
                    startActivityForResult(chooserIntent, fileChooserRequestCode)
                    true
                } catch (error: Exception) {
                    this@MainActivity.filePathCallback?.onReceiveValue(null)
                    this@MainActivity.filePathCallback = null
                    false
                }
            }
        }

        setContentView(web)
        web.loadUrl("https://jonitalp2023-collab.github.io/Wichat/")
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != fileChooserRequestCode) return

        val callback = filePathCallback ?: return
        filePathCallback = null
        val results = if (resultCode == Activity.RESULT_OK) {
            WebChromeClient.FileChooserParams.parseResult(resultCode, data)
        } else {
            null
        }
        callback.onReceiveValue(results)
    }

    override fun onPause() {
        // Avisar a la página antes de pausar WebView. La liberación se hace
        // mediante la sesión autenticada de Supabase.
        if (::web.isInitialized) {
            web.evaluateJavascript(
                "if(window.chatAppOnBackground){window.chatAppOnBackground();}",
                null
            )
            pauseWebViewRunnable = Runnable { if (::web.isInitialized) web.onPause() }
            // Dar tiempo a Supabase para cerrar presencia y liberar el Nick antes de pausar WebView.
            mainHandler.postDelayed(pauseWebViewRunnable!!, 1500)
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
        }
    }

    override fun onDestroy() {
        filePathCallback?.onReceiveValue(null)
        filePathCallback = null
        super.onDestroy()
    }
}
