/*
 * store.vala
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

public errordomain StoreError {
    FAILED
}

/*
 * Clipboard history, newest first.
 *
 * Entries (id, kind, timestamp and the decrypted preview) are kept in memory
 * so the history dialog never has to touch the disk.  Payloads and
 * thumbnails are only decrypted on demand.  When the vault is persistent the
 * sealed blobs go to an SQLite database readable only by the user;
 * otherwise they stay sealed in memory under a throwaway key.
 *
 * Every SQL statement uses bound parameters; no content is ever spliced
 * into SQL text.
 */
public class Store : Object {
    public const string DB_NAME = "history-v2.sqlite";
    private const int SCHEMA_VERSION = 1;
    private const string CANARY = "mate-clipman";

    public signal void added (Entry entry);
    public signal void promoted (Entry entry);
    public signal void removed (Entry entry);
    public signal void cleared ();

    private Vault vault;
    private Sqlite.Database? db;
    private string? db_path;
    private GenericArray<Entry> entries = new GenericArray<Entry> ();
    private HashTable<string, Entry> by_key = new HashTable<string, Entry> (str_hash, str_equal);
    private int64 next_memory_id = 1;
    private int _limit = 50;

    public bool persistent {
        get { return db != null; }
    }

    public int limit {
        get { return _limit; }
        set {
            _limit = value.clamp (1, 1000);
            trim ();
        }
    }

    public uint length {
        get { return entries.length; }
    }

    public Store (Vault vault, string? data_dir, int limit) throws Error {
        this.vault = vault;
        _limit = limit.clamp (1, 1000);

        if (vault.persistent && data_dir != null) {
            open_database (data_dir);
            load_entries ();
        }
    }

    public static string default_data_dir () {
        return Path.build_filename (Environment.get_user_data_dir (), "mate-clipman");
    }

    public Entry? get_entry (uint index) {
        return index < entries.length ? entries[index] : null;
    }

    public void @foreach (Func<Entry> func) {
        entries.foreach (func);
    }

    /*
     * Records new clipboard content and returns its entry.  Content already
     * in the history is moved to the top instead of being stored twice.
     */
    public Entry? add (Kind kind, Bytes payload, string preview, Bytes? thumbnail) {
        var digest = vault.digest (payload);
        var existing = by_key[Entry.key_for (kind, digest)];
        if (existing != null) {
            promote (existing);
            return existing;
        }

        var entry = new Entry (kind, preview);
        entry.digest = digest;
        entry.stamp = get_real_time ();

        var sealed_payload = vault.seal (payload, "payload", digest);
        Bytes? sealed_thumb = thumbnail != null ? vault.seal (thumbnail, "thumbnail", digest) : null;

        if (db != null) {
            Sqlite.Statement stmt;
            prepare ("INSERT INTO items (kind, digest, stamp, preview, thumbnail, payload) "
                     + "VALUES (?1, ?2, ?3, ?4, ?5, ?6)", out stmt);
            var sealed_preview = vault.seal_string (preview, "preview", digest);
            var digest_bytes = new Bytes (digest);
            stmt.bind_int (1, kind);
            bind_bytes (stmt, 2, digest_bytes);
            stmt.bind_int64 (3, entry.stamp);
            bind_bytes (stmt, 4, sealed_preview);
            bind_bytes (stmt, 5, sealed_thumb);
            bind_bytes (stmt, 6, sealed_payload);
            if (stmt.step () != Sqlite.DONE) {
                warning ("Could not save clipboard item: %s", db.errmsg ());
                return null;
            }
            entry.id = db.last_insert_rowid ();
        } else {
            entry.id = next_memory_id++;
            entry.sealed_payload = sealed_payload;
            entry.sealed_thumb = sealed_thumb;
        }

        entries.insert (0, entry);
        by_key[entry.map_key] = entry;
        added (entry);
        trim ();
        return entry;
    }

    /* Moves @entry to the top of the history. */
    public void promote (Entry entry) {
        uint index;
        if (!entries.find (entry, out index))
            return;

        entry.stamp = get_real_time ();
        if (db != null) {
            Sqlite.Statement stmt;
            prepare ("UPDATE items SET stamp = ?1 WHERE id = ?2", out stmt);
            stmt.bind_int64 (1, entry.stamp);
            stmt.bind_int64 (2, entry.id);
            stmt.step ();
        }

        if (index != 0) {
            entries.remove_index (index);
            entries.insert (0, entry);
        }
        promoted (entry);
    }

