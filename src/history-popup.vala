/*
 * history-popup.vala
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
 * The clipboard history dialog.
 *
 * Rows are built once, the first time the dialog opens, and then kept in
 * step with the store; searching only filters them.  Image rows decode their
 * small stored thumbnail when created; full images are never loaded here.
 *
 * On X11 it is an undecorated popup window placed at the pointer or next
 * to the applet.  On Wayland it is a layer-shell surface anchored next to
 * the applet, since clients cannot learn the global pointer position as far 
 * as i know.
 */
public class HistoryPopup : Gtk.Window {
    private const int WIDTH = 400;
    private const int HEIGHT = 450;
    private const int64 TOGGLE_GRACE_US = 300 * 1000;

    public signal void entry_activated (Entry entry);
    public signal void delete_requested (Entry entry);
    public signal void clear_requested ();

    private Store store;
    private GLib.Settings settings;
    private bool layer_shell;

    private Gtk.Box vbox;
    private Gtk.Box header;
    private Gtk.Separator separator;
    private Gtk.SearchEntry search_entry;
    private Gtk.ListBox list_box;
    private Gtk.ScrolledWindow scrolled;
    private Gtk.Stack stack;

    private HashTable<Entry, Gtk.ListBoxRow> rows = new HashTable<Entry, Gtk.ListBoxRow> (direct_hash, direct_equal);
    private bool rows_built;
    private string needle = "";
    private int64 hidden_at;

    public HistoryPopup (Store store, GLib.Settings settings) {
        Object (type: Gtk.WindowType.TOPLEVEL);
        this.store = store;
        this.settings = settings;

        title = _("Clipboard History");
        set_default_size (WIDTH, HEIGHT);
        skip_taskbar_hint = true;
        skip_pager_hint = true;
        decorated = false;
        border_width = 1;

#if HAVE_WAYLAND
        if (GdkWayland.is_wayland_display (get_display ()) && GtkLayerShell.is_supported ()) {
            layer_shell = true;
            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_namespace (this, "mate-clipman");
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.TOP);
            GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.ON_DEMAND);
            /* Ignore other exclusive zones: the margins we set are absolute. */
            GtkLayerShell.set_exclusive_zone (this, -1);
            set_size_request (WIDTH, HEIGHT);
        }
