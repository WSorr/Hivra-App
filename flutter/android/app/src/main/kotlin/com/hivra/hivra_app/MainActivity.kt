package com.hivra.hivra_app

import android.os.Bundle
import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private data class BackupSave(val source: File, val result: MethodChannel.Result)
    private var backupSave: BackupSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hivra/file_documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveJsonDocument") {
                    result.notImplemented()
                } else if (backupSave != null) {
                    result.error("save_in_progress", "A backup save is already open", null)
                } else {
                    try {
                        val source = File(requireNotNull(call.argument<String>("sourcePath"))).canonicalFile
                        require(source.isFile && source.path.startsWith(cacheDir.canonicalPath + File.separator))
                        val name = requireNotNull(call.argument<String>("suggestedName"))
                        require(name.endsWith(".json") && !name.contains('/') && !name.contains('\\'))
                        backupSave = BackupSave(source, result)
                        startActivityForResult(
                            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, name)
                            },
                            BACKUP_SAVE_REQUEST,
                        )
                    } catch (_: Exception) {
                        backupSave = null
                        result.error("save_unavailable", "Cannot open the backup save dialog", null)
                    }
                }
            }
    }

    @Deprecated("Activity result callback is required by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != BACKUP_SAVE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val save = backupSave ?: return
        if (resultCode != Activity.RESULT_OK) {
            backupSave = null
            save.result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null || uri.scheme != "content") {
            backupSave = null
            save.result.error("invalid_destination", "No backup document was selected", null)
            return
        }
        thread(name = "hivra-backup-save") {
            val written = runCatching {
                requireNotNull(contentResolver.openOutputStream(uri, "wt")).use { output ->
                    save.source.inputStream().use { input -> input.copyTo(output) }
                    output.flush()
                }
            }.isSuccess
            if (!written) {
                runCatching { DocumentsContract.deleteDocument(contentResolver, uri) }
            }
            runOnUiThread {
                if (backupSave === save) {
                    backupSave = null
                    if (written) save.result.success(uri.toString())
                    else save.result.error("write_failed", "The backup document could not be saved", null)
                }
            }
        }
    }

    override fun onDestroy() {
        backupSave?.result?.error("activity_closed", "The backup save was interrupted", null)
        backupSave = null
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        HivraKeystoreBridge.init(applicationContext)
        super.onCreate(savedInstanceState)
    }

    companion object {
        private const val BACKUP_SAVE_REQUEST = 0x4842
    }
}