    public void remove (Entry entry) {
        if (!entries.remove (entry))
            return;

        by_key.remove (entry.map_key);
        delete_rows ({ entry.id });
        removed (entry);
        compact ();
    }

    public void clear () {
        entries.remove_range (0, entries.length);
        by_key.remove_all ();
        if (db != null)
            exec ("DELETE FROM items");
        cleared ();
        compact ();
    }

    public Bytes load_payload (Entry entry) throws Error {
        var sealed = entry.sealed_payload ?? load_blob (entry, "payload");
        if (sealed == null)
            throw new StoreError.FAILED ("clipboard item is missing");
        return vault.open (sealed, "payload", entry.digest);
    }

    public Bytes? load_thumbnail (Entry entry) {
        try {
            var sealed = entry.sealed_thumb ?? load_blob (entry, "thumbnail");
            return sealed != null ? vault.open (sealed, "thumbnail", entry.digest) : null;
        } catch (Error e) {
            warning ("Could not read thumbnail: %s", e.message);
            return null;
        }
    }

    /*
     * Stops saving history: pulls every sealed blob into memory, then
     * deletes the database file so nothing remains on disk.
     */
    public void forget_disk () {
        if (db == null)
            return;

        foreach (var entry in entries.data) {
            entry.sealed_payload = load_blob (entry, "payload");
            entry.sealed_thumb = load_blob (entry, "thumbnail");
        }

        exec ("DELETE FROM items");
        exec ("VACUUM");
        db = null;
        foreach (var suffix in new string[] { "", "-journal", "-wal", "-shm" })
            FileUtils.unlink (db_path + suffix);
    }

    private void trim () {
        if (entries.length <= _limit)
            return;

        int64[] ids = {};
        var dropped = new GenericArray<Entry> ();
        while (entries.length > _limit) {
            var entry = entries[entries.length - 1];
            entries.remove_index (entries.length - 1);
            by_key.remove (entry.map_key);
            ids += entry.id;
            dropped.add (entry);
        }

        delete_rows (ids);
        foreach (var entry in dropped.data)
            removed (entry);
        compact ();
    }

    private void delete_rows (int64[] ids) {
        if (db == null || ids.length == 0)
            return;

        exec ("BEGIN");
        Sqlite.Statement stmt;
        prepare ("DELETE FROM items WHERE id = ?1", out stmt);
        foreach (var id in ids) {
            stmt.bind_int64 (1, id);
            stmt.step ();
            stmt.reset ();
        }
        exec ("COMMIT");
    }

    /* Returns freed pages to the filesystem so the file never just grows. */
    private void compact () {
        if (db != null)
            exec ("PRAGMA incremental_vacuum");
    }

    private void open_database (string data_dir) throws Error {
        if (DirUtils.create_with_parents (data_dir, 0700) != 0)
            throw new StoreError.FAILED ("cannot create %s", data_dir);
        FileUtils.chmod (data_dir, 0700);

        db_path = Path.build_filename (data_dir, DB_NAME);

        /* Create the file ourselves so it is never world-readable, not even
         * for a moment, and refuse to follow a planted symlink. */
        int fd = Posix.open (db_path, Posix.O_RDWR | Posix.O_CREAT | Posix.O_NOFOLLOW | Posix.O_CLOEXEC,
                             (Posix.mode_t) 0600);
        if (fd < 0)
            throw new StoreError.FAILED ("cannot open %s: %s", db_path, strerror (errno));
        Posix.fchmod (fd, (Posix.mode_t) 0600);
        Posix.close (fd);

        Sqlite.Database database;
        if (Sqlite.Database.open_v2 (db_path, out database, Sqlite.OPEN_READWRITE) != Sqlite.OK)
            throw new StoreError.FAILED ("cannot open history database: %s", database.errmsg ());
        db = (owned) database;

        /* secure_delete overwrites removed rows; incremental auto-vacuum lets
         * compact() shrink the file; temp data never leaves memory. */
        exec ("PRAGMA secure_delete = ON");
        exec ("PRAGMA auto_vacuum = INCREMENTAL");
        exec ("PRAGMA temp_store = MEMORY");
        exec ("PRAGMA trusted_schema = OFF");
        exec ("PRAGMA journal_mode = DELETE");

        exec ("CREATE TABLE IF NOT EXISTS meta ("
              + " name TEXT PRIMARY KEY,"
              + " value BLOB NOT NULL)");
        exec ("CREATE TABLE IF NOT EXISTS items ("
              + " id INTEGER PRIMARY KEY,"
              + " kind INTEGER NOT NULL,"
              + " digest BLOB NOT NULL,"
              + " stamp INTEGER NOT NULL,"
              + " preview BLOB NOT NULL,"
              + " thumbnail BLOB,"
              + " payload BLOB NOT NULL,"
              + " UNIQUE (kind, digest))");
        exec ("CREATE INDEX IF NOT EXISTS items_by_stamp ON items (stamp DESC)");
        exec ("PRAGMA user_version = %d".printf (SCHEMA_VERSION));

        check_key ();
    }