#endif
        if (!layer_shell)
            type_hint = Gdk.WindowTypeHint.POPUP_MENU;

        /* Add frame for border */
        var frame = new Gtk.Frame (null);
        frame.shadow_type = Gtk.ShadowType.OUT;
        add (frame);

        vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        frame.add (vbox);

        /* Header with search and clear */
        header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        header.border_width = 6;
        vbox.pack_start (header, false, false, 0);

        search_entry = new Gtk.SearchEntry ();
        search_entry.placeholder_text = _("Search history...");
        search_entry.hexpand = true;
        header.pack_start (search_entry, true, true, 0);

        var clear_btn = new Gtk.Button.from_icon_name ("edit-clear-all-symbolic", Gtk.IconSize.BUTTON);
        clear_btn.tooltip_text = _("Clear all history");
        header.pack_end (clear_btn, false, false, 0);

        separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        vbox.pack_start (separator, false, false, 0);

        /* Stack for list/empty views */
        stack = new Gtk.Stack ();
        vbox.pack_start (stack, true, true, 0);

        scrolled = new Gtk.ScrolledWindow (null, null);
        scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        stack.add_named (scrolled, "list");

        list_box = new Gtk.ListBox ();
        list_box.selection_mode = Gtk.SelectionMode.SINGLE;
        list_box.activate_on_single_click = true;
        list_box.set_filter_func (filter_row);
        scrolled.add (list_box);

        /* Empty state */
        var empty_label = new Gtk.Label (_("No clipboard history"));
        empty_label.sensitive = false;
        stack.add_named (empty_label, "empty");

        list_box.row_activated.connect (on_row_activated);
        search_entry.search_changed.connect (on_search_changed);
        search_entry.activate.connect (activate_first_visible);
        search_entry.stop_search.connect (() => hide ());
        key_press_event.connect (on_key_press);
        focus_out_event.connect (() => {
            hide ();
            return false;
        });
        hide.connect (() => hidden_at = get_monotonic_time ());
        clear_btn.clicked.connect (() => clear_requested ());

        store.added.connect (on_entry_added);
        store.promoted.connect (on_entry_promoted);
        store.removed.connect (on_entry_removed);
        store.cleared.connect (on_store_cleared);
        settings.changed["show-preview"].connect (rebuild_rows);

        frame.show_all ();
    }

    /* True if the dialog is open, or was just closed by the very click that
     * is now asking to toggle it (focus-out fires before the click). */
    public bool recently_visible () {
        return visible || get_monotonic_time () - hidden_at < TOGGLE_GRACE_US;
    }

    /* Opens the dialog at the mouse pointer (X11 only). */
    public void popup_at_pointer () {
        if (layer_shell)
            return;

        prepare (true);

        int x = 0, y = 0;
        get_pointer_position (out x, out y);

        /* Adjust position to keep on screen */
        var monitor = get_display ().get_monitor_at_point (x, y);
        var area = monitor.get_workarea ();
        x = x.clamp (area.x, int.max (area.x, area.x + area.width - WIDTH));
        y = y.clamp (area.y, int.max (area.y, area.y + area.height - HEIGHT));

        show_at (x, y);
    }

    /* Opens the dialog next to @anchor, opening away from the panel edge. */
    public void popup_at_widget (Gtk.Widget anchor, MatePanel.AppletOrient orient) {
        /* A panel at the bottom opens the dialog upwards: keep the search
         * box next to the panel, at the bottom of the dialog. */
        prepare (orient != MatePanel.AppletOrient.UP);

#if HAVE_WAYLAND
        if (layer_shell) {
            place_layer_surface (anchor, orient);
            show_all ();
            present ();
            search_entry.grab_focus ();
            return;
        }
#endif

        int ox = 0, oy = 0;
        anchor.get_window ().get_origin (out ox, out oy);
        Gtk.Allocation alloc;
        anchor.get_allocation (out alloc);
        if (!anchor.get_has_window ()) {
            ox += alloc.x;
            oy += alloc.y;
        }

        int x = ox, y = oy;
        switch (orient) {
        case MatePanel.AppletOrient.DOWN:
            y = oy + alloc.height;
            break;
        case MatePanel.AppletOrient.UP:
            y = oy - HEIGHT;
            break;
        case MatePanel.AppletOrient.RIGHT:
            x = ox + alloc.width;
            break;
        case MatePanel.AppletOrient.LEFT:
            x = ox - WIDTH;
            break;
        }

        var monitor = get_display ().get_monitor_at_window (anchor.get_window ());
        var geometry = monitor.get_geometry ();
        x = x.clamp (geometry.x, int.max (geometry.x, geometry.x + geometry.width - WIDTH));
        y = y.clamp (geometry.y, int.max (geometry.y, geometry.y + geometry.height - HEIGHT));

        show_at (x, y);
    }

    private void prepare (bool search_on_top) {
        ensure_rows ();

        /* Search box at the top, or at the bottom for bottom panels */
        vbox.reorder_child (header, search_on_top ? 0 : 2);
        vbox.reorder_child (separator, 1);
        vbox.reorder_child (stack, search_on_top ? 2 : 0);

        search_entry.text = "";
        needle = "";
        list_box.invalidate_filter ();
        update_empty_state ();
        list_box.unselect_all ();
        scrolled.vadjustment.value = 0;
    }

    private void show_at (int x, int y) {
        move (x, y);
        show ();

        uint32 timestamp = Gtk.get_current_event_time ();
#if HAVE_X11
        /* Invoked from a keyboard shortcut there is no event to take the
         * time from without one the window manager may refuse focus. */
        if (timestamp == Gdk.CURRENT_TIME && get_window () is Gdk.X11.Window)
            timestamp = Gdk.X11.get_server_time ((Gdk.X11.Window) get_window ());
#endif
        present_with_time (timestamp);

        /* Some window managers remember the last position of windows that
         * were already mapped, move again so the popup always follows. */
        move (x, y);

        search_entry.grab_focus ();
    }

