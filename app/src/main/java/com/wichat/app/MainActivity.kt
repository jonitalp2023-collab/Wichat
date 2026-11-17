package com.wichat.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
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

    companion object {
        private const val FILE_CHOOSER_REQUEST_CODE = 4102
    }

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
                // Cancelar cualquier selector anterior que haya quedado pendiente.
                this@MainActivity.filePathCallback?.onReceiveValue(null)
                this@MainActivity.filePathCallback = filePathCallback

                return try {
                    val chooserIntent = fileChooserParams?.createIntent()
                        ?: throw ActivityNotFoundException("No se pudo preparar el selector de archivos")
                    startActivityForResult(chooserIntent, FILE_CHOOSER_REQUEST_CODE)
                    true
                } catch (_: ActivityNotFoundException) {
                    this@MainActivity.filePathCallback?.onReceiveValue(null)
                    this@MainActivity.filePathCallback = null
                    false
                } catch (_: Exception) {
                    this@MainActivity.filePathCallback?.onReceiveValue(null)
                    this@MainActivity.filePathCallback = null
                    false
                }
            }
        }

        setContentView(web)
        web.loadUrl("https://jonitalp2023-collab.github.io/Wichat/")
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
        // Avisar a la página antes de pausar WebView. La liberación se hace
        // mediante la sesión autenticada de Supabase.
        if (::web.isInitialized) {
            web.evaluateJavascript(
                "if(window.chatAppOnBackground){window.chatAppOnBackground();}",
                null
            )
            pauseWebViewRunnable = Runnable { if (::web.isInitialized) web.onPause() }
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
        }
    }

    override fun onDestroy() {
        filePathCallback?.onReceiveValue(null)
        filePathCallback = null
        pauseWebViewRunnable?.let { mainHandler.removeCallbacks(it) }
        if (::web.isInitialized) {
            web.destroy()
        }
        super.onDestroy()
    }
}
