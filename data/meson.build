# GSettings schema
install_data('org.mate.clipman.gschema.xml',
  install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas')
)

# Desktop file
desktop_conf = configuration_data()
desktop_conf.set('bindir', join_paths(get_option('prefix'), get_option('bindir')))

configure_file(
  input: 'mate-clipman.desktop.in',
  output: 'mate-clipman.desktop',
  configuration: desktop_conf,
  install: true,
  install_dir: join_paths(get_option('datadir'), 'applications')
)

# Autostart desktop file
configure_file(
  input: 'mate-clipman-autostart.desktop.in',
  output: 'mate-clipman-autostart.desktop',
  configuration: desktop_conf,
  install: true,
  install_dir: join_paths(get_option('sysconfdir'), 'xdg', 'autostart')
)

# Panel applet files (if building with MATE panel support)
if mate_panel_dep.found()
  applet_conf = configuration_data()
  applet_conf.set('LIBDIR', join_paths(get_option('prefix'), get_option('libdir')))

  configure_file(
    input: 'org.mate.panel.ClipmanApplet.mate-panel-applet.in',
    output: 'org.mate.panel.ClipmanApplet.mate-panel-applet',
    configuration: applet_conf,
    install: true,
    install_dir: join_paths(get_option('datadir'), 'mate-panel', 'applets')
  )

  configure_file(
    input: 'org.mate.panel.applet.ClipmanAppletFactory.service.in',
    output: 'org.mate.panel.applet.ClipmanAppletFactory.service',
    configuration: applet_conf,
    install: true,
    install_dir: join_paths(get_option('datadir'), 'dbus-1', 'services')
  )
endif
