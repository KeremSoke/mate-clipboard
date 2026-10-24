/*
 * service.vala
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

/*
 * The D-Bus face of the applet, for binding the history to a key.
 *
 * It deliberately has a single method that takes no arguments and returns
 * nothing: other programs on the session bus can ask for the dialog to be
 * shown, but cannot pass data in or read any history out.
 */
[DBus (name = "org.mate.Clipman")]
public class ShortcutService : Object {
    private unowned Service service;

    internal ShortcutService (Service service) {
        this.service = service;
    }

    public void show_history () throws DBusError, IOError {
        service.show_history_from_shortcut ();
    }
}

/* Something on a panel the history dialog can open next to. */
public interface PanelAnchor : Object {
    public abstract Gtk.Widget widget { get; }
    /* Which way popups open, i.e. away from the panel edge. */
    public abstract MatePanel.AppletOrient orient { get; }
}

/*
 * Everything one clipboard manager needs, shared by all applet instances
 * in the panel process: settings, the encrypted store, the clipboard
 * backend, the history dialog and the D-Bus shortcut object.
 */
public class Service : Object {
    public const string BUS_NAME = "org.mate.Clipman";
    public const string OBJECT_PATH = "/org/mate/Clipman";
    public const string SHORTCUT_COMMAND = "gdbus call --session --dest org.mate.Clipman"
                                           + " --object-path /org/mate/Clipman"
                                           + " --method org.mate.Clipman.ShowHistory";

    private const uint PASTE_DELAY_MS = 150;

    private static Service? instance;

    public const string SCHEMA_ID = "org.mate.clipman";
    /* Keys this version reads; an older installed schema may lack some. */
    private const string[] REQUIRED_KEYS = {
        "history-size", "use-primary-selection", "sync-selections", "save-images", "save-files",
        "keep-content", "show-preview", "confirm-clear", "paste-on-select", "exclude-pattern",
        "popup-position", "persist-history"
    };

    /* Null when the schema is missing; the service then stays inert. */
    public GLib.Settings? settings { get; private set; }
    /* Why the service could not start, for the applet's tooltip. */
    public string? error_message { get; private set; }
    /* False until the store is open, or when history is memory-only. */
    public bool history_saved { get; private set; }
    /* The store is open (the keyring may still be prompting before that). */
    public bool ready { get; private set; }
    /* Saving was wanted but the keyring or database was unavailable. */
    public bool saving_failed { get; private set; }
    public bool is_wayland { get; private set; }

    private Store? store;
    private HistoryPopup? popup;
    private ClipboardBackend? backend;
    private Preferences? preferences;
    private GenericArray<PanelAnchor> anchors = new GenericArray<PanelAnchor> ();
    private Regex? exclude;
    private Cancellable cancellable = new Cancellable ();
    private uint bus_owner_id;
    private uint registration_id;
    private DBusConnection? connection;
    private ShortcutService? shortcut_service;
    private ulong[] settings_handlers = {};

    private class ImageInfo {
        public int width;
        public int height;
        public Bytes? thumbnail;
    }

    /* Each applet registers itself; the service lives while any does. */
    public static Service register (PanelAnchor anchor) {
        if (instance == null) {
            instance = new Service ();
            instance.start ();
        }
        instance.anchors.add (anchor);
        return instance;
    }

    public void unregister (PanelAnchor anchor) {
        anchors.remove (anchor);
        if (anchors.length == 0 && instance == this) {
            shutdown ();
            instance = null;
        }
    }

    private void start () {
        /* We run inside mate-panel, where g_settings_new() on a missing
         * schema would abort the whole panel; never let that happen. */
        settings = load_settings ();
        if (settings == null) {
            error_message = _("Clipboard Manager is not installed correctly: its settings schema is missing.");
            critical ("GSettings schema %s with the expected keys was not found", SCHEMA_ID);
            return;
        }
#if HAVE_WAYLAND
        is_wayland = GdkWayland.is_wayland_display (Gdk.Display.get_default ());
#endif

        /* Writing to a reader that went away must fail with EPIPE rather
         * than kill the whole panel. */
        Posix.signal (Posix.Signal.PIPE, Posix.SIG_IGN);

        try {
            Vault.init_crypto ();
        } catch (VaultError e) {
            critical ("%s", e.message);
            return;
        }

        update_exclude_pattern ();
        settings_handlers += settings.changed["exclude-pattern"].connect (update_exclude_pattern);

        open_store.begin ();
    }

    /*
     * GLib reads the compiled schemas once per process, so a panel that was
     * running before installation does not see ours (or sees an older
     * version).  Fall back to reading the install directory directly.
     */
    private static GLib.Settings? load_settings () {
        var schema = usable_schema (SettingsSchemaSource.get_default ());
        if (schema == null) {
            try {
                var source = new SettingsSchemaSource.from_directory (Config.SCHEMA_DIR, null, false);
                schema = usable_schema (source);
            } catch (Error e) {
                debug ("Could not read %s: %s", Config.SCHEMA_DIR, e.message);
            }
        }
        return schema != null ? new GLib.Settings.full (schema, null, null) : null;
    }