#if HAVE_WAYLAND
    private void place_layer_surface (Gtk.Widget anchor, MatePanel.AppletOrient orient) {
        var toplevel = anchor.get_toplevel () as Gtk.Window;
        var monitor = get_display ().get_monitor_at_window (toplevel.get_window ());
        var geometry = monitor.get_geometry ();
        GtkLayerShell.set_monitor (this, monitor);

        /* Find the applet's position on its monitor from the panel's own
         * layer-shell placement plus the applet's offset inside the panel. */
        int ax = 0, ay = 0;
        anchor.translate_coordinates (toplevel, 0, 0, out ax, out ay);
        int panel_w = toplevel.get_allocated_width ();
        int panel_h = toplevel.get_allocated_height ();
        int x = panel_offset (toplevel, GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT,
                              geometry.width, panel_w) + ax;
        int y = panel_offset (toplevel, GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                              geometry.height, panel_h) + ay;
        int w = anchor.get_allocated_width ();
        int h = anchor.get_allocated_height ();

        GtkLayerShell.Edge[] edges = { GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT,
                                       GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM };
        foreach (var edge in edges) {
            GtkLayerShell.set_anchor (this, edge, false);
            GtkLayerShell.set_margin (this, edge, 0);
        }

        int along_x = x.clamp (0, int.max (0, geometry.width - WIDTH));
        int along_y = y.clamp (0, int.max (0, geometry.height - HEIGHT));

        switch (orient) {
        case MatePanel.AppletOrient.DOWN: /* panel at the top */
            anchor_edge (GtkLayerShell.Edge.TOP, y + h);
            anchor_edge (GtkLayerShell.Edge.LEFT, along_x);
            break;
        case MatePanel.AppletOrient.UP: /* panel at the bottom */
            anchor_edge (GtkLayerShell.Edge.BOTTOM, geometry.height - y);
            anchor_edge (GtkLayerShell.Edge.LEFT, along_x);
            break;
        case MatePanel.AppletOrient.RIGHT: /* panel on the left */
            anchor_edge (GtkLayerShell.Edge.LEFT, x + w);
            anchor_edge (GtkLayerShell.Edge.TOP, along_y);
            break;
        case MatePanel.AppletOrient.LEFT: /* panel on the right */
            anchor_edge (GtkLayerShell.Edge.RIGHT, geometry.width - x);
            anchor_edge (GtkLayerShell.Edge.TOP, along_y);
            break;
        }
    }

    private void anchor_edge (GtkLayerShell.Edge edge, int margin) {
        GtkLayerShell.set_anchor (this, edge, true);
        GtkLayerShell.set_margin (this, edge, int.max (0, margin));
    }

    /* Where the panel starts along one axis of its monitor. */
    private static int panel_offset (Gtk.Window panel, GtkLayerShell.Edge start, GtkLayerShell.Edge end,
                                     int monitor_size, int panel_size) {
        if (!GtkLayerShell.is_layer_window (panel))
            return 0;
        bool at_start = GtkLayerShell.get_anchor (panel, start);
        bool at_end = GtkLayerShell.get_anchor (panel, end);
        if (at_start)
            return GtkLayerShell.get_margin (panel, start);
        if (at_end)
            return monitor_size - panel_size - GtkLayerShell.get_margin (panel, end);
        return (monitor_size - panel_size) / 2;
    }
