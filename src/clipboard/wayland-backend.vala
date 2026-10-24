/*
 * wayland-backend.vala
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

#if HAVE_WAYLAND
namespace Clipman {

/*
 * Clipboard access on Wayland through the data-control protocols, which
 * let a privileged client see and set the selection without having focus.
 * Prefers ext-data-control-v1 and falls back to wlr-data-control (Wayfire
 * offers both). Objects live on GDK's own connection and default queue, so
 * every event arrives on the main loop like any other GDK event.
 */
public class WaylandBackend : ClipboardBackend {
    internal const string OWN_MARKER = "application/x-mate-clipman-owned";
    private const uint READ_TIMEOUT_SECONDS = 5;

    private unowned Gdk.Display gdk_display;
    private unowned Wl.Display display;
    private Wl.Registry? registry;
    private Wl.Callback? sync_callback;
    private uint32 ext_name;
    private uint32 wlr_name;
    private uint32 wlr_version;
    private DataControlProtocol? protocol;

    /* MIME types announced for each live offer */
    private HashTable<void*, GenericArray<string>> offers =
        new HashTable<void*, GenericArray<string>> (direct_hash, direct_equal);
    private void*[] current_offer = new void*[2];
    private Cancellable?[] reads = new Cancellable?[2];
    /* Content served by each of our live sources */
    private HashTable<void*, Payload> sources = new HashTable<void*, Payload> (direct_hash, direct_equal);

    private const Wl.RegistryListener REGISTRY_LISTENER = { on_global, on_global_remove };
    private const Wl.CallbackListener SYNC_LISTENER = { on_sync_done };

    private class Payload {
        public Kind kind;
        public Bytes data;

        public Payload (Kind kind, Bytes data) {
            this.kind = kind;
            this.data = data;
        }
    }

    public WaylandBackend (Gdk.Display gdk_display) {
        this.gdk_display = gdk_display;
        display = GdkWayland.get_wl_display (gdk_display);
    }

    public override bool can_paste {
        get { return false; }
    }

    public override void start () {
        if (registry != null)
            return;

        registry = display.get_registry ();
        registry.add_listener (REGISTRY_LISTENER, this);
        sync_callback = GdkWayland.display_sync (display);
        sync_callback.add_listener (SYNC_LISTENER, this);
        display.flush ();
    }

    public override void stop () {
        foreach (var cancellable in reads) {
            if (cancellable != null)
                cancellable.cancel ();
        }
        if (protocol != null) {
            foreach (var source in sources.get_keys ())
                protocol.source_destroy (source);
            foreach (var offer in offers.get_keys ())
                protocol.offer_destroy (offer);
        }
        sources.remove_all ();
        offers.remove_all ();
        current_offer = new void*[2];
        protocol = null;
        sync_callback = null;
        registry = null;
        display.flush ();
    }

    public override void offer (Selection selection, Kind kind, Bytes data) {
        if (protocol == null || (selection == Selection.PRIMARY && !protocol.has_primary))
            return;

        void* source = protocol.create_source (this);
        foreach (var mime_type in mime_types_for (kind))
            protocol.source_offer (source, mime_type);
        protocol.source_offer (source, OWN_MARKER);
        sources[source] = new Payload (kind, data);
        protocol.set_selection (selection, source);
        display.flush ();
    }

    private static void on_global (void* data, Wl.Registry registry, uint32 name,
                                   string interface_name, uint32 version) {
        var self = (WaylandBackend) data;
        if (interface_name == "ext_data_control_manager_v1") {
            self.ext_name = name;
        } else if (interface_name == "zwlr_data_control_manager_v1") {
            self.wlr_name = name;
            self.wlr_version = version;
        }
    }

    private static void on_global_remove (void* data, Wl.Registry registry, uint32 name) {
    }

    private static void on_sync_done (void* data, Wl.Callback callback, uint32 serial) {
        var self = (WaylandBackend) data;
        self.sync_callback = null;
        self.bind_protocol ();
    }

