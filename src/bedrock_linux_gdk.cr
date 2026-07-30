require "./bedrock_linux_gdk/version"
require "./bedrock_linux_gdk/ui/application"

if ARGV == ["--version"]
  puts "bedrock-linux-gdk #{BedrockLinuxGdk.version_string}"
  exit 0
end

exit BedrockLinuxGdk::UI.run