#endif

    private void get_pointer_position (out int x, out int y) {
        x = 0;
        y = 0;
#if HAVE_X11
        /* Ask the X server directly, it knows the global pointer position
         * even when no GDK device has reported one yet. */
        var x11_display = get_display () as Gdk.X11.Display;
        if (x11_display != null) {
            unowned X.Display xdisplay = x11_display.get_xdisplay ();
            X.Window root, child;
            int win_x, win_y;
            uint mask;
            if (xdisplay.query_pointer (xdisplay.default_root_window (), out root, out child,
                                        out x, out y, out win_x, out win_y, out mask))
                return;
        }
#endif
        var seat = get_display ().get_default_seat ();
        if (seat != null && seat.get_pointer () != null)
            seat.get_pointer ().get_position (null, out x, out y);
    }

    private void ensure_rows () {
        if (rows_built)
            return;
        rows_built = true;
        /* The store is newest first */
        store.foreach ((entry) => list_box.insert (create_row (entry), -1));
    }

    private void rebuild_rows () {
        if (!rows_built)
            return;
        foreach (var row in rows.get_values ())
            row.destroy ();
        rows.remove_all ();
        rows_built = false;
        ensure_rows ();
    }

    private Gtk.ListBoxRow create_row (Entry entry) {
        var row = new Gtk.ListBoxRow ();
        row.set_data<Entry> ("entry", entry);

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        box.border_width = 6;
        row.add (box);

        /* Icon based on type */
        string icon_name;
        switch (entry.kind) {
        case Kind.IMAGE:
            icon_name = "image-x-generic";
            break;
        case Kind.FILES:
            icon_name = "folder";
            break;
        default:
            icon_name = "text-x-generic";
            break;
        }

        var image = new Gtk.Image.from_icon_name (icon_name, Gtk.IconSize.MENU);
        box.pack_start (image, false, false, 0);

        /* Show thumbnail for images if enabled */
        if (entry.kind == Kind.IMAGE && settings.get_boolean ("show-preview"))
            set_thumbnail (image, entry);

        /* Label */
        var label = new Gtk.Label (entry.label);
        label.xalign = 0;
        label.ellipsize = Pango.EllipsizeMode.END;
        label.hexpand = true;
        box.pack_start (label, true, true, 0);

        /* Delete button */
        var delete_btn = new Gtk.Button.from_icon_name ("edit-delete-symbolic", Gtk.IconSize.BUTTON);
        delete_btn.relief = Gtk.ReliefStyle.NONE;
        delete_btn.tooltip_text = _("Delete this item");
        delete_btn.clicked.connect (() => delete_requested (entry));
        box.pack_end (delete_btn, false, false, 0);

        row.show_all ();
        rows[entry] = row;
        return row;
    }

    /* Only the small stored thumbnail is ever decoded for displau */
    private void set_thumbnail (Gtk.Image image, Entry entry) {
        if (entry.thumbnail == null) {
            var png = store.load_thumbnail (entry);
            if (png == null)
                return;
            try {
                entry.thumbnail = new Gdk.Pixbuf.from_stream (new MemoryInputStream.from_bytes (png));
            } catch (Error e) {
                warning ("Could not decode thumbnail: %s", e.message);
                return;
            }
        }

        int scale = image.get_scale_factor ();
        var pixbuf = entry.thumbnail;
        int size = THUMB_DISPLAY_SIZE * scale;
        if (pixbuf.width > size || pixbuf.height > size) {
            double ratio = double.min ((double) size / pixbuf.width, (double) size / pixbuf.height);
            pixbuf = pixbuf.scale_simple (int.max (1, (int) (pixbuf.width * ratio)),
                                          int.max (1, (int) (pixbuf.height * ratio)),
                                          Gdk.InterpType.BILINEAR);
        }
        image.surface = Gdk.cairo_surface_create_from_pixbuf (pixbuf, scale, null);
    }

    private void on_entry_added (Entry entry) {
        if (rows_built)
            list_box.insert (create_row (entry), 0);
        update_empty_state ();
    }

    private void on_entry_promoted (Entry entry) {
        var row = rows[entry];
        if (row == null || row.get_index () == 0)
            return;
        list_box.remove (row);
        list_box.insert (row, 0);
    }

    private void on_entry_removed (Entry entry) {
        var row = rows[entry];
        if (row != null) {
            rows.remove (entry);
            row.destroy ();
        }
        update_empty_state ();
    }

    private void on_store_cleared () {
        foreach (var row in rows.get_values ())
            row.destroy ();
        rows.remove_all ();
        update_empty_state ();
    }

    private bool filter_row (Gtk.ListBoxRow row) {
        if (needle == "")
            return true;
        var entry = row.get_data<Entry> ("entry");
        return entry.matches (needle) || entry.label.casefold ().contains (needle);
    }

    private void on_search_changed () {
        needle = search_entry.text.strip ().casefold ();
        list_box.invalidate_filter ();
        update_empty_state ();
    }

    private void update_empty_state () {
        bool any = false;
        store.foreach ((entry) => {
            if (!any && (needle == "" || entry.matches (needle) || entry.label.casefold ().contains (needle)))
                any = true;
        });
        stack.visible_child_name = any ? "list" : "empty";
    }

    private void activate_first_visible () {
        foreach (var child in list_box.get_children ()) {
            var row = (Gtk.ListBoxRow) child;
            if (row.get_child_visible () && filter_row (row)) {
                row.activate ();
                return;
            }
        }
    }

    private void on_row_activated (Gtk.ListBoxRow row) {
        var entry = row.get_data<Entry> ("entry");
        if (entry != null) {
            hide ();
            entry_activated (entry);
        }
    }

    private bool on_key_press (Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.Escape) {
            hide ();
            return true;
        }

        /* Focus search on typing */
        if (!search_entry.has_focus && event.keyval >= Gdk.Key.space && event.keyval <= Gdk.Key.asciitilde)
            search_entry.grab_focus_without_selecting ();

        return false;
    }
}

}
