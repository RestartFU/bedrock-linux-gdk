module BedrockLinuxGdk
  VERSION = "0.1.2"

  BUILD_PROFILE = {{ env("BEDROCK_BUILD_PROFILE") || "default" }}
  BUILD_COMMIT  = {{ env("BEDROCK_BUILD_COMMIT") || "" }}

  {% if (env("BEDROCK_BUILD_PROFILE") || "default") == "nightly" %}
    APP_ID       = "com.restartfu.BedrockLinuxGdk.Nightly"
    APP_NAME     = "Bedrock Linux GDK (Nightly)"
    INSTALL_NAME = "bedrock-linux-gdk-nightly"
  {% else %}
    APP_ID       = "com.restartfu.BedrockLinuxGdk"
    APP_NAME     = "Bedrock Linux GDK"
    INSTALL_NAME = "bedrock-linux-gdk"
  {% end %}

  def self.version_string : String
    String.build do |value|
      value << VERSION
      value << "-nightly" if BUILD_PROFILE == "nightly"
      value << " (" << BUILD_COMMIT << ")" unless BUILD_COMMIT.empty?
    end
  end
end
