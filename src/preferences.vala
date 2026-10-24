/*
 * preferences.vala
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

public class Preferences : Gtk.Dialog {
    private unowned Service service;
    private Gtk.Label storage_status;

    public Preferences (Service service) {
        this.service = service;
        var settings = service.settings;

        title = _("Clipboard Manager Preferences");
        set_default_size (450, -1);
        resizable = false;
        add_button (_("_Close"), Gtk.ResponseType.CLOSE);

        var content = get_content_area ();
        content.border_width = 12;

        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        content.add (vbox);

        /* General section */
        vbox.pack_start (section_label (_("General")), false, false, 0);

        var grid = new Gtk.Grid ();
        grid.column_spacing = 12;
        grid.row_spacing = 6;
        vbox.pack_start (indented (grid), false, false, 0);

        var label = new Gtk.Label (_("History size:"));
        label.xalign = 0;
        grid.attach (label, 0, 0, 1, 1);

        var history_size = new Gtk.SpinButton.with_range (1, 500, 1);
        history_size.tooltip_text = _("Maximum number of items to keep in history");
        grid.attach (history_size, 1, 0, 1, 1);
        settings.bind ("history-size", history_size, "value", SettingsBindFlags.DEFAULT);

        add_check (vbox, settings, "keep-content", _("Keep clipboard content when source closes"),
                   _("Restore clipboard content when the application that copied it closes"));
        add_check (vbox, settings, "confirm-clear", _("Confirm before clearing history"), null);
        var paste = add_check (vbox, settings, "paste-on-select",
                               _("Automatically paste when selecting from history"), null);
        if (service.is_wayland) {
            paste.sensitive = false;
            paste.tooltip_text = _("Not available on Wayland");
        }

        /* History dialog section */
        vbox.pack_start (section_label (_("History Dialog")), false, false, 0);

        var at_pointer = new Gtk.RadioButton.with_label (null, _("Open the keyboard shortcut dialog at the mouse pointer"));
        var at_applet = new Gtk.RadioButton.with_label_from_widget (at_pointer, _("Open the keyboard shortcut dialog next to the panel applet"));
        vbox.pack_start (indented (at_pointer), false, false, 0);
        vbox.pack_start (indented (at_applet), false, false, 0);
        at_pointer.active = settings.get_string ("popup-position") == "pointer";
        at_applet.active = !at_pointer.active;
        at_pointer.toggled.connect (() => {
            settings.set_string ("popup-position", at_pointer.active ? "pointer" : "applet");
        });
        if (service.is_wayland) {
            /* Wayland clients cannot learn where the pointer is. */
            at_pointer.sensitive = false;
            at_applet.sensitive = false;
            at_applet.active = true;
            at_pointer.tooltip_text = _("Not available on Wayland");
        }

        var hint = new Gtk.Label (_("To open the history with a key, add this command as a custom shortcut in the Control Center:"));
        hint.xalign = 0;
        hint.wrap = true;
        hint.max_width_chars = 50;
        vbox.pack_start (indented (hint), false, false, 0);

        var command_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        var command = new Gtk.Entry ();
        command.text = Service.SHORTCUT_COMMAND;
        command.editable = false;
        command.hexpand = true;
        command_box.pack_start (command, true, true, 0);
        var copy = new Gtk.Button.from_icon_name ("edit-copy-symbolic", Gtk.IconSize.BUTTON);
        copy.tooltip_text = _("Copy command");
        copy.clicked.connect (() => {
            Gtk.Clipboard.get_for_display (get_display (), Gdk.SELECTION_CLIPBOARD)
                .set_text (Service.SHORTCUT_COMMAND, -1);
        });
        command_box.pack_start (copy, false, false, 0);
        vbox.pack_start (indented (command_box), false, false, 0);

        /* Clipboard section */
        vbox.pack_start (section_label (_("Clipboard Sources")), false, false, 0);
        add_check (vbox, settings, "use-primary-selection", _("Track primary selection (middle-click paste)"),
                   _("Also save text selected with the mouse"));
        add_check (vbox, settings, "sync-selections", _("Synchronize clipboard and primary selection"),
                   _("Keep both selections synchronized"));

        /* Content types section */
        vbox.pack_start (section_label (_("Content Types")), false, false, 0);
        add_check (vbox, settings, "save-images", _("Save images to history"), null);
        add_check (vbox, settings, "save-files", _("Save file paths to history"), null);
        add_check (vbox, settings, "show-preview", _("Show image previews in history"), null);

        /* Privacy section */
        vbox.pack_start (section_label (_("Privacy")), false, false, 0);
        add_check (vbox, settings, "persist-history", _("Save history to disk (encrypted)"),
                   _("When off, history is kept in memory only and is lost when the panel restarts"));

        storage_status = new Gtk.Label (null);
        storage_status.xalign = 0;
        storage_status.wrap = true;
        storage_status.max_width_chars = 50;
        storage_status.get_style_context ().add_class ("dim-label");
        vbox.pack_start (indented (storage_status), false, false, 0);
        update_storage_status ();
        ulong saved_handler = service.notify.connect (update_storage_status);
        ulong persist_handler = settings.changed["persist-history"].connect (update_storage_status);
        destroy.connect (() => {
            SignalHandler.disconnect (service, saved_handler);
            SignalHandler.disconnect (settings, persist_handler);
        });

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.pack_start (new Gtk.Label (_("Exclude pattern:")), false, false, 0);
        var exclude = new Gtk.Entry ();
        exclude.placeholder_text = _("Regular expression");
        exclude.tooltip_text = _("Text matching this pattern will not be saved (e.g., passwords)");
        exclude.hexpand = true;
        box.pack_start (exclude, true, true, 0);
        vbox.pack_start (indented (box), false, false, 0);
        settings.bind ("exclude-pattern", exclude, "text", SettingsBindFlags.DEFAULT);

        vbox.show_all ();
        response.connect (() => destroy ());
    }

    private void update_storage_status () {
        bool persist = service.settings.get_boolean ("persist-history");
        if (service.history_saved) {
            storage_status.label = _("History is encrypted with a key kept in your login keyring.");
        } else if (!persist) {
            storage_status.label = _("History is kept in memory only.");
        } else if (!service.ready) {
            storage_status.label = _("Waiting for the login keyring…");
        } else if (service.saving_failed) {
            storage_status.label = _("The login keyring is unavailable, so history is kept in memory only.");
        } else {
            storage_status.label = _("History will be saved, encrypted, after the panel restarts.");
        }
    }

    private static Gtk.CheckButton add_check (Gtk.Box box, GLib.Settings settings, string key,
                                              string text, string? tooltip) {
        var check = new Gtk.CheckButton.with_label (text);
        check.tooltip_text = tooltip;
        settings.bind (key, check, "active", SettingsBindFlags.DEFAULT);
        box.pack_start (indented (check), false, false, 0);
        return check;
    }

    private static Gtk.Widget section_label (string text) {
        var label = new Gtk.Label (null);
        label.set_markup (Markup.printf_escaped ("<b>%s</b>", text));
        label.xalign = 0;
        label.margin_top = 12;
        label.margin_bottom = 6;
        return label;
    }

    private static Gtk.Widget indented (Gtk.Widget widget) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        box.margin_start = 12;
        box.pack_start (widget, true, true, 0);
        return box;
    }
}

}