    private void bind_protocol () {
        unowned Wl.Seat seat = GdkWayland.get_wl_seat (gdk_display.get_default_seat ());

        if (ext_name != 0) {
            protocol = new ExtProtocol (this, registry, ext_name, seat);
        } else if (wlr_name != 0) {
            protocol = new WlrProtocol (this, registry, wlr_name, uint32.min (wlr_version, 2), seat);
        } else {
            warning ("The compositor supports neither ext-data-control-v1 nor "
                     + "wlr-data-control-unstable-v1; clipboard history is disabled");
            return;
        }
        display.flush ();
    }

    internal void handle_data_offer (void* offer) {
        offers[offer] = new GenericArray<string> ();
    }

    internal void handle_offer_mime (void* offer, string mime_type) {
        unowned GenericArray<string>? mime_types = offers[offer];
        if (mime_types != null)
            mime_types.add (mime_type);
    }

    internal void handle_selection (Selection selection, void* offer) {
        void* previous = current_offer[selection];
        current_offer[selection] = offer;
        if (previous != null && previous != offer)
            drop_offer (previous);

        if (reads[selection] != null) {
            reads[selection].cancel ();
            reads[selection] = null;
        }

        if (offer == null) {
            lost (selection);
            return;
        }
        if (selection == Selection.PRIMARY && !watch_primary)
            return;

        unowned GenericArray<string>? mime_types = offers[offer];
        if (mime_types == null || has_type (mime_types, OWN_MARKER) || has_type (mime_types, PASSWORD_HINT))
            return;

        Kind kind;
        var mime_type = choose_type (mime_types, out kind);
        if (mime_type != null)
            read_offer.begin (selection, offer, mime_type, kind);
    }

    internal void handle_finished () {
        warning ("The compositor withdrew clipboard access");
        protocol = null;
        offers.remove_all ();
        sources.remove_all ();
        current_offer = new void*[2];
    }

    internal void handle_send (void* source, string mime_type, int fd) {
        unowned Payload? payload = sources[source];
        if (payload == null) {
            Posix.close (fd);
            return;
        }
        write_and_close.begin (fd, convert_for (payload.kind, payload.data, mime_type));
    }

    internal void handle_cancelled (void* source) {
        sources.remove (source);
        if (protocol != null)
            protocol.source_destroy (source);
    }

    private void drop_offer (void* offer) {
        if (offers.remove (offer) && protocol != null)
            protocol.offer_destroy (offer);
    }

    private string? choose_type (GenericArray<string> mime_types, out Kind kind) {
        kind = Kind.TEXT;
        /* Same priority as before... */
        if (has_type (mime_types, "text/uri-list")) {
            kind = Kind.FILES;
            return save_files ? "text/uri-list" : null;
        }
        if (has_type (mime_types, "image/png")) {
            kind = Kind.IMAGE;
            return save_images ? "image/png" : null;
        }
        foreach (var type in TEXT_TYPES) {
            if (has_type (mime_types, type))
                return type;
        }
        return null;
    }

    private static bool has_type (GenericArray<string> mime_types, string type) {
        return mime_types.find_with_equal_func (type, str_equal);
    }

    private async void read_offer (Selection selection, void* offer, string mime_type, Kind kind) {
        int fds[2];
        try {
            Unix.open_pipe (fds, Posix.FD_CLOEXEC);
            Unix.set_fd_nonblocking (fds[0], true);
        } catch (Error e) {
            warning ("Could not create a pipe: %s", e.message);
            return;
        }

        protocol.offer_receive (offer, mime_type, fds[1]);
        Posix.close (fds[1]);
        display.flush ();

        var cancellable = new Cancellable ();
        reads[selection] = cancellable;
        uint timeout = 0;
        timeout = Timeout.add_seconds (READ_TIMEOUT_SECONDS, () => {
            timeout = 0;
            cancellable.cancel ();
            return Source.REMOVE;
        });

        Bytes? data = null;
        try {
            data = yield read_limited (new UnixInputStream (fds[0], true), max_bytes (kind), cancellable);
        } catch (IOError.CANCELLED e) {
        } catch (Error e) {
            debug ("Skipped clipboard content: %s", e.message);
        }

        if (timeout != 0)
            Source.remove (timeout);
        if (reads[selection] == cancellable)
            reads[selection] = null;
        if (data != null && data.length > 0 && !cancellable.is_cancelled ())
            received (selection, kind, data);
    }