    private static SettingsSchema? usable_schema (SettingsSchemaSource? source) {
        var schema = source != null ? source.lookup (SCHEMA_ID, true) : null;
        if (schema == null)
            return null;
        foreach (var key in REQUIRED_KEYS) {
            if (!schema.has_key (key))
                return null;
        }
        return schema;
    }

    private void shutdown () {
        cancellable.cancel ();
        foreach (var handler in settings_handlers)
            SignalHandler.disconnect (settings, handler);
        settings_handlers = {};
        if (backend != null)
            backend.stop ();
        if (registration_id != 0)
            connection.unregister_object (registration_id);
        if (bus_owner_id != 0)
            Bus.unown_name (bus_owner_id);
        if (popup != null)
            popup.destroy ();
        if (preferences != null)
            preferences.destroy ();
        backend = null;
        popup = null;
        preferences = null;
        store = null;
    }

    private async void open_store () {
        int limit = settings.get_int ("history-size");
        Vault? vault = null;

        if (settings.get_boolean ("persist-history")) {
            try {
                vault = yield Vault.from_keyring (cancellable);
            } catch (Error e) {
                if (cancellable.is_cancelled ())
                    return;
                warning ("Login keyring unavailable, clipboard history will not be saved: %s", e.message);
                saving_failed = true;
            }
        }

        try {
            if (vault == null)
                vault = Vault.ephemeral ();
            try {
                store = new Store (vault, Store.default_data_dir (), limit);
            } catch (Error e) {
                warning ("Could not open the history database, history will not be saved: %s", e.message);
                saving_failed = true;
                store = new Store (Vault.ephemeral (), null, limit);
            }
        } catch (Error e) {
            critical ("Could not set up clipboard history: %s", e.message);
            return;
        }
        if (cancellable.is_cancelled ())
            return;

        history_saved = store.persistent;
        ready = true;
        settings_handlers += settings.changed["history-size"].connect (() => {
            if (store != null)
                store.limit = settings.get_int ("history-size");
        });
        settings_handlers += settings.changed["persist-history"].connect (() => {
            /* Turning saving off wipes the file at once; turning it back on
             * takes effect the next time the panel starts. */
            if (store != null && !settings.get_boolean ("persist-history")) {
                store.forget_disk ();
                history_saved = false;
            }
        });

        popup = new HistoryPopup (store, settings);
        popup.entry_activated.connect (on_entry_activated);
        popup.delete_requested.connect ((entry) => store.remove (entry));
        popup.clear_requested.connect (request_clear);

        backend = ClipboardBackend.create (Gdk.Display.get_default ());
        if (backend != null) {
            settings.bind ("use-primary-selection", backend, "watch-primary", SettingsBindFlags.GET);
            settings.bind ("save-images", backend, "save-images", SettingsBindFlags.GET);
            settings.bind ("save-files", backend, "save-files", SettingsBindFlags.GET);
            backend.received.connect (on_received);
            backend.lost.connect (on_lost);
            backend.start ();
        }

        export_shortcut_service ();
    }

    private void export_shortcut_service () {
        bus_owner_id = Bus.own_name (BusType.SESSION, BUS_NAME, BusNameOwnerFlags.NONE,
            (conn) => {
                try {
                    shortcut_service = new ShortcutService (this);
                    registration_id = conn.register_object (OBJECT_PATH, shortcut_service);
                    connection = conn;
                } catch (IOError e) {
                    warning ("Could not export %s: %s", OBJECT_PATH, e.message);
                }
            },
            null,
            () => debug ("%s is owned by another process", BUS_NAME));
    }

    public void show_history_from_shortcut () {
        if (popup == null)
            return;
        if (popup.visible) {
            popup.hide ();
            return;
        }

        bool at_pointer = settings.get_string ("popup-position") == "pointer";
        if (!is_wayland && (at_pointer || anchors.length == 0))
            popup.popup_at_pointer ();
        else if (anchors.length > 0)
            popup.popup_at_widget (anchors[0].widget, anchors[0].orient);
    }

    public void toggle_from_applet (PanelAnchor anchor) {
        if (popup == null)
            return;
        if (popup.recently_visible ()) {
            popup.hide ();
            return;
        }
        popup.popup_at_widget (anchor.widget, anchor.orient);
    }

    public void show_preferences () {
        if (settings == null)
            return;
        if (preferences == null) {
            preferences = new Preferences (this);
            preferences.destroy.connect (() => preferences = null);
        }
        preferences.present ();
    }

