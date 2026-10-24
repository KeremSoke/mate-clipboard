/* The few GDK Wayland backend calls needed to share GDK's connection. */

[CCode (cheader_filename = "gdk/gdkwayland.h")]
namespace GdkWayland {
	[CCode (cname = "GDK_IS_WAYLAND_DISPLAY")]
	public static bool is_wayland_display (Gdk.Display display);

	[CCode (cname = "gdk_wayland_display_get_wl_display")]
	public static unowned Wl.Display get_wl_display (Gdk.Display display);

	[CCode (cname = "gdk_wayland_seat_get_wl_seat")]
	public static unowned Wl.Seat get_wl_seat (Gdk.Seat seat);

	/* wayland-client.vapi only exposes an unowned wl_display_sync(). */
	[CCode (cname = "wl_display_sync")]
	public static Wl.Callback display_sync (Wl.Display display);
}
