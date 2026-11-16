package com.wichat.app

import android.annotation.SuppressLint
import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient

class MainActivity : Activity() {

    private lateinit var web: WebView
    private val mainHandler = Handler(Looper.getMainLooper())

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        web = WebView(this)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true

        // Consultar siempre la versión actual de GitHub Pages
        web.settings.cacheMode = WebSettings.LOAD_NO_CACHE

        web.webViewClient = WebViewClient()
        web.webChromeClient = WebChromeClient()

        setContentView(web)
        web.loadUrl("https://jonitalp2023-collab.github.io/Wichat/")
    }

    override fun onPause() {
        // Avisar a la página antes de pausar WebView. La liberación se hace
        // mediante la sesión autenticada de Supabase.
        if (::web.isInitialized) {
            web.evaluateJavascript(
                "if(window.chatAppOnBackground){window.chatAppOnBackground();}",
                null
            )
            mainHandler.postDelayed({ if (::web.isInitialized) web.onPause() }, 400)
        }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (::web.isInitialized) {
            web.onResume()
            web.evaluateJavascript(
                "if(window.chatAppOnForeground){window.chatAppOnForeground();}",
                null
            )
        }
    }
}