    public void request_clear () {
        if (store == null)
            return;

        if (!settings.get_boolean ("confirm-clear")) {
            store.clear ();
            return;
        }

        var dialog = new Gtk.MessageDialog (null, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION,
                                            Gtk.ButtonsType.YES_NO, "%s", _("Clear all clipboard history?"));
        dialog.format_secondary_text ("%s", _("This action cannot be undone."));
        dialog.set_keep_above (true);
        dialog.response.connect ((response) => {
            if (response == Gtk.ResponseType.YES && store != null)
                store.clear ();
            dialog.destroy ();
        });
        dialog.show ();
    }

    private void update_exclude_pattern () {
        var pattern = settings.get_string ("exclude-pattern");
        exclude = null;
        if (pattern == "")
            return;
        try {
            exclude = new Regex (pattern, RegexCompileFlags.OPTIMIZE);
        } catch (RegexError e) {
            warning ("Ignoring invalid exclude pattern: %s", e.message);
        }
    }

    private void on_received (Selection selection, Kind kind, Bytes data) {
        if (store == null)
            return;

        switch (kind) {
        case Kind.TEXT:
            var text = bytes_to_string (data);
            if (text.strip () == "")
                return;
            if (exclude != null && exclude.match (text))
                return;
            var payload = new Bytes (text.data);
            store.add (Kind.TEXT, payload, utf8_prefix (text, PREVIEW_CHARS), null);
            sync_other_selection (selection, kind, payload);
            break;
        case Kind.FILES:
            var uris = split_uri_list (bytes_to_string (data));
            if (uris.length == 0)
                return;
            var list = string.joinv ("\n", uris);
            store.add (Kind.FILES, new Bytes (list.data), list, null);
            break;
        case Kind.IMAGE:
            add_image.begin (data);
            break;
        }
    }

    /* Keeps CLIPBOARD and PRIMARY in step when asked to; text only, since
     * pasting an image with the middle button is never what anyone wants. */
    private void sync_other_selection (Selection selection, Kind kind, Bytes payload) {
        if (kind != Kind.TEXT || backend == null || !settings.get_boolean ("sync-selections"))
            return;
        backend.offer (selection == Selection.CLIPBOARD ? Selection.PRIMARY : Selection.CLIPBOARD,
                       kind, payload);
    }

    private async void add_image (Bytes png) {
        uint32 width, height;
        if (!png_dimensions (png, out width, out height) || (uint64) width * height > MAX_IMAGE_PIXELS)
            return;

        var info = yield inspect_image (png);
        if (info != null && store != null)
            store.add (Kind.IMAGE, png, "%dx%d".printf (info.width, info.height), info.thumbnail);
    }

    /* Decodes the image at thumbnail size, off the main thread. */
    private static async ImageInfo? inspect_image (Bytes png) {
        ImageInfo? info = null;
        SourceFunc callback = inspect_image.callback;

        new Thread<void*> ("clipman-thumbnail", () => {
            var result = new ImageInfo ();
            try {
                var loader = new Gdk.PixbufLoader.with_type ("png");
                loader.size_prepared.connect ((width, height) => {
                    result.width = width;
                    result.height = height;
                    double scale = double.min (1.0, (double) THUMB_STORED_SIZE / int.max (width, height));
                    loader.set_size (int.max (1, (int) (width * scale)), int.max (1, (int) (height * scale)));
                });
                loader.write_bytes (png);
                loader.close ();

                uint8[] buffer;
                loader.get_pixbuf ().save_to_buffer (out buffer, "png");
                result.thumbnail = new Bytes.take ((owned) buffer);
                info = result;
            } catch (Error e) {
                debug ("Skipped unreadable image: %s", e.message);
            }
            Idle.add ((owned) callback);
            return null;
        });
        yield;
        return info;
    }

    private void on_entry_activated (Entry entry) {
        Bytes payload;
        try {
            payload = store.load_payload (entry);
        } catch (Error e) {
            warning ("Could not read clipboard item: %s", e.message);
            return;
        }

        if (backend != null) {
            backend.offer (Selection.CLIPBOARD, entry.kind, payload);
            sync_other_selection (Selection.CLIPBOARD, entry.kind, payload);
        }
        store.promote (entry);

        if (backend != null && backend.can_paste && settings.get_boolean ("paste-on-select")) {
            /* Give the window manager time to hand focus back first. */
            Timeout.add (PASTE_DELAY_MS, () => {
                if (backend != null)
                    backend.paste ();
                return Source.REMOVE;
            });
        }
    }

    /* The owner of the clipboard went away: put the newest item back. */
    private void on_lost (Selection selection) {
        if (selection != Selection.CLIPBOARD || store == null || backend == null
            || !settings.get_boolean ("keep-content"))
            return;

        var newest = store.get_entry (0);
        if (newest == null)
            return;
        try {
            backend.offer (selection, newest.kind, store.load_payload (newest));
        } catch (Error e) {
            warning ("Could not restore clipboard content: %s", e.message);
        }
    }
}

}
