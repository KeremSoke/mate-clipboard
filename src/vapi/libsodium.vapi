/* Minimal binding for the parts of libsodium used by mate-clipman. */

[CCode (cheader_filename = "sodium.h", lower_case_cprefix = "")]
namespace Sodium {
	[CCode (cname = "sodium_init")]
	public int init ();

	[CCode (cname = "randombytes_buf")]
	public void random_bytes (void* buf, size_t size);

	[CCode (cname = "sodium_memzero")]
	public void memzero (void* pnt, size_t len);

	[CCode (cname = "sodium_mlock")]
	public int mlock (void* addr, size_t len);

	/* Zeroes the memory before unlocking it. */
	[CCode (cname = "sodium_munlock")]
	public int munlock (void* addr, size_t len);

	[CCode (cname = "crypto_kdf_KEYBYTES")]
	public const size_t KDF_KEYBYTES;

	[CCode (cname = "crypto_kdf_derive_from_key")]
	public int kdf_derive_from_key (uint8* subkey, size_t subkey_len, uint64 subkey_id, string ctx, uint8* key);

	[CCode (cname = "crypto_generichash")]
	public int generichash (uint8* output, size_t outlen, uint8* input, uint64 inlen, uint8* key, size_t keylen);

	/* XChaCha20-Poly1305 (IETF) authenticated encryption. */
	namespace Aead {
		[CCode (cname = "crypto_aead_xchacha20poly1305_ietf_KEYBYTES")]
		public const size_t KEYBYTES;
		[CCode (cname = "crypto_aead_xchacha20poly1305_ietf_NPUBBYTES")]
		public const size_t NPUBBYTES;
		[CCode (cname = "crypto_aead_xchacha20poly1305_ietf_ABYTES")]
		public const size_t ABYTES;

		[CCode (cname = "crypto_aead_xchacha20poly1305_ietf_encrypt")]
		public int encrypt (uint8* c, void* clen_p, uint8* m, uint64 mlen, uint8* ad, uint64 adlen, void* nsec, uint8* npub, uint8* k);

		[CCode (cname = "crypto_aead_xchacha20poly1305_ietf_decrypt")]
		public int decrypt (uint8* m, void* mlen_p, void* nsec, uint8* c, uint64 clen, uint8* ad, uint64 adlen, uint8* npub, uint8* k);
	}
}
