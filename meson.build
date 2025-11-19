project('mate-clipman', 'c',
  version: '1.0.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 0.50.0',
  default_options: [
    'warning_level=2',
    'c_std=gnu11',
  ]
)

# Dependencies
glib_dep = dependency('glib-2.0', version: '>= 2.50')
gobject_dep = dependency('gobject-2.0', version: '>= 2.50')
gio_dep = dependency('gio-2.0', version: '>= 2.50')
gtk_dep = dependency('gtk+-3.0', version: '>= 3.22')
gdk_x11_dep = dependency('gdk-x11-3.0', version: '>= 3.22')
x11_dep = dependency('x11', version: '>= 1.6')
sqlite_dep = dependency('sqlite3', version: '>= 3.20')

# Optional MATE panel applet
mate_panel_dep = dependency('libmatepanelapplet-4.0', required: false)

# Configuration
conf = configuration_data()
conf.set_quoted('PACKAGE_NAME', meson.project_name())
conf.set_quoted('PACKAGE_VERSION', meson.project_version())
conf.set_quoted('PACKAGE_DATADIR', join_paths(get_option('prefix'), get_option('datadir'), meson.project_name()))
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set('HAVE_MATE_PANEL', mate_panel_dep.found())

config_h = configure_file(
  output: 'config.h',
  configuration: conf
)

# Include directories
inc = include_directories('.')

# Source files
clipman_sources = [
  'src/main.c',
  'src/clipman-app.c',
  'src/clipman-item.c',
  'src/clipman-manager.c',
  'src/clipman-storage.c',
  'src/clipman-history.c',
  'src/clipman-preferences.c',
]

clipman_deps = [
  glib_dep,
  gobject_dep,
  gio_dep,
  gtk_dep,
  gdk_x11_dep,
  x11_dep,
  sqlite_dep,
]

# Main executable
executable('mate-clipman',
  clipman_sources,
  dependencies: clipman_deps,
  include_directories: inc,
  install: true
)

# Panel applet (optional)
if mate_panel_dep.found()
  applet_sources = [
    'src/clipman-applet.c',
    'src/clipman-item.c',
    'src/clipman-manager.c',
    'src/clipman-storage.c',
    'src/clipman-history.c',
    'src/clipman-preferences.c',
  ]

  shared_module('mate-clipman-applet',
    applet_sources,
    dependencies: [clipman_deps, mate_panel_dep],
    include_directories: inc,
    install: true,
    install_dir: join_paths(get_option('libdir'), 'mate-panel')
  )
endif

# Data files
subdir('data')
