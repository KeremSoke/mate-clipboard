# 📋 MATE Clipboard Manager

A clipboard history applet for the MATE panel, written in Vala. (Unlike 1.x version!) It works on MATE under **both X11** and **Wayland** (Wayfire, or any compositor with the data-control protocol).

## ✨ Features

- 📜 **Clipboard history**: text, images and copied files
- 🔍 **Search**: type to filter the history instantly
- 🧩 **Panel applet**: click it to open the history next to the panel
- ⌨️ **Keyboard shortcut**: open the history at the mouse pointer (X11) or next to the applet
- 🔐 **Encrypted history**: stored encrypted with XChaCha20-Poly1305, with the key kept in your login keyring
- 🖼️ **Image thumbnails**: small previews, stored separately from the full image
- 🖱️ **Primary selection**: optionally track the mouse selection and keep it in sync
- 🛡️ **Content filtering**: skip text matching a regular expression, and anything password managers mark as secret

> [!CAUTION]
> If you used version 1.x, its old **unencrypted** history is still at `~/.local/share/mate-clipman/history.db`. This version does not read it; delete the file once you no longer need it.

## 🛠️ Building

### 📦 Dependencies

```bash
# Debian / Ubuntu
sudo apt install meson ninja-build valac gettext \
    libgtk-3-dev libmate-panel-applet-dev libsqlite3-dev libsodium-dev libsecret-1-dev \
    libx11-dev libxtst-dev \
    libwayland-dev wayland-protocols libgtk-layer-shell-dev

# Fedora
sudo dnf install meson ninja-build vala gettext \
    gtk3-devel mate-panel-devel sqlite-devel libsodium-devel libsecret-devel \
    libX11-devel libXtst-devel \
    wayland-devel wayland-protocols-devel gtk-layer-shell-devel
```

The X11 and Wayland parts are optional: build without one with `-Dx11=disabled` or `-Dwayland=disabled`. Wayland support needs wayland-protocols 1.39 or newer.

### 🔨 Compile and install

```bash
meson setup builddir --prefix=/usr
meson compile -C builddir
meson test -C builddir
sudo meson install -C builddir
```

Installing also compiles the GSettings schemas. Then right-click the panel, choose **Add to Panel…** and pick **Clipboard Manager**. The applet is loaded inside the panel process, as Wayland requires.

## 💡 Usage

- **Click** the applet to open the history; click again or press <kbd>Esc</kbd> to close it.
- **Type** to search. <kbd>Enter</kbd> picks the first match.
- **Pick** an item to put it back on the clipboard.
- **Right-click** the applet for Preferences, Clear History and About.

The search box sits at the edge nearest the panel: at the top for a top panel and when opened at the pointer, at the bottom for a bottom panel.

### ⌨️ Keyboard shortcut

The applet offers a D-Bus method that opens the history. To bind it to a key (e.g. <kbd>Super</kbd>+<kbd>V</kbd>):

1. Open **MATE Control Center** → **Hardware** → **Keyboard Shortcuts**
2. Click **Add**, name it "Clipboard History" and use this command:

   ```bash
   gdbus call --session --dest org.mate.Clipman --object-path /org/mate/Clipman --method org.mate.Clipman.ShowHistory
   ```

3. Click the new shortcut and press your key combination.

On Wayfire, add the same command as a binding in `wayfire.ini` instead. The command is also in the Preferences dialog, with a copy button.

Under **History Dialog** in Preferences you choose whether the shortcut opens the history at the mouse pointer or next to the applet. On Wayland it always opens next to the applet, because Wayland programs cannot see where the pointer is.

## ⚡ Performance

- Older items are deleted as new ones arrive, and the database file is compacted.
- Copied images are decoded and scaled on a worker thread. 
- Items over 8 MiB of text or 32 MiB of image data are skipped.

## ⚖️ License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

`protocols/wlr-data-control-unstable-v1.xml` comes from wlr-protocols and keeps its own permissive license, shown at the top of that file.

## 👏 Credits

- Inspired by [Diodon](https://launchpad.net/diodon)

Hopefully one day will be a part of the MATE Desktop ecosystem 💚
