store_sources = files(
  'vapi/config.vapi',
  'entry.vala',
  'vault.vala',
  'store.vala',
)

applet_sources = store_sources + files(
  'clipboard/backend.vala',
  'clipboard/x11-backend.vala',
  'clipboard/wayland-backend.vala',
  'history-popup.vala',
  'preferences.vala',
  'service.vala',
  'applet.vala',
)

if have_wayland
  protocols_dir = wayland_protocols.get_variable(pkgconfig: 'pkgdatadir')
  protocols = {
    'ext-data-control-v1': protocols_dir / 'staging' / 'ext-data-control' / 'ext-data-control-v1.xml',
    'wlr-data-control-unstable-v1': meson.project_source_root() / 'protocols' / 'wlr-data-control-unstable-v1.xml',
  }
  foreach name, xml : protocols
    applet_sources += custom_target(name + '-client-header',
      input: xml,
      output: name + '-client-protocol.h',
      command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'],
    )
    applet_sources += custom_target(name + '-code',
      input: xml,
      output: name + '-protocol.c',
      command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'],
    )
  endforeach
  applet_sources += files('vapi/data-control.vapi')
endif

applet_lib = shared_module('mate-clipman-applet',
  applet_sources,
  dependencies: deps,
  include_directories: config_inc,
  vala_args: vala_args,
  c_args: ['-Wno-unused-variable', '-Wno-unused-but-set-variable', '-Wno-unused-function'],
  install: true,
  install_dir: get_option('libdir') / 'mate-panel',
)
