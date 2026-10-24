/*
 * backend.vala
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
 * Watches the system clipboard and can take it over.
 *
 * Content travels as raw bytes: UTF-8 for text, PNG for images and a
 * newline separated URI list for files.
 */
public abstract class ClipboardBackend : Object {
    /* Password managers (KeePassXC, KWallet, ...) mark secrets with this. */
    protected const string PASSWORD_HINT = "x-kde-passwordManagerHint";

    protected const string[] TEXT_TYPES = {
        "text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "STRING", "TEXT"
    };

    /* New content was copied by another application. */
    public signal void received (Selection selection, Kind kind, Bytes data);
    /* The selection was emptied, typically because its owner exited. */
    public signal void lost (Selection selection);

    public bool watch_primary { get; set; default = false; }
    public bool save_images { get; set; default = true; }
    public bool save_files { get; set; default = true; }

    public abstract void start ();
    public abstract void stop ();
    /* Makes this process the owner of @selection, serving @data. */
    public abstract void offer (Selection selection, Kind kind, Bytes data);
    public abstract bool can_paste { get; }
    /* Sends Ctrl+V to the focused window, where supported. */
    public virtual void paste () {
    }

    public static ClipboardBackend? create (Gdk.Display display) {
#if HAVE_WAYLAND
        if (GdkWayland.is_wayland_display (display))
            return new WaylandBackend (display);
#endif
#if HAVE_X11
        if (display is Gdk.X11.Display)
            return new X11Backend (display);
#endif
        warning ("Clipboard history is not supported on this display");
        return null;
    }

    protected static size_t max_bytes (Kind kind) {
        return kind == Kind.IMAGE ? MAX_IMAGE_BYTES : MAX_TEXT_BYTES;
    }

    /* Reads @stream to the end, failing once more than @limit bytes arrive. */
    protected static async Bytes read_limited (InputStream stream, size_t limit,
                                               Cancellable? cancellable) throws Error {
        var buffer = new ByteArray ();
        while (true) {
            var chunk = yield stream.read_bytes_async (64 * 1024, Priority.DEFAULT, cancellable);
            if (chunk.length == 0)
                break;
            if (buffer.len + chunk.length > limit)
                throw new IOError.MESSAGE_TOO_LARGE ("clipboard content is larger than %zu bytes", limit);
            buffer.append (chunk.get_data ());
        }
        return ByteArray.free_to_bytes ((owned) buffer);
    }

    /* Converts stored content to what a requested MIME type expects. */
    protected static Bytes convert_for (Kind kind, Bytes data, string mime_type) {
        if (kind != Kind.FILES)
            return data;

        var uris = split_uri_list (bytes_to_string (data));
        switch (mime_type) {
        case "text/uri-list":
            return new Bytes (string.joinv ("\r\n", uris).data);
        case "x-special/gnome-copied-files":
            return new Bytes (("copy\n" + string.joinv ("\n", uris)).data);
        default:
            string[] paths = {};
            foreach (var uri in uris)
                paths += File.new_for_uri (uri).get_path () ?? uri;
            return new Bytes (string.joinv ("\n", paths).data);
        }
    }

    protected static string[] mime_types_for (Kind kind) {
        switch (kind) {
        case Kind.IMAGE:
            return { "image/png" };
        case Kind.FILES:
            return { "text/uri-list", "x-special/gnome-copied-files",
                     "text/plain;charset=utf-8", "text/plain", "UTF8_STRING" };
        default:
            return TEXT_TYPES;
        }
    }
}

}
