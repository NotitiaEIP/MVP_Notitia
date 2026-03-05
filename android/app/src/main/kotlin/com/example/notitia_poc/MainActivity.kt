package com.example.notitia

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var nfcSharePlugin: NfcSharePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nfcSharePlugin = NfcSharePlugin(this, flutterEngine)
        nfcSharePlugin?.register()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        nfcSharePlugin?.unregister()
        nfcSharePlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
