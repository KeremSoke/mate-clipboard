/*
 * entry.vala
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

public enum Kind {
    TEXT = 0,
    IMAGE = 1,
    FILES = 2;

    public static bool is_valid (int value) {
        return value >= TEXT && value <= FILES;
    }
}

public enum Selection {
    CLIPBOARD = 0,
    PRIMARY = 1
}

/* Size caps keep a single huge copy from bloating memory and the database. */
public const size_t MAX_TEXT_BYTES = 8 * 1024 * 1024;
public const size_t MAX_IMAGE_BYTES = 32 * 1024 * 1024;
/* A small PNG can still claim huge dimensions; never decode those. */
public const uint64 MAX_IMAGE_PIXELS = 64 * 1024 * 1024;
/* Characters of text kept decrypted in memory for labels and searching. */
public const int PREVIEW_CHARS = 2048;
public const int LABEL_CHARS = 100;
/* Thumbnails are stored at twice the displayed size for HiDPI screens. */
public const int THUMB_DISPLAY_SIZE = 48;
public const int THUMB_STORED_SIZE = THUMB_DISPLAY_SIZE * 2;

/*
 * One history item.  Only the small preview lives in memory; the payload
 * (and an image's thumbnail) stay encrypted in the store until needed
 */
public class Entry : Object {
    public int64 id { get; set; }
    public Kind kind { get; construct; }
    public int64 stamp { get; set; }
    /* Text: first PREVIEW_CHARS characters.  Files: the URI list
     * Images: "WIDTHxHEIGHT" */
    public string preview { get; construct; }

    internal uint8[] digest;
    /* Sealed blobs for history that is not written to disk */
    internal Bytes? sealed_payload;
    internal Bytes? sealed_thumb;
    /* Decoded thumbnail, cached once a history row has needed it */
    internal Gdk.Pixbuf? thumbnail;

    private string? _label;
    private string? _search_key;

    public Entry (Kind kind, string preview) {
        Object (kind: kind, preview: preview);
    }

    public string label {
        get {
            if (_label == null)
                _label = build_label ();
            return _label;
        }
    }

    public bool matches (string casefolded_needle) {
        if (_search_key == null)
            _search_key = preview.casefold ();
        return casefolded_needle in _search_key;
    }

    internal string map_key {
        owned get { return key_for (kind, digest); }
    }

    internal static string key_for (Kind kind, uint8[] digest) {
        var builder = new StringBuilder ();
        builder.append_printf ("%d:", (int) kind);
        foreach (var b in digest)
            builder.append_printf ("%02x", b);
        return builder.str;
    }

    private string build_label () {
        switch (kind) {
        case Kind.IMAGE:
            int width = 0, height = 0;
            preview.scanf ("%dx%d", out width, out height);
            return _("[Image %dx%d]").printf (width, height);
        case Kind.FILES:
            var uris = split_uri_list (preview);
            if (uris.length == 1) {
                var file = File.new_for_uri (uris[0]);
                return _("[File: %s]").printf (file.get_basename () ?? uris[0]);
            }
            return _("[%u files]").printf (uris.length);
        default:
            return create_label (preview, LABEL_CHARS);
        }
    }
}

/* Splits a text/uri-list body, skipping comments and blank lines. */
public string[] split_uri_list (string text) {
    string[] uris = {};
    foreach (var line in text.split ("\n")) {
        var uri = line.strip ();
        if (uri != "" && !uri.has_prefix ("#"))
            uris += uri;
    }
    return uris;
}

/* Reads a PNG's dimensions from its IHDR chunk without decoding it. */
public bool png_dimensions (Bytes png, out uint32 width, out uint32 height) {
    width = 0;
    height = 0;
    unowned uint8[] d = png.get_data ();
    const uint8[] SIGNATURE = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
    if (png.length < 24)
        return false;
    for (int i = 0; i < SIGNATURE.length; i++) {
        if (d[i] != SIGNATURE[i])
            return false;
    }
    width = (uint32) d[16] << 24 | (uint32) d[17] << 16 | (uint32) d[18] << 8 | (uint32) d[19];
    height = (uint32) d[20] << 24 | (uint32) d[21] << 16 | (uint32) d[22] << 8 | (uint32) d[23];
    return width > 0 && height > 0;
}

/* Clipboard bytes are not NUL-terminated; copy them into a valid string. */
public string bytes_to_string (Bytes data) {
    unowned uint8[] raw = data.get_data ();
    return ((string) raw).make_valid ((ssize_t) data.length);
}

/* Takes at most @max_chars characters of valid UTF-8 from @text. */
public string utf8_prefix (string text, int max_chars) {
    var valid = text.make_valid ();
    if (valid.char_count () <= max_chars)
        return valid;
    return valid.substring (0, valid.index_of_nth_char (max_chars));
}

/* Collapses whitespace into single spaces and ellipsizes long text. */
public string create_label (string text, int max_chars) {
    var builder = new StringBuilder ();
    bool prev_space = false;
    unichar c;
    for (int i = 0; text.get_next_char (ref i, out c);) {
        if (c == '\n' || c == '\r' || c == '\t' || c == ' ') {
            if (!prev_space)
                builder.append_c (' ');
            prev_space = true;
        } else {
            builder.append_unichar (c);
            prev_space = false;
        }
    }

    var label = builder.str.strip ();
    if (label.char_count () > max_chars)
        label = label.substring (0, label.index_of_nth_char (max_chars - 3)) + "...";
    return label;
}

}
