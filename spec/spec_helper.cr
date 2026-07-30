require "spec"
require "file_utils"
require "random/secure"
require "../src/bedrock_linux_gdk/account"
require "../src/bedrock_linux_gdk/backend"
require "../src/bedrock_linux_gdk/host_environment"
require "../src/bedrock_linux_gdk/launch_session"
require "../src/bedrock_linux_gdk/paths"
require "../src/bedrock_linux_gdk/settings"
require "../src/bedrock_linux_gdk/update_channel"
require "../src/bedrock_linux_gdk/version_entry"

def with_temp_dir(prefix : String, & : String ->) : Nil
  directory = File.join(
    Dir.tempdir,
    "#{prefix}-#{Random::Secure.hex(8)}"
  )
  Dir.mkdir_p(directory)
  begin
    yield directory
  ensure
    FileUtils.rm_r(directory) if Dir.exists?(directory)
  end
end