    private static async void write_and_close (int fd, Bytes data) {
        try {
            Unix.set_fd_nonblocking (fd, true);
            var stream = new UnixOutputStream (fd, true);
            size_t written;
            yield stream.write_all_async (data.get_data (), Priority.DEFAULT, null, out written);
            yield stream.close_async ();
        } catch (Error e) {
            debug ("Could not hand clipboard content over: %s", e.message);
        }
    }
}

/*
 * The two data-control protocols are identical apart from their C names;
 * these shims let the backend above drive either through opaque handles.
 */
private abstract class DataControlProtocol : Object {
    public abstract bool has_primary { get; }
    public abstract void* create_source (WaylandBackend backend);
    public abstract void source_offer (void* source, string mime_type);
    public abstract void source_destroy (void* source);
    public abstract void set_selection (Selection selection, void* source);
    public abstract void offer_receive (void* offer, string mime_type, int fd);
    public abstract void offer_destroy (void* offer);
}

private class ExtProtocol : DataControlProtocol {
    private DataControl.ExtManager manager;
    private DataControl.ExtDevice device;

    private const DataControl.ExtDeviceListener DEVICE_LISTENER = {
        on_data_offer, on_selection, on_finished, on_primary_selection
    };
    private const DataControl.ExtOfferListener OFFER_LISTENER = { on_offer };
    private const DataControl.ExtSourceListener SOURCE_LISTENER = { on_send, on_cancelled };

    public ExtProtocol (WaylandBackend backend, Wl.Registry registry, uint32 name, Wl.Seat seat) {
        manager = registry.bind<DataControl.ExtManager> (name, ref DataControl.ext_manager_interface, 1);
        device = manager.get_data_device (seat);
        device.add_listener (DEVICE_LISTENER, backend);
    }

    public override bool has_primary {
        get { return true; }
    }

    public override void* create_source (WaylandBackend backend) {
        unowned DataControl.ExtSource source = manager.create_data_source ();
        source.add_listener (SOURCE_LISTENER, backend);
        return source;
    }

    public override void source_offer (void* source, string mime_type) {
        ((DataControl.ExtSource) source).offer (mime_type);
    }

    public override void source_destroy (void* source) {
        ((DataControl.ExtSource) source).destroy ();
    }

    public override void set_selection (Selection selection, void* source) {
        if (selection == Selection.PRIMARY)
            device.set_primary_selection ((DataControl.ExtSource) source);
        else
            device.set_selection ((DataControl.ExtSource) source);
    }

    public override void offer_receive (void* offer, string mime_type, int fd) {
        ((DataControl.ExtOffer) offer).receive (mime_type, fd);
    }

    public override void offer_destroy (void* offer) {
        ((DataControl.ExtOffer) offer).destroy ();
    }

    private static void on_data_offer (void* data, DataControl.ExtDevice device, DataControl.ExtOffer offer) {
        offer.add_listener (OFFER_LISTENER, data);
        ((WaylandBackend) data).handle_data_offer (offer);
    }

    private static void on_selection (void* data, DataControl.ExtDevice device, DataControl.ExtOffer? offer) {
        ((WaylandBackend) data).handle_selection (Selection.CLIPBOARD, offer);
    }

    private static void on_primary_selection (void* data, DataControl.ExtDevice device, DataControl.ExtOffer? offer) {
        ((WaylandBackend) data).handle_selection (Selection.PRIMARY, offer);
    }

