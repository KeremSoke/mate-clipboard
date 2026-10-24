/* Based on the vapigen output for MatePanelApplet-4.0.gir, with the
 * in-process factory entry point added (it is not introspectable). */

[CCode (cprefix = "MatePanel", lower_case_cprefix = "mate_panel_", cheader_filename = "mate-panel-applet.h,mate-panel-applet-enums.h")]
namespace MatePanel {
	[CCode (type_id = "mate_panel_applet_get_type ()")]
	public class Applet : Gtk.EventBox, Atk.Implementor, Gtk.Buildable {
		[CCode (has_construct_function = false, type = "GtkWidget*")]
		public Applet ();
		[CCode (cname = "mate_panel_applet_factory_setup_in_process")]
		public static int factory_setup_in_process (string factory_id, GLib.Type applet_type, MatePanel.AppletFactoryCallback callback);
		public MatePanel.AppletFlags get_flags ();
		public bool get_locked_down ();
		public MatePanel.AppletOrient get_orient ();
		public uint get_size ();
		public void request_focus (uint32 timestamp);
		[Version (deprecated = true, deprecated_since = "3.20")]
		public void set_background_widget (Gtk.Widget widget);
		public void set_flags (MatePanel.AppletFlags flags);
		public void setup_menu (string xml, Gtk.ActionGroup action_group);
		public signal void change_orient (uint orient);
		public signal void change_size (int size);
	}

	[CCode (cprefix = "MATE_PANEL_APPLET_", type_id = "mate_panel_applet_flags_get_type ()")]
	[Flags]
	public enum AppletFlags {
		FLAGS_NONE,
		EXPAND_MAJOR,
		EXPAND_MINOR,
		HAS_HANDLE
	}

	/* The direction popups open in: DOWN means the panel is at the top. */
	[CCode (cprefix = "MATE_PANEL_APPLET_ORIENT_", type_id = "mate_panel_applet_orient_get_type ()")]
	public enum AppletOrient {
		UP,
		DOWN,
		LEFT,
		RIGHT
	}

	[CCode (instance_pos = 2.9)]
	public delegate bool AppletFactoryCallback (MatePanel.Applet applet, string iid);
}
