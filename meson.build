project('lazycat-terminal', 'vala', 'c',
  version: '0.1.0',
  meson_version: '>= 0.50.0',
)

gnome = import('gnome')

cc = meson.get_compiler('c')

dependencies = [
  dependency('gtk4'),
  dependency('vte-2.91-gtk4'),
  meson.get_compiler('vala').find_library('posix'),
  cc.find_library('m', required: true),
]

sources = files(
  'src/main.vala',
  'src/window.vala',
  'src/tab_bar.vala',
  'src/terminal_tab.vala',
)

executable('lazycat-terminal',
  sources,
  dependencies: dependencies,
  install: true,
)
