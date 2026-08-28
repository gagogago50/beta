package com.senlinjun.nek0

import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Portable, password-protected backup/restore of the TeamSpeak identity.
 *
 * The identity never leaves the app in plaintext: [encrypt] derives an AES key
 * from the user's password (PBKDF2-HMAC-SHA256, random salt, many iterations)
 * and seals the identity with AES-GCM. The result is a self-contained single
 * string the user can copy or save anywhere.
 *
 * Format (versioned, so a future iteration count or algorithm change stays
 * readable):  `nekobackup1:<iterations>:<salt_b64>:<payload_b64>`
 * where payload = IV || ciphertext, and GCM tag authenticates the whole thing,
 * so a wrong password or a tampered blob fails to decrypt instead of producing
 * garbage.
 *
 * The password is never stored. Exporting is the one moment the identity is
 * deliberately readable; everything else stays in Keystore-backed storage.
 */
class IdentityBackup {
    private val random = SecureRandom()

    companion object {
        private const val PREFIX = "nekobackup1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
        private const val GCM_IV_BYTES = 12
        private const val KEY_LEN_BITS = 256
        // Higher = slower to brute-force; on a phone this is still well under
        // a second. The official client's own backups are not even encrypted,
        // so this is already a large improvement over "no protection".
        private const val ITERATIONS = 200_000
        private const val SALT_BYTES = 16
        private const val MAX_PASSWORD = 1024
    }

    /** Returns a portable blob. Throws on empty password. */
    fun encrypt(plaintext: String, password: String): String {
        require(password.isNotBlank()) { "Password must not be empty" }
        require(password.length <= MAX_PASSWORD) { "Password is too long" }
        val salt = ByteArray(SALT_BYTES).also { random.nextBytes(it) }
        val key = deriveKey(password.toCharArray(), salt, ITERATIONS)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val ciphertext = cipher.doFinal(plaintext.toByteArray(StandardCharsets.UTF_8))
        val payload = cipher.iv + ciphertext
        val encoder = Base64.getEncoder()
        return arrayOf(
            PREFIX,
            ITERATIONS.toString(),
            encoder.encodeToString(salt),
            encoder.encodeToString(payload),
        ).joinToString(":")
    }

    /** Decrypts a blob produced by [encrypt]. Throws on a wrong password. */
    fun decrypt(blob: String, password: String): String {
        require(password.isNotBlank()) { "Password must not be empty" }
        val parts = blob.split(":")
        require(parts.size == 4 && parts[0] == PREFIX) { "Unrecognized backup format" }
        val iterations = parts[1].toIntOrNull()
            ?: throw IllegalArgumentException("Invalid backup iterations")
        val decoder = Base64.getDecoder()
        val salt = decoder.decode(parts[2])
        val payload = decoder.decode(parts[3])
        require(payload.size > GCM_IV_BYTES) { "Backup payload is too short" }
        val key = deriveKey(password.toCharArray(), salt, iterations)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(GCM_TAG_BITS, payload, 0, GCM_IV_BYTES),
        )
        val plaintext = cipher.doFinal(payload, GCM_IV_BYTES, payload.size - GCM_IV_BYTES)
        return String(plaintext, StandardCharsets.UTF_8)
    }

    private fun deriveKey(password: CharArray, salt: ByteArray, iterations: Int): SecretKeySpec {
        val spec = PBEKeySpec(password, salt, iterations, KEY_LEN_BITS)
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val bytes = factory.generateSecret(spec).encoded
        // Wipe the intermediate key material.
        spec.clearPassword()
        return SecretKeySpec(bytes, "AES")
    }
}