    private static void on_finished (void* data, DataControl.ExtDevice device) {
        ((WaylandBackend) data).handle_finished ();
    }

    private static void on_offer (void* data, DataControl.ExtOffer offer, string mime_type) {
        ((WaylandBackend) data).handle_offer_mime (offer, mime_type);
    }

    private static void on_send (void* data, DataControl.ExtSource source, string mime_type, int32 fd) {
        ((WaylandBackend) data).handle_send (source, mime_type, fd);
    }

    private static void on_cancelled (void* data, DataControl.ExtSource source) {
        ((WaylandBackend) data).handle_cancelled (source);
    }
}

private class WlrProtocol : DataControlProtocol {
    private DataControl.WlrManager manager;
    private DataControl.WlrDevice device;

    private const DataControl.WlrDeviceListener DEVICE_LISTENER = {
        on_data_offer, on_selection, on_finished, on_primary_selection
    };
    private const DataControl.WlrOfferListener OFFER_LISTENER = { on_offer };
    private const DataControl.WlrSourceListener SOURCE_LISTENER = { on_send, on_cancelled };

    public WlrProtocol (WaylandBackend backend, Wl.Registry registry, uint32 name, uint32 version, Wl.Seat seat) {
        manager = registry.bind<DataControl.WlrManager> (name, ref DataControl.wlr_manager_interface, version);
        device = manager.get_data_device (seat);
        device.add_listener (DEVICE_LISTENER, backend);
    }

    /* Primary selection arrived in main version 2 bumop of the wlr protocol */
    public override bool has_primary {
        get { return manager.get_version () >= 2; }
    }

    public override void* create_source (WaylandBackend backend) {
        unowned DataControl.WlrSource source = manager.create_data_source ();
        source.add_listener (SOURCE_LISTENER, backend);
        return source;
    }

    public override void source_offer (void* source, string mime_type) {
        ((DataControl.WlrSource) source).offer (mime_type);
    }

    public override void source_destroy (void* source) {
        ((DataControl.WlrSource) source).destroy ();
    }

    public override void set_selection (Selection selection, void* source) {
        if (selection == Selection.PRIMARY)
            device.set_primary_selection ((DataControl.WlrSource) source);
        else
            device.set_selection ((DataControl.WlrSource) source);
    }

    public override void offer_receive (void* offer, string mime_type, int fd) {
        ((DataControl.WlrOffer) offer).receive (mime_type, fd);
    }

    public override void offer_destroy (void* offer) {
        ((DataControl.WlrOffer) offer).destroy ();
    }

    private static void on_data_offer (void* data, DataControl.WlrDevice device, DataControl.WlrOffer offer) {
        offer.add_listener (OFFER_LISTENER, data);
        ((WaylandBackend) data).handle_data_offer (offer);
    }

    private static void on_selection (void* data, DataControl.WlrDevice device, DataControl.WlrOffer? offer) {
        ((WaylandBackend) data).handle_selection (Selection.CLIPBOARD, offer);
    }

    private static void on_primary_selection (void* data, DataControl.WlrDevice device, DataControl.WlrOffer? offer) {
        ((WaylandBackend) data).handle_selection (Selection.PRIMARY, offer);
    }

    private static void on_finished (void* data, DataControl.WlrDevice device) {
        ((WaylandBackend) data).handle_finished ();
    }

    private static void on_offer (void* data, DataControl.WlrOffer offer, string mime_type) {
        ((WaylandBackend) data).handle_offer_mime (offer, mime_type);
    }

    private static void on_send (void* data, DataControl.WlrSource source, string mime_type, int32 fd) {
        ((WaylandBackend) data).handle_send (source, mime_type, fd);
    }

    private static void on_cancelled (void* data, DataControl.WlrSource source) {
        ((WaylandBackend) data).handle_cancelled (source);
    }
}

}
#endif
