/*
 * test-store.vala
 *
 * Exercises the encrypted store without a keyring or a display: a fixed
 * test key stands in for the one normally kept in the login keyring.
 */

using Clipman;

const string SECRET_TEXT = "correct horse battery staple";

uint8[] test_key (uint8 fill) {
    var key = new uint8[32];
    for (int i = 0; i < key.length; i++)
        key[i] = fill;
    return key;
}

string make_temp_dir () {
    try {
        return DirUtils.make_tmp ("clipman-test-XXXXXX");
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

Store open_store (string dir, uint8 fill, int limit) {
    try {
        return new Store (new Vault.from_key (test_key (fill), true), dir, limit);
    } catch (Error e) {
        error ("%s", e.message);
    }
}

Bytes text (string s) {
    return new Bytes (s.data);
}

string read_file (string path) {
    try {
        uint8[] contents;
        FileUtils.get_data (path, out contents);
        /* Search the raw bytes; the file is binary. */
        var builder = new StringBuilder ();
        foreach (var b in contents)
            builder.append_c (b == 0 ? ' ' : (char) b);
        return builder.str;
    } catch (FileError e) {
        error ("%s", e.message);
    }
}

void test_round_trip () {
    var dir = make_temp_dir ();
    var store = open_store (dir, 7, 10);
    var entry = store.add (Kind.TEXT, text (SECRET_TEXT), SECRET_TEXT, null);
    assert (entry != null);
    store = null;

    /* Reopening with the same key brings the item back. */
    store = open_store (dir, 7, 10);
    assert (store.length == 1);
    var loaded = store.get_entry (0);
    assert (loaded.preview == SECRET_TEXT);
    try {
        assert (bytes_to_string (store.load_payload (loaded)) == SECRET_TEXT);
    } catch (Error e) {
        error ("%s", e.message);
    }
    store = null;

    /* Neither the text nor its preview appear in the file. */
    var raw = read_file (Path.build_filename (dir, Store.DB_NAME));
    assert (!(SECRET_TEXT in raw));
    assert (!("horse" in raw));

    /* The database is private to the user. */
    Posix.Stat st;
    Posix.stat (Path.build_filename (dir, Store.DB_NAME), out st);
    assert ((st.st_mode & 0077) == 0);
    Posix.stat (dir, out st);
    assert ((st.st_mode & 0077) == 0);
}

void test_wrong_key_discards () {
    var dir = make_temp_dir ();
    var store = open_store (dir, 1, 10);
    store.add (Kind.TEXT, text ("first key"), "first key", null);
    store = null;

    /* A different key cannot read the rows, which are wiped. */
    Test.expect_message (null, LogLevelFlags.LEVEL_WARNING, "*different key*");
    store = open_store (dir, 2, 10);
    Test.assert_expected_messages ();
    assert (store.length == 0);
}

void test_limit_and_dedup () {
    var dir = make_temp_dir ();
    var store = open_store (dir, 3, 3);
    int removed = 0;
    store.removed.connect (() => removed++);

    for (int i = 0; i < 5; i++) {
        var s = "item %d".printf (i);
        store.add (Kind.TEXT, text (s), s, null);
    }
    /* Never grows past the limit, newest first. */
    assert (store.length == 3);
    assert (removed == 2);
    assert (store.get_entry (0).preview == "item 4");
    assert (store.get_entry (2).preview == "item 2");

    /* Copying something already stored moves it up instead of duplicating. */
    store.add (Kind.TEXT, text ("item 2"), "item 2", null);
    assert (store.length == 3);
    assert (store.get_entry (0).preview == "item 2");

    /* Same bytes as a different kind are a different item. */
    store.add (Kind.FILES, text ("item 2"), "item 2", null);
    assert (store.get_entry (0).kind == Kind.FILES);
    assert (store.length == 3);

    store.limit = 1;
    assert (store.length == 1);
    store = null;

    store = open_store (dir, 3, 50);
    assert (store.length == 1);

    store.clear ();
    assert (store.length == 0);
    store = null;
    store = open_store (dir, 3, 50);
    assert (store.length == 0);
}

void test_thumbnail_is_separate () {
    var dir = make_temp_dir ();
    var store = open_store (dir, 4, 10);
    var payload = new Bytes (new uint8[4096]);
    var thumb = text ("tiny thumbnail");
    var entry = store.add (Kind.IMAGE, payload, "640x480", thumb);
    assert (entry.label == "[Image 640x480]");
    store = null;

    store = open_store (dir, 4, 10);
    var loaded = store.get_entry (0);
    var loaded_thumb = store.load_thumbnail (loaded);
    assert (loaded_thumb != null && bytes_to_string (loaded_thumb) == "tiny thumbnail");
}

void test_memory_only () {
    try {
        var store = new Store (Vault.ephemeral (), null, 10);
        assert (!store.persistent);
        var entry = store.add (Kind.TEXT, text ("in memory"), "in memory", null);
        assert (bytes_to_string (store.load_payload (entry)) == "in memory");
        /* What is kept in memory is sealed, not plain. */
        assert (!("in memory" in bytes_to_string (entry.sealed_payload)));
    } catch (Error e) {
        error ("%s", e.message);
    }
}

void test_forget_disk () {
    var dir = make_temp_dir ();
    var store = open_store (dir, 5, 10);
    var entry = store.add (Kind.TEXT, text ("keep me"), "keep me", null);
    store.forget_disk ();
    assert (!store.persistent);
    assert (!FileUtils.test (Path.build_filename (dir, Store.DB_NAME), FileTest.EXISTS));
    try {
        assert (bytes_to_string (store.load_payload (entry)) == "keep me");
    } catch (Error e) {
        error ("%s", e.message);
    }
}

void test_png_dimensions () {
    uint8[] header = {
        0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n',
        0, 0, 0, 13, 'I', 'H', 'D', 'R',
        0, 0, 0x0a, 0x00,   /* width 2560 */
        0x00, 0x01, 0x00, 0x00  /* height 65536 */
    };
    uint32 w, h;
    assert (png_dimensions (new Bytes (header), out w, out h));
    assert (w == 2560 && h == 65536);
    /* 2560 x 65536 is past the pixel cap, so it would be skipped. */
    assert ((uint64) w * h > MAX_IMAGE_PIXELS);
    assert (!png_dimensions (new Bytes ("not a png at all, really".data), out w, out h));
}

void test_labels () {
    assert (create_label ("  hello\n\n\tworld  ", 100) == "hello world");
    assert (create_label ("abcdefghij", 8) == "abcde...");
    assert (utf8_prefix ("ğüşiöç", 3) == "ğüş");
    var files = new Entry (Kind.FILES, "file:///tmp/a.txt\nfile:///tmp/b.txt");
    assert (files.label == "[2 files]");
    var file = new Entry (Kind.FILES, "file:///tmp/a.txt");
    assert (file.label == "[File: a.txt]");
}

int main (string[] args) {
    Test.init (ref args);
    try {
        Vault.init_crypto ();
    } catch (VaultError e) {
        error ("%s", e.message);
    }

    Test.add_func ("/store/round-trip", test_round_trip);
    Test.add_func ("/store/wrong-key", test_wrong_key_discards);
    Test.add_func ("/store/limit-dedup", test_limit_and_dedup);
    Test.add_func ("/store/thumbnail", test_thumbnail_is_separate);
    Test.add_func ("/store/memory-only", test_memory_only);
    Test.add_func ("/store/forget-disk", test_forget_disk);
    Test.add_func ("/entry/labels", test_labels);
    Test.add_func ("/entry/png-dimensions", test_png_dimensions);
    return Test.run ();
}
