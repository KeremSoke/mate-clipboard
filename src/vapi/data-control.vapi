/* Bindings for the wayland-scanner client code of ext-data-control-v1 and
 * wlr-data-control-unstable-v1.  Both protocols carry the same requests and
 * events, so the two halves below are identical apart from C names. */

[CCode (cprefix = "", lower_case_cprefix = "")]
namespace DataControl {
	/* ext-data-control-v1 */

	[CCode (cheader_filename = "ext-data-control-v1-client-protocol.h", cname = "ext_data_control_manager_v1_interface")]
	public Wl.Interface ext_manager_interface;

	[Compact]
	[CCode (cheader_filename = "ext-data-control-v1-client-protocol.h", cname = "struct ext_data_control_manager_v1", free_function = "ext_data_control_manager_v1_destroy")]
	public class ExtManager : Wl.Proxy {
		[CCode (cname = "ext_data_control_manager_v1_create_data_source")]
		public unowned ExtSource create_data_source ();
		[CCode (cname = "ext_data_control_manager_v1_get_data_device")]
		public ExtDevice get_data_device (Wl.Seat seat);
	}

	[Compact]
	[CCode (cheader_filename = "ext-data-control-v1-client-protocol.h", cname = "struct ext_data_control_device_v1", free_function = "ext_data_control_device_v1_destroy")]
	public class ExtDevice : Wl.Proxy {
		[CCode (cname = "ext_data_control_device_v1_add_listener")]
		public int add_listener (ExtDeviceListener listener, void* data);
		[CCode (cname = "ext_data_control_device_v1_set_selection")]
		public void set_selection (ExtSource? source);
		[CCode (cname = "ext_data_control_device_v1_set_primary_selection")]
		public void set_primary_selection (ExtSource? source);
	}

	[Compact]
	[CCode (cheader_filename = "ext-data-control-v1-client-protocol.h", cname = "struct ext_data_control_source_v1", free_function = "ext_data_control_source_v1_destroy")]
	public class ExtSource : Wl.Proxy {
		[CCode (cname = "ext_data_control_source_v1_add_listener")]
		public int add_listener (ExtSourceListener listener, void* data);
		[CCode (cname = "ext_data_control_source_v1_offer")]
		public void offer (string mime_type);
		[CCode (cname = "ext_data_control_source_v1_destroy")]
		public void destroy ();
	}

	[Compact]
	[CCode (cheader_filename = "ext-data-control-v1-client-protocol.h", cname = "struct ext_data_control_offer_v1", free_function = "ext_data_control_offer_v1_destroy")]
	public class ExtOffer : Wl.Proxy {
		[CCode (cname = "ext_data_control_offer_v1_add_listener")]
		public int add_listener (ExtOfferListener listener, void* data);
		[CCode (cname = "ext_data_control_offer_v1_receive")]
		public void receive (string mime_type, int32 fd);
		[CCode (cname = "ext_data_control_offer_v1_destroy")]
		public void destroy ();
	}

	[CCode (cname = "struct ext_data_control_device_v1_listener", has_type_id = false)]
	public struct ExtDeviceListener {
		public ExtDeviceDataOffer data_offer;
		public ExtDeviceSelection selection;
		public ExtDeviceFinished finished;
		public ExtDeviceSelection primary_selection;
	}

	[CCode (cname = "struct ext_data_control_source_v1_listener", has_type_id = false)]
	public struct ExtSourceListener {
		public ExtSourceSend send;
		public ExtSourceCancelled cancelled;
	}

	[CCode (cname = "struct ext_data_control_offer_v1_listener", has_type_id = false)]
	public struct ExtOfferListener {
		public ExtOfferOffer offer;
	}

	[CCode (has_target = false, has_typedef = false)]
	public delegate void ExtDeviceDataOffer (void* data, ExtDevice device, ExtOffer offer);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void ExtDeviceSelection (void* data, ExtDevice device, ExtOffer? offer);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void ExtDeviceFinished (void* data, ExtDevice device);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void ExtSourceSend (void* data, ExtSource source, string mime_type, int32 fd);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void ExtSourceCancelled (void* data, ExtSource source);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void ExtOfferOffer (void* data, ExtOffer offer, string mime_type);

