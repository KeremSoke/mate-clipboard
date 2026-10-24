project('mate-clipman', ['c', 'vala'],
  version: '2.0.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 0.59.0',
)

i18n = import('i18n')
gnome = import('gnome')

valac = meson.get_compiler('vala')
vapi_dir = meson.current_source_dir() / 'src' / 'vapi'
add_project_arguments('--vapidir', vapi_dir, language: 'vala')

# Dependencies
deps = [
  dependency('glib-2.0', version: '>= 2.66'),
  dependency('gobject-2.0', version: '>= 2.66'),
  dependency('gio-2.0', version: '>= 2.66'),
  dependency('gio-unix-2.0', version: '>= 2.66'),
  dependency('gtk+-3.0', version: '>= 3.22'),
  dependency('gdk-pixbuf-2.0'),
  dependency('libmatepanelapplet-4.0', version: '>= 1.20'),
  dependency('sqlite3', version: '>= 3.30'),
  dependency('libsodium', version: '>= 1.0.18'),
  dependency('libsecret-1', version: '>= 0.20'),
  valac.find_library('posix'),
]

vala_args = []

# X11: GtkClipboard, XQueryPointer and XTest for paste-on-select
x11_deps = [
  dependency('gdk-x11-3.0', required: get_option('x11')),
  dependency('x11', required: get_option('x11')),
  dependency('xtst', required: get_option('x11')),
]
have_x11 = true
foreach dep : x11_deps
  have_x11 = have_x11 and dep.found()
endforeach
if have_x11
  deps += x11_deps
  vala_args += ['-D', 'HAVE_X11']
endif

# Wayland: data-control protocols and gtk-layer-shell for the popup
wayland_deps = [
  dependency('gdk-wayland-3.0', required: get_option('wayland')),
  dependency('wayland-client', required: get_option('wayland')),
  dependency('gtk-layer-shell-0', version: '>= 0.6', required: get_option('wayland')),
]
# ext-data-control-v1 first shipped in wayland-protocols 1.39
wayland_protocols = dependency('wayland-protocols', version: '>= 1.39', required: get_option('wayland'))
wayland_scanner = find_program('wayland-scanner', required: get_option('wayland'))
have_wayland = wayland_scanner.found() and wayland_protocols.found()
foreach dep : wayland_deps
  have_wayland = have_wayland and dep.found()
endforeach
if have_wayland
  deps += wayland_deps
  vala_args += ['-D', 'HAVE_WAYLAND']
endif

if not have_x11 and not have_wayland
  error('Neither X11 nor Wayland support can be built')
endif

# Configuration
conf = configuration_data()
conf.set_quoted('PACKAGE_NAME', meson.project_name())
conf.set_quoted('PACKAGE_VERSION', meson.project_version())
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
conf.set_quoted('SCHEMA_DIR', get_option('prefix') / get_option('datadir') / 'glib-2.0' / 'schemas')

configure_file(
  output: 'config.h',
  configuration: conf
)

config_inc = include_directories('.')

# Vala's _() expands to glib/gi18n-lib.h, which needs GETTEXT_PACKAGE
# defined before anything else is included.
add_project_arguments('-include', 'config.h', language: 'c')

subdir('src')
subdir('tests')
subdir('data')
subdir('po')

gnome.post_install(glib_compile_schemas: true)
