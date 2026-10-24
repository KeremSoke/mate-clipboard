# Store and vault round trip, using a throwaway key and directory.
test_store = executable('test-store',
  store_sources + files('test-store.vala'),
  dependencies: deps,
  include_directories: config_inc,
  c_args: ['-Wno-unused-variable', '-Wno-unused-but-set-variable'],
)
test('store', test_store, env: ['TMPDIR=' + meson.current_build_dir()])
