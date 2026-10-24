/*
 * vault.vala
 *
 * MATE Clipboard Manager
 * A clipboard history manager for the MATE Desktop
 *
 * Copyright 2025-2026 Kerem Soke
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 */

namespace Clipman {

public errordomain VaultError {
    INIT_FAILED,
    BAD_KEY,
    CORRUPT
}

/*
 * Owns the history key and seals everything that reaches the database.
 *
 * A random 256-bit master key lives in the user's login keyring (Secret
 * Service), never on disk next to the history.  Two subkeys are derived from
 * it: one for XChaCha20-Poly1305 encryption, one for the keyed BLAKE2b
 * digests used to spot duplicates without storing plain hashes of content.
 * The subkeys sit in mlock()ed memory and are wiped when the vault goes away.
 */
public class Vault : Object {
    private const size_t KEY_BYTES = 32;
    private const size_t DIGEST_BYTES = 32;
    private const string KDF_CONTEXT = "mclipman"; /* exactly 8 bytes */
    private const uint8 FORMAT_VERSION = 1;
    private const string AD_PREFIX = "mate-clipman/v1/";

    private uint8[] enc_key;
    private uint8[] mac_key;

    /* True when the key came from the keyring and history may be saved. */
    public bool persistent { get; private set; }

    private static Secret.Schema? _schema;

    private static Secret.Schema schema {
        get {
            if (_schema == null) {
                _schema = new Secret.Schema ("org.mate.Clipman.HistoryKey",
                                             Secret.SchemaFlags.NONE,
                                             "purpose", Secret.SchemaAttributeType.STRING);
            }
            return _schema;
        }
    }

    public static void init_crypto () throws VaultError {
        if (Sodium.init () < 0)
            throw new VaultError.INIT_FAILED ("libsodium could not be initialised");
    }

    /* Builds a vault from @master_key, which the caller should wipe after. */
    public Vault.from_key (uint8[] master_key, bool persistent) throws VaultError {
        if (master_key.length != KEY_BYTES)
            throw new VaultError.BAD_KEY ("history key has the wrong length");

        this.persistent = persistent;
        enc_key = new uint8[KEY_BYTES];
        mac_key = new uint8[KEY_BYTES];
        Sodium.mlock (enc_key, enc_key.length);
        Sodium.mlock (mac_key, mac_key.length);
        Sodium.kdf_derive_from_key (enc_key, enc_key.length, 1, KDF_CONTEXT, master_key);
        Sodium.kdf_derive_from_key (mac_key, mac_key.length, 2, KDF_CONTEXT, master_key);
    }

    /* A vault whose key exists only in memory, for history that is never saved. */
    public static Vault ephemeral () throws VaultError {
        var key = new uint8[KEY_BYTES];
        Sodium.random_bytes (key, key.length);
        try {
            return new Vault.from_key (key, false);
        } finally {
            Sodium.memzero (key, key.length);
        }
    }

    /*
     * Fetches the master key from the login keyring, creating it on first
     * use.  Unlocking the keyring may prompt the user, hence async.
     */
    public static async Vault from_keyring (Cancellable? cancellable) throws Error {
        string? secret = yield Secret.password_lookupv (schema, key_attributes (), cancellable);
        uint8[] key;

        if (secret != null) {
            key = Base64.decode (secret);
            wipe_string (secret);
        } else {
            key = new uint8[KEY_BYTES];
            Sodium.random_bytes (key, key.length);
            var encoded = Base64.encode (key);
            try {
                yield Secret.password_storev (schema, key_attributes (), Secret.COLLECTION_DEFAULT,
                                              _("MATE Clipboard Manager history key"),
                                              encoded, cancellable);
            } finally {
                wipe_string (encoded);
            }
        }

        try {
            return new Vault.from_key (key, true);
        } finally {
            Sodium.memzero (key, key.length);
        }
    }

    ~Vault () {
        /* sodium_munlock() zeroes the memory before unlocking it. */
        if (enc_key != null)
            Sodium.munlock (enc_key, enc_key.length);
        if (mac_key != null)
            Sodium.munlock (mac_key, mac_key.length);
    }

    /* Keyed BLAKE2b digest: equal content gives equal digests, but the
     * digest reveals nothing without the key. */
    public uint8[] digest (Bytes data) {
        var output = new uint8[DIGEST_BYTES];
        unowned uint8[] input = data.get_data ();
        Sodium.generichash (output, output.length, input, data.length, mac_key, mac_key.length);
        return output;
    }

    /*
     * Encrypts @plain.  @purpose and @digest are authenticated but not
     * stored, so a blob cannot be moved to another column or row unnoticed.
     * Layout: version byte | 24-byte nonce | ciphertext | 16-byte tag.
     */
    public Bytes seal (Bytes plain, string purpose, uint8[] digest) {
        var ad = associated_data (purpose, digest);
        size_t header = 1 + Sodium.Aead.NPUBBYTES;
        var output = new uint8[header + plain.length + Sodium.Aead.ABYTES];
        uint8* nonce = (uint8*) output + 1;

        output[0] = FORMAT_VERSION;
        Sodium.random_bytes (nonce, Sodium.Aead.NPUBBYTES);
        unowned uint8[] input = plain.get_data ();
        Sodium.Aead.encrypt ((uint8*) output + header, null, input, plain.length,
                             ad, ad.length, null, nonce, enc_key);
        return new Bytes.take ((owned) output);
    }

    public Bytes open (Bytes sealed, string purpose, uint8[] digest) throws VaultError {
        size_t header = 1 + Sodium.Aead.NPUBBYTES;
        unowned uint8[] input = sealed.get_data ();

        if (sealed.length < header + Sodium.Aead.ABYTES || input[0] != FORMAT_VERSION)
            throw new VaultError.CORRUPT ("encrypted record is malformed");

        var ad = associated_data (purpose, digest);
        var output = new uint8[sealed.length - header - Sodium.Aead.ABYTES];
        uint8* nonce = (uint8*) input + 1;
        if (Sodium.Aead.decrypt (output, null, null, (uint8*) input + header,
                                 sealed.length - header, ad, ad.length, nonce, enc_key) != 0) {
            throw new VaultError.CORRUPT ("encrypted record failed authentication");
        }
        return new Bytes.take ((owned) output);
    }

    public Bytes seal_string (string text, string purpose, uint8[] digest) {
        return seal (new Bytes (text.data), purpose, digest);
    }

    public string open_string (Bytes sealed, string purpose, uint8[] digest) throws VaultError {
        return bytes_to_string (open (sealed, purpose, digest));
    }

    private static uint8[] associated_data (string purpose, uint8[] digest) {
        var ad = new ByteArray ();
        ad.append ((AD_PREFIX + purpose).data);
        ad.append ({ 0 });
        ad.append (digest);
        return ad.steal ();
    }

    private static HashTable<string, string> key_attributes () {
        var attributes = new HashTable<string, string> (str_hash, str_equal);
        attributes["purpose"] = "history-key-v1";
        return attributes;
    }

    private static void wipe_string (string text) {
        Sodium.memzero (text, text.length);
    }
}

}
