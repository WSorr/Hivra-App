package com.hivra.hivra_app

import android.os.Bundle
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.util.PathUtils
import java.io.File
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private sealed class DocumentRequest(val result: MethodChannel.Result) {
        class Save(val source: File, result: MethodChannel.Result) : DocumentRequest(result)
        class Open(result: MethodChannel.Result) : DocumentRequest(result)
    }
    private var documentRequest: DocumentRequest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hivra/file_documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveJsonDocument" && call.method != "openDocument") {
                    result.notImplemented()
                } else if (documentRequest != null) {
                    result.error("document_in_progress", "A document dialog is already open", null)
                } else {
                    try {
                        val intent = if (call.method == "saveJsonDocument") {
                            val source = File(requireNotNull(call.argument<String>("sourcePath"))).canonicalFile
                            // Match the cache-dir-path used by Dart Directory.systemTemp.
                            val cache = File(PathUtils.getCacheDirectory(this)).canonicalFile
                            require(source.isFile && source.path.startsWith(cache.path + File.separator))
                            val name = requireNotNull(call.argument<String>("suggestedName"))
                            require(name.endsWith(".json") && !name.contains('/') && !name.contains('\\'))
                            documentRequest = DocumentRequest.Save(source, result)
                            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, name)
                            }
                        } else {
                            documentRequest = DocumentRequest.Open(result)
                            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                type = requireNotNull(call.argument<String>("mimeType"))
                                call.argument<String>("initialDirectory")?.let {
                                    if (android.os.Build.VERSION.SDK_INT >= 26) {
                                        putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(it))
                                    }
                                }
                            }
                        }
                        intent.addCategory(Intent.CATEGORY_OPENABLE)
                        startActivityForResult(intent, DOCUMENT_REQUEST)
                    } catch (_: Exception) {
                        documentRequest = null
                        result.error("document_unavailable", "Cannot open the document dialog", null)
                    }
                }
            }
    }

    @Deprecated("Activity result callback is required by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != DOCUMENT_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val request = documentRequest ?: return
        if (resultCode != Activity.RESULT_OK) {
            documentRequest = null
            request.result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null || uri.scheme != "content") {
            documentRequest = null
            request.result.error("invalid_document", "No document was selected", null)
            return
        }
        thread(name = "hivra-document-copy") {
            var staged: File? = null
            val copied = runCatching {
                when (request) {
                    is DocumentRequest.Save -> {
                        requireNotNull(contentResolver.openOutputStream(uri, "wt")).use { output ->
                            request.source.inputStream().use { input -> input.copyTo(output) }
                            output.flush()
                        }
                        uri.toString()
                    }
                    is DocumentRequest.Open -> {
                        val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                            if (it.moveToFirst()) it.getString(0) else null
                        } ?: "Selected document"
                        val directory = File.createTempFile("hivra-document-", "", File(PathUtils.getCacheDirectory(this)))
                        staged = directory
                        check(directory.delete() && directory.mkdir())
                        val file = File(directory, File(name).name)
                        // Provider display names cannot escape this private staging directory.
                        require(file.canonicalFile.parentFile == directory.canonicalFile)
                        requireNotNull(contentResolver.openInputStream(uri)).use { input ->
                            file.outputStream().use { output -> input.copyTo(output) }
                        }
                        file.path
                    }
                }
            }
            if (copied.isFailure) {
                staged?.deleteRecursively()
                if (request is DocumentRequest.Save) {
                    runCatching { DocumentsContract.deleteDocument(contentResolver, uri) }
                }
            }
            runOnUiThread {
                if (documentRequest === request) {
                    documentRequest = null
                    copied.fold(
                        onSuccess = { request.result.success(it) },
                        onFailure = { request.result.error("document_copy_failed", "The selected document could not be copied", null) },
                    )
                } else {
                    staged?.deleteRecursively()
                }
            }
        }
    }

    override fun onDestroy() {
        documentRequest?.result?.error("activity_closed", "The document operation was interrupted", null)
        documentRequest = null
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        HivraKeystoreBridge.init(applicationContext)
        super.onCreate(savedInstanceState)
    }

    companion object {
        private const val DOCUMENT_REQUEST = 0x4842
    }
}
