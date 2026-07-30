project(
  'bedrock-linux-gdk',
  'c',
  version: '0.1.0',
  license: 'MIT',
  meson_version: '>=1.0.0',
)

crystal = find_program('crystal')
shards = find_program('shards')

run_command(shards, 'install', '--production', check: true)

sources = files(
  'src/bedrock_linux_gdk.cr',
  'src/bedrock_linux_gdk/account.cr',
  'src/bedrock_linux_gdk/backend.cr',
  'src/bedrock_linux_gdk/host_environment.cr',
  'src/bedrock_linux_gdk/launch_session.cr',
  'src/bedrock_linux_gdk/paths.cr',
  'src/bedrock_linux_gdk/process_job.cr',
  'src/bedrock_linux_gdk/settings.cr',
  'src/bedrock_linux_gdk/update_channel.cr',
  'src/bedrock_linux_gdk/version.cr',
  'src/bedrock_linux_gdk/version_entry.cr',
  'src/bedrock_linux_gdk/ui/adw.cr',
  'src/bedrock_linux_gdk/ui/application.cr',
  'src/bedrock_linux_gdk/ui/dialogs.cr',
  'src/bedrock_linux_gdk/ui/style.cr',
  'src/bedrock_linux_gdk/ui/updater.cr',
  'src/bedrock_linux_gdk/ui/window.cr',
)

app = custom_target(
  'bedrock-linux-gdk',
  input: sources,
  output: 'bedrock-linux-gdk',
  command: [
    crystal,
    'build',
    '@INPUT0@',
    '--release',
    '--no-debug',
    '-o',
    '@OUTPUT@',
  ],
  build_by_default: true,
  install: true,
  install_dir: get_option('bindir'),
)

install_data(
  'data/com.restartfu.BedrockLinuxGdk.desktop',
  install_dir: get_option('datadir') / 'applications',
)
install_data(
  'data/com.restartfu.BedrockLinuxGdk.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo',
)
install_data(
  'data/icons/hicolor/512x512/apps/com.restartfu.BedrockLinuxGdk.png',
  install_dir: get_option('datadir') / 'icons/hicolor/512x512/apps',
)
