/*
 * x11-backend.vala
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

#if HAVE_X11
namespace Clipman {

/*
 * Clipboard access on X11 through GtkClipboard.  Everything is requested
 * asynchronously: this code runs inside mate-panel, which must never block
 * waiting for another application to answer a selection request.
 */
public class X11Backend : ClipboardBackend {
    private const uint PRIMARY_SETTLE_MS = 300;

    private enum Info {
        TEXT,
        PNG,
        URI_LIST,
        GNOME_FILES
    }

    private unowned Gdk.Display display;
    private Gtk.Clipboard?[] clipboards = new Gtk.Clipboard?[2];
    private ulong[] handlers = new ulong[2];
    private uint[] generation = new uint[2];
    private uint primary_timeout;
    private Kind[] offered_kind = new Kind[2];
    private Bytes?[] offered_data = new Bytes?[2];

    public X11Backend (Gdk.Display display) {
        this.display = display;
    }

    public override bool can_paste {
        get { return true; }
    }

    public override void start () {
        if (clipboards[0] != null)
            return;

        clipboards[Selection.CLIPBOARD] = Gtk.Clipboard.get_for_display (display, Gdk.SELECTION_CLIPBOARD);
        clipboards[Selection.PRIMARY] = Gtk.Clipboard.get_for_display (display, Gdk.SELECTION_PRIMARY);

        handlers[Selection.CLIPBOARD] = clipboards[Selection.CLIPBOARD].owner_change.connect ((event) => {
            changed (Selection.CLIPBOARD, event.reason != Gdk.OwnerChange.NEW_OWNER);
        });
        handlers[Selection.PRIMARY] = clipboards[Selection.PRIMARY].owner_change.connect ((event) => {
            if (!watch_primary)
                return;
            bool owner_gone = event.reason != Gdk.OwnerChange.NEW_OWNER;
            generation[Selection.PRIMARY]++;
            if (primary_timeout != 0)
                Source.remove (primary_timeout);
            primary_timeout = Timeout.add (PRIMARY_SETTLE_MS, () => {
                primary_timeout = 0;
                changed (Selection.PRIMARY, owner_gone);
                return Source.REMOVE;
            });
        });
    }

    public override void stop () {
        if (primary_timeout != 0) {
            Source.remove (primary_timeout);
            primary_timeout = 0;
        }
        for (int i = 0; i < 2; i++) {
            if (clipboards[i] != null) {
                SignalHandler.disconnect (clipboards[i], handlers[i]);
                if (clipboards[i].get_owner () == this)
                    clipboards[i].clear ();
            }
            clipboards[i] = null;
            offered_data[i] = null;
            generation[i]++;
        }
    }

    public override void offer (Selection selection, Kind kind, Bytes data) {
        var clipboard = clipboards[selection];
        if (clipboard == null)
            return;

        var targets = new Gtk.TargetList (null);
        switch (kind) {
        case Kind.IMAGE:
            targets.add (Gdk.Atom.intern_static_string ("image/png"), 0, Info.PNG);
            break;
        case Kind.FILES:
            targets.add (Gdk.Atom.intern_static_string ("text/uri-list"), 0, Info.URI_LIST);
            targets.add (Gdk.Atom.intern_static_string ("x-special/gnome-copied-files"), 0, Info.GNOME_FILES);
            targets.add_text_targets (Info.TEXT);
            break;
        default:
            targets.add_text_targets (Info.TEXT);
            break;
        }

        offered_kind[selection] = kind;
        offered_data[selection] = data;
        clipboard.set_with_owner (Gtk.target_table_new_from_list (targets), get_contents, clear_contents, this);
        clipboard.set_can_store (null);
    }

    /* Types Ctrl+V into whichever window has the focus. TODO!!!!!!*/
    public override void paste () {
        unowned X.Display xdisplay = ((Gdk.X11.Display) display).get_xdisplay ();
        uint control = xdisplay.keysym_to_keycode (Gdk.Key.Control_L);
        uint v = xdisplay.keysym_to_keycode (Gdk.Key.v);
        if (control == 0 || v == 0)
            return;

        XTest.fake_key_event (xdisplay, control, true, 0);
        XTest.fake_key_event (xdisplay, v, true, 0);
        XTest.fake_key_event (xdisplay, v, false, 0);
        XTest.fake_key_event (xdisplay, control, false, 0);
        xdisplay.flush ();
    }

