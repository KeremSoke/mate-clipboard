# 📋 MATE Clipboard Manager

A clipboard history manager inspired by [Diodon](https://launchpad.net/diodon) for the MATE Desktop Environment, written in pure C using GTK+ 3 and GObject.

## ✨ Features

- 📜 **Clipboard History**: Stores text, images, and file paths
- 🗃️ **SQLite Storage**: Persistent history with efficient searching
- 🔍 **Search**: Quick search through clipboard history
- 🖱️ **Primary Selection**: Optionally track mouse selection (middle-click paste)
- 🔄 **Selection Sync**: Keep clipboard and primary selection synchronized
- 🛡️ **Content Filtering**: Exclude text matching regex patterns (e.g., passwords)
- 🖼️ **Image Previews**: Show thumbnails in history
- 🧩 **MATE Panel Applet**: Optional panel integration (in progress)
- 📥 **System Tray**: Status icon with menu

## 🛠️ Building

### 📦 Dependencies

Install the required development packages:

```bash
# Debian
sudo apt install meson ninja-build gcc gettext\
    libglib2.0-dev libgtk-3-dev libx11-dev libsqlite3-dev \
    libmate-panel-applet-dev
```

### 🔨 Compile

```bash
# Configure
meson setup builddir

# Build
meson compile -C builddir
```

## 🚀 Installation

### 🌍 System-wide

Install the GSettings schema system-wide so the app works without environment variables:

```bash
# Install 
sudo meson instal -C builddir

# Copy schema to system location
sudo cp data/org.mate.clipman.gschema.xml /usr/share/glib-2.0/schemas/

# Recompile all schemas
sudo glib-compile-schemas /usr/share/glib-2.0/schemas/
```

Now you can run the app directly:

```bash
mate-clipman
```

### 🏠 Local 

If you don't have root access:

```bash
# Compile the local schema
glib-compile-schemas data/

# Make wrapper script executable
chmod +x mate-clipman.sh

# Run using the wrapper
./mate-clipman.sh
```

Or create a wrapper script sets the schema path automatically:

```bash
export GSETTINGS_SCHEMA_DIR=/path/to/mate-clipboard/data
exec /path/to/mate-clipboard/builddir/mate-clipman "$@"
```

## 💡 Usage

### ▶️ Running

```bash
# Normal start (shows history popup)
mate-clipman

# Start hidden in system tray (for autostart)
mate-clipman --hidden
```

### ⌨️ Keyboard Shortcut

To open the clipboard history with a keyboard shortcut (e.g., SUPER+V):

1. Open **MATE Control Center** → **Hardware** → **Keyboard Shortcuts**
2. Click **Add** to create a new custom shortcut
3. Set the name to "Clipboard Manager"
4. Set the command to:
   - If installed system-wide: `mate-clipman`
5. Then click on the shortcut and press your desired key combination (e.g., SUPER+V)

When the app is already running, triggering the shortcut will show the history popup.

### ⚡ Autostart

The application can autostart with your session. After installation, enable the autostart file or add it to your startup applications.

1. Open **MATE Control Center** → **Personal** → **Startup Applications**
2. Click **Add** to create a new custom shortcut
3. Set the name to "MATE Clipboard Manager"
4. Set the command to:
   - If installed system-wide: `mate-clipman --hidden`

## ⚙️ Configuration

Settings are stored in GSettings under the `org.mate.clipman` schema.

### Options

- 📏 **History size**: Number of items to keep (1-500)
- 🖱️ **Track primary selection**: Also save mouse selections
- 🔄 **Synchronize selections**: Keep clipboard and primary in sync
- 🖼️ **Save images**: Include images in history
- 📂 **Save files**: Include copied file paths
- 💾 **Keep content**: Restore clipboard when source app closes
- 👁️ **Show preview**: Display image thumbnails
- ⚠️ **Confirm clear**: Ask before clearing history
- 📋 **Paste on select**: Auto-paste when choosing from history
- 🚫 **Exclude pattern**: Regex for text to exclude

## 🆚 Differences from Diodon

This project was inspired by Diodon but has several differences:

1. **Pure C/GObject**: No Vala, direct GTK+/GLib usage
2. **SQLite Storage**: Instead of Zeitgeist, uses local SQLite database
3. **No Plugin System**: Built-in features only, simpler architecture
4. **MATE Integration**: Native panel applet support
5. **Different UI**: Popup window with search instead of menu-only
6. **Focused Features**: Essential clipboard management without complexity

## ⚖️ License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

## 👏 Credits

- Inspired by [Diodon](https://launchpad.net/diodon)

Hopefully one day will be a part of the MATE Desktop ecosystem 💚