	/* wlr-data-control-unstable-v1 */

	[CCode (cheader_filename = "wlr-data-control-unstable-v1-client-protocol.h", cname = "zwlr_data_control_manager_v1_interface")]
	public Wl.Interface wlr_manager_interface;

	[Compact]
	[CCode (cheader_filename = "wlr-data-control-unstable-v1-client-protocol.h", cname = "struct zwlr_data_control_manager_v1", free_function = "zwlr_data_control_manager_v1_destroy")]
	public class WlrManager : Wl.Proxy {
		[CCode (cname = "zwlr_data_control_manager_v1_create_data_source")]
		public unowned WlrSource create_data_source ();
		[CCode (cname = "zwlr_data_control_manager_v1_get_data_device")]
		public WlrDevice get_data_device (Wl.Seat seat);
	}

	[Compact]
	[CCode (cheader_filename = "wlr-data-control-unstable-v1-client-protocol.h", cname = "struct zwlr_data_control_device_v1", free_function = "zwlr_data_control_device_v1_destroy")]
	public class WlrDevice : Wl.Proxy {
		[CCode (cname = "zwlr_data_control_device_v1_add_listener")]
		public int add_listener (WlrDeviceListener listener, void* data);
		[CCode (cname = "zwlr_data_control_device_v1_set_selection")]
		public void set_selection (WlrSource? source);
		[CCode (cname = "zwlr_data_control_device_v1_set_primary_selection")]
		public void set_primary_selection (WlrSource? source);
	}

	[Compact]
	[CCode (cheader_filename = "wlr-data-control-unstable-v1-client-protocol.h", cname = "struct zwlr_data_control_source_v1", free_function = "zwlr_data_control_source_v1_destroy")]
	public class WlrSource : Wl.Proxy {
		[CCode (cname = "zwlr_data_control_source_v1_add_listener")]
		public int add_listener (WlrSourceListener listener, void* data);
		[CCode (cname = "zwlr_data_control_source_v1_offer")]
		public void offer (string mime_type);
		[CCode (cname = "zwlr_data_control_source_v1_destroy")]
		public void destroy ();
	}

	[Compact]
	[CCode (cheader_filename = "wlr-data-control-unstable-v1-client-protocol.h", cname = "struct zwlr_data_control_offer_v1", free_function = "zwlr_data_control_offer_v1_destroy")]
	public class WlrOffer : Wl.Proxy {
		[CCode (cname = "zwlr_data_control_offer_v1_add_listener")]
		public int add_listener (WlrOfferListener listener, void* data);
		[CCode (cname = "zwlr_data_control_offer_v1_receive")]
		public void receive (string mime_type, int32 fd);
		[CCode (cname = "zwlr_data_control_offer_v1_destroy")]
		public void destroy ();
	}

	[CCode (cname = "struct zwlr_data_control_device_v1_listener", has_type_id = false)]
	public struct WlrDeviceListener {
		public WlrDeviceDataOffer data_offer;
		public WlrDeviceSelection selection;
		public WlrDeviceFinished finished;
		public WlrDeviceSelection primary_selection;
	}

	[CCode (cname = "struct zwlr_data_control_source_v1_listener", has_type_id = false)]
	public struct WlrSourceListener {
		public WlrSourceSend send;
		public WlrSourceCancelled cancelled;
	}

	[CCode (cname = "struct zwlr_data_control_offer_v1_listener", has_type_id = false)]
	public struct WlrOfferListener {
		public WlrOfferOffer offer;
	}

	[CCode (has_target = false, has_typedef = false)]
	public delegate void WlrDeviceDataOffer (void* data, WlrDevice device, WlrOffer offer);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void WlrDeviceSelection (void* data, WlrDevice device, WlrOffer? offer);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void WlrDeviceFinished (void* data, WlrDevice device);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void WlrSourceSend (void* data, WlrSource source, string mime_type, int32 fd);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void WlrSourceCancelled (void* data, WlrSource source);
	[CCode (has_target = false, has_typedef = false)]
	public delegate void WlrOfferOffer (void* data, WlrOffer offer, string mime_type);
}