    private static void get_contents (Gtk.Clipboard clipboard, Gtk.SelectionData selection_data,
                                      uint info, void* owner) {
        var self = (X11Backend) owner;
        var selection = clipboard.get_selection () == Gdk.SELECTION_PRIMARY
                        ? Selection.PRIMARY : Selection.CLIPBOARD;
        var data = self.offered_data[selection];
        if (data == null)
            return;

        var kind = self.offered_kind[selection];
        var target = selection_data.get_target ();
        switch (info) {
        case Info.TEXT:
            var text = bytes_to_string (convert_for (kind, data, "text/plain"));
            selection_data.set_text (text, -1);
            break;
        case Info.PNG:
            selection_data.set (target, 8, data.get_data ());
            break;
        default:
            var converted = convert_for (kind, data, target.name ());
            selection_data.set (target, 8, converted.get_data ());
            break;
        }
    }

    private static void clear_contents (Gtk.Clipboard clipboard, void* owner) {
    }

    /* @owner_gone: the owning window was destroyed or its client exited,
     * as opposed to another application taking the selection. */
    private void changed (Selection selection, bool owner_gone) {
        var clipboard = clipboards[selection];
        if (clipboard == null || clipboard.get_owner () == this)
            return;

        generation[selection]++;
        if (owner_gone) {
            lost (selection);
            return;
        }

        uint current = generation[selection];
        clipboard.request_targets ((clipboard, atoms) => {
            if (current == generation[selection])
                handle_targets (selection, atoms);
        });
    }

    private void handle_targets (Selection selection, Gdk.Atom[]? atoms) {
        var clipboard = clipboards[selection];
        /* No targets can also mean a slow owner timed out; that is not a
         * reason to replace the clipboard, so only owner_gone counts. */
        if (atoms == null || atoms.length == 0)
            return;

        bool has_png = false;
        bool has_uris = false;
        foreach (var atom in atoms) {
            var name = atom.name ();
            if (name == PASSWORD_HINT)
                return;
            if (name == "image/png")
                has_png = true;
            else if (name == "text/uri-list")
                has_uris = true;
        }

        uint current = generation[selection];

        /* Same priority as before: files, then images, then text. */
        if (has_uris) {
            if (!save_files)
                return;
            clipboard.request_uris ((clipboard, uris) => {
                if (current == generation[selection] && uris != null && uris.length > 0)
                    deliver (selection, Kind.FILES, new Bytes (string.joinv ("\n", uris).data));
            });
        } else if (Gtk.targets_include_image (atoms, false)) {
            if (!save_images)
                return;
            if (has_png) {
                /* Take the PNG as-is: no decoding or re-encoding needed. */
                clipboard.request_contents (Gdk.Atom.intern_static_string ("image/png"), (clipboard, data) => {
                    /* get_data() carries no length in the binding; this does. */
                    if (current == generation[selection] && data.get_length () > 0)
                        deliver (selection, Kind.IMAGE, new Bytes (data.get_data_with_length ()));
                });
            } else {
                clipboard.request_image ((clipboard, pixbuf) => {
                    if (current == generation[selection] && pixbuf != null)
                        encode_png.begin (selection, pixbuf, current);
                });
            }
        } else if (Gtk.targets_include_text (atoms)) {
            clipboard.request_text ((clipboard, text) => {
                if (current == generation[selection] && text != null && text != "")
                    deliver (selection, Kind.TEXT, new Bytes (text.data));
            });
        }
    }

    private void deliver (Selection selection, Kind kind, Bytes data) {
        if (data.length <= max_bytes (kind))
            received (selection, kind, data);
    }

    /* Applications that only offer other image formats: re-encode off the
     * main thread so a large screenshot cannot stall the panel. */
    private async void encode_png (Selection selection, Gdk.Pixbuf pixbuf, uint current) {
        Bytes? png = null;
        SourceFunc callback = encode_png.callback;
        new Thread<void*> ("clipman-png", () => {
            try {
                uint8[] buffer;
                pixbuf.save_to_buffer (out buffer, "png", "compression", "1");
                png = new Bytes.take ((owned) buffer);
            } catch (Error e) {
                warning ("Could not encode copied image: %s", e.message);
            }
            Idle.add ((owned) callback);
            return null;
        });
        yield;

        if (png != null && current == generation[selection])
            deliver (selection, Kind.IMAGE, png);
    }
}

}
#endif
