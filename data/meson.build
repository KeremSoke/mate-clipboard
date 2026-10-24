# GSettings schema
install_data('org.mate.clipman.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

# Panel applet description, loaded in-process by mate-panel
applet_conf = configuration_data()
applet_conf.set('LIBDIR', get_option('prefix') / get_option('libdir'))

applet_keyfile_in = configure_file(
  input: 'org.mate.panel.ClipmanApplet.mate-panel-applet.desktop.in',
  output: 'org.mate.panel.ClipmanApplet.mate-panel-applet.in',
  configuration: applet_conf
)

i18n.merge_file(
  input: applet_keyfile_in,
  output: 'org.mate.panel.ClipmanApplet.mate-panel-applet',
  po_dir: meson.project_source_root() / 'po',
  install: true,
  install_dir: get_option('datadir') / 'mate-panel' / 'applets',
  type: 'desktop'
)
