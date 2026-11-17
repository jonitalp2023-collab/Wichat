package com.wichat.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject

class MainActivity : Activity() {
    private lateinit var web: WebView
    private var pendingAuthCallback: String? = null

    private inner class AndroidBridge {
        @JavascriptInterface
        fun isNativeApp(): Boolean = true
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        pendingAuthCallback = intent?.data?.takeIf { it.scheme == "com.wichat.app" }?.toString()

        web = WebView(this)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.loadWithOverviewMode = true
        web.settings.useWideViewPort = true
        web.addJavascriptInterface(AndroidBridge(), "Android")
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val uri = request?.url ?: return false
                // Google blocks OAuth inside embedded WebViews. Open Supabase's
                // authorization URL in the system browser; Supabase redirects
                // back to this app through the registered deep link.
                if (uri.host == "pqnnzkqxkndzelsbtxvv.supabase.co" &&
                    uri.path?.startsWith("/auth/v1/authorize") == true) {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    return true
                }
                return false
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                deliverPendingAuthCallback()
            }
        }
        setContentView(web)
        web.loadUrl("file:///android_asset/index.html")
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingAuthCallback = intent?.data?.takeIf { it.scheme == "com.wichat.app" }?.toString()
        deliverPendingAuthCallback()
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
}
