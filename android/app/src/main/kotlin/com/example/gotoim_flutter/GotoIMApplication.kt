package com.example.gotoim_flutter

import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngineGroup

/**
 * Custom [FlutterApplication] that holds a [FlutterEngineGroup] singleton.
 *
 * The engine group allows creating lightweight FlutterEngines for MiniApp
 * tasks that share the Dart VM with the main application engine, reducing
 * memory overhead to ~180 KB per additional engine.
 */
class GotoIMApplication : FlutterApplication() {

    /** Single engine group shared by MainActivity and all MiniAppActivity instances. */
    lateinit var engineGroup: FlutterEngineGroup
        private set

    override fun onCreate() {
        super.onCreate()
        engineGroup = FlutterEngineGroup(this)
    }
}
