/*
 * applet.vala
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

private const string APPLET_MENU_XML =
    "<menuitem name=\"Preferences\" action=\"Preferences\"/>"
    + "<menuitem name=\"Clear\" action=\"Clear\"/>"
    + "<separator/>"
    + "<menuitem name=\"About\" action=\"About\"/>";

public class AppletButton : Object, PanelAnchor {
    private unowned MatePanel.Applet applet;
    private Service service;
    private Gtk.Image image;
    private Gtk.Button button;

    public AppletButton (MatePanel.Applet applet) {
        this.applet = applet;
        service = Service.register (this);

        applet.set_flags (MatePanel.AppletFlags.EXPAND_MINOR);
        applet.set_background_widget (applet);

        button = new Gtk.Button ();
        button.relief = Gtk.ReliefStyle.NONE;
        image = new Gtk.Image.from_icon_name ("edit-paste", Gtk.IconSize.BUTTON);
        button.add (image);
        applet.add (button);
        button.tooltip_text = service.error_message ?? _("Clipboard History");
        update_icon_size ();

        button.clicked.connect (() => service.toggle_from_applet (this));
        applet.change_size.connect (update_icon_size);

        var actions = new Gtk.ActionGroup ("ClipmanAppletActions");
        actions.set_translation_domain (Config.GETTEXT_PACKAGE);
        add_action (actions, "Preferences", "preferences-system", _("_Preferences"),
                    () => service.show_preferences ());
        add_action (actions, "Clear", "edit-clear-all", _("_Clear History"),
                    () => service.request_clear ());
        add_action (actions, "About", "help-about", _("_About"), show_about);
        applet.setup_menu (APPLET_MENU_XML, actions);

        applet.destroy.connect (() => service.unregister (this));
        applet.show_all ();
    }

    public Gtk.Widget widget {
        get { return applet; }
    }

    public MatePanel.AppletOrient orient {
        get { return applet.get_orient (); }
    }

    private static void add_action (Gtk.ActionGroup group, string name, string icon,
                                    string label, owned ActivateFunc callback) {
        var action = new Gtk.Action (name, label, null, null);
        action.icon_name = icon;
        action.activate.connect (() => callback ());
        group.add_action (action);
    }

    private delegate void ActivateFunc ();

    private void update_icon_size () {
        /* Follow the panel size instead of a fixed icon size. */
        int size = (int) applet.get_size ();
        image.pixel_size = (size - 8).clamp (16, 48);
    }

    private static void show_about () {
        Gtk.show_about_dialog (null,
                               "program-name", _("MATE Clipboard Manager"),
                               "version", Config.PACKAGE_VERSION,
                               "comments", _("A clipboard history manager for MATE Desktop"),
                               "copyright", "Copyright \xc2\xa9 2025 Kerem Soke",
                               "license-type", Gtk.License.GPL_3_0,
                               "logo-icon-name", "edit-paste");
    }
}

private bool factory_callback (MatePanel.Applet applet, string iid) {
    if (iid != "ClipmanApplet")
        return false;
    /* Lives exactly as long as the applet widget */
    applet.set_data<AppletButton> ("clipman-applet", new AppletButton (applet));
    return true;
}

}

/* Entry point looked up by mate-panel when loading the applet in-process
 * what MATE_PANEL_APPLET_IN_PROCESS_FACTORY expands to in C */
[CCode (cname = "_mate_panel_applet_shlib_factory")]
public int clipman_shlib_factory () {
    Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
    Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
    return MatePanel.Applet.factory_setup_in_process ("ClipmanAppletFactory", typeof (MatePanel.Applet),
                                                       Clipman.factory_callback);
}
