package com.hivra.hivra_app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.annotation.Keep
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

@Keep
object HivraKeystoreBridge {
    private const val STORE_NAME = "hivra_keystore_v1"
    private const val KEY_ALIAS = "hivra_seed_wrap_key_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"

    @Volatile
    private var appContext: Context? = null

    @JvmStatic
    @Keep
    fun init(context: Context) {
        if (appContext == null) {
            appContext = context.applicationContext
        }
        System.loadLibrary("hivra_ffi")
        nativeInit()
    }

    @JvmStatic
    @Keep
    external fun nativeInit()

    @Keep
    fun storeSeedBlob(account: String, encodedSeed: String): Boolean {
        return runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
            val ciphertext = cipher.doFinal(encodedSeed.toByteArray(StandardCharsets.UTF_8))
            val iv = cipher.iv ?: return false
            prefs().edit()
                .putString(account, pack(iv, ciphertext))
                .apply()
            true
        }.getOrDefault(false)
    }

    @Keep
    fun loadSeedBlob(account: String): String? {
        return runCatching {
            val packed = prefs().getString(account, null) ?: return null
            val (iv, ciphertext) = unpack(packed)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateSecretKey(),
                GCMParameterSpec(128, iv),
            )
            val plaintext = cipher.doFinal(ciphertext)
            String(plaintext, StandardCharsets.UTF_8)
        }.getOrNull()
    }

    @Keep
    fun deleteSeedBlob(account: String): Boolean {
        return runCatching {
            prefs().edit().remove(account).apply()
            true
        }.getOrDefault(false)
    }

    @Keep
    fun seedBlobExists(account: String): Boolean {
        return runCatching { prefs().contains(account) }.getOrDefault(false)
    }

    private fun prefs() = requireNotNull(appContext) {
        "HivraKeystoreBridge not initialized"
    }.getSharedPreferences(STORE_NAME, Context.MODE_PRIVATE)

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) {
            return existing
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE,
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun pack(iv: ByteArray, ciphertext: ByteArray): String {
        return "${Base64.encodeToString(iv, Base64.NO_WRAP)}:${Base64.encodeToString(ciphertext, Base64.NO_WRAP)}"
    }

    private fun unpack(packed: String): Pair<ByteArray, ByteArray> {
        val parts = packed.split(':', limit = 2)
        require(parts.size == 2) { "Invalid ciphertext payload" }
        return Base64.decode(parts[0], Base64.NO_WRAP) to
            Base64.decode(parts[1], Base64.NO_WRAP)
    }
}
