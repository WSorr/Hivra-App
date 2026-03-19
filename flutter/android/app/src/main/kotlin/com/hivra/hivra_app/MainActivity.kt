package com.hivra.hivra_app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        HivraKeystoreBridge.init(applicationContext)
        super.onCreate(savedInstanceState)
    }
}