    /*
     * A sealed canary proves the database belongs to the current key.  If
     * the key changed (keyring reset) the old rows can never be decrypted,
     * so they are wiped instead of lingering.
     */
    private void check_key () {
        uint8[] no_digest = {};
        Sqlite.Statement stmt;
        prepare ("SELECT value FROM meta WHERE name = 'canary'", out stmt);

        Bytes? sealed = stmt.step () == Sqlite.ROW ? column_bytes (stmt, 0) : null;
        /* Finish the read before writing; VACUUM refuses to run otherwise. */
        stmt.reset ();

        if (sealed != null) {
            try {
                if (vault.open_string (sealed, "canary", no_digest) == CANARY)
                    return;
            } catch (VaultError e) {
            }
            warning ("Clipboard history was encrypted with a different key; discarding it");
            exec ("DELETE FROM items");
            exec ("VACUUM");
        }

        prepare ("INSERT OR REPLACE INTO meta (name, value) VALUES ('canary', ?1)", out stmt);
        var sealed_canary = vault.seal_string (CANARY, "canary", no_digest);
        bind_bytes (stmt, 1, sealed_canary);
        stmt.step ();
    }

    private void load_entries () {
        Sqlite.Statement stmt;
        prepare ("SELECT id, kind, digest, stamp, preview FROM items ORDER BY stamp DESC", out stmt);

        int64[] broken = {};
        while (stmt.step () == Sqlite.ROW) {
            int64 id = stmt.column_int64 (0);
            int kind = stmt.column_int (1);
            uint8[] digest = column_bytes (stmt, 2).get_data ();

            if (!Kind.is_valid (kind)) {
                broken += id;
                continue;
            }

            try {
                var preview = vault.open_string (column_bytes (stmt, 4), "preview", digest);
                var entry = new Entry ((Kind) kind, preview);
                entry.id = id;
                entry.digest = digest;
                entry.stamp = stmt.column_int64 (3);
                entries.add (entry);
                by_key[entry.map_key] = entry;
            } catch (VaultError e) {
                broken += id;
            }
        }
        stmt.reset ();

        if (broken.length > 0) {
            warning ("Dropping %d unreadable clipboard history items", broken.length);
            delete_rows (broken);
        }
        trim ();
    }

    private Bytes? load_blob (Entry entry, string column) {
        if (db == null)
            return null;

        Sqlite.Statement stmt;
        /* @column is one of our two literal column names, never user data. */
        return_val_if_fail (column == "payload" || column == "thumbnail", null);
        prepare ("SELECT %s FROM items WHERE id = ?1".printf (column), out stmt);
        stmt.bind_int64 (1, entry.id);
        if (stmt.step () != Sqlite.ROW || stmt.column_type (0) == Sqlite.NULL)
            return null;
        return column_bytes (stmt, 0);
    }

    private void prepare (string sql, out Sqlite.Statement stmt) {
        if (db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK)
            critical ("SQL error in \"%s\": %s", sql, db.errmsg ());
    }

    private void exec (string sql) {
        string errmsg;
        if (db.exec (sql, null, out errmsg) != Sqlite.OK)
            warning ("SQL error in \"%s\": %s", sql, errmsg);
    }

    /* Binds as SQLITE_STATIC: @data must stay alive until the statement
     * has been stepped, so callers hold it in a local. */
    private static void bind_bytes (Sqlite.Statement stmt, int index, Bytes? data) {
        if (data == null) {
            stmt.bind_null (index);
            return;
        }
        unowned uint8[] raw = data.get_data ();
        stmt.bind_blob (index, raw, (int) data.length, null);
    }

    private static Bytes column_bytes (Sqlite.Statement stmt, int column) {
        int size = stmt.column_bytes (column);
        uint8* blob = stmt.column_blob (column);
        var copy = new uint8[size];
        if (size > 0)
            Memory.copy (copy, blob, size);
        return new Bytes.take ((owned) copy);
    }
}

}
