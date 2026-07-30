require "json"
require "./version"

module BedrockLinuxGdk
  module UpdateChannel
    extend self

    enum Channel
      Release
      Nightly
    end

    REPOSITORY = "RestartFU/bedrock-linux-gdk"

    def current : Channel
      BUILD_PROFILE == "nightly" ? Channel::Nightly : Channel::Release
    end

    def check_url(channel : Channel = current) : String
      if channel.nightly?
        "https://api.github.com/repos/#{REPOSITORY}/releases/tags/nightly"
      else
        "https://api.github.com/repos/#{REPOSITORY}/releases/latest"
      end
    end

    def installer_url(channel : Channel = current) : String
      if channel.nightly?
        "https://github.com/#{REPOSITORY}/releases/download/nightly/install.sh"
      else
        "https://github.com/#{REPOSITORY}/releases/latest/download/install.sh"
      end
    end

    def install_command(channel : Channel = current) : String
      release_flag = channel.release? ? " -s -- --release" : ""
      "sleep 1; curl -fsSL --proto '=https' --tlsv1.2 " \
      "#{installer_url(channel)} | sh#{release_flag}"
    end

    def latest_from_reply(
      body : String,
      channel : Channel = current,
    ) : String?
      release = JSON.parse(body).as_h?
      return unless release

      key = channel.nightly? ? "target_commitish" : "tag_name"
      release[key]?.try(&.as_s?)
    rescue JSON::ParseException
      nil
    end

    def newer?(
      latest : String?,
      channel : Channel = current,
      current_commit : String = BUILD_COMMIT,
      current_version : String = VERSION,
    ) : Bool
      return false unless latest
      return false if latest.empty?

      if channel.nightly?
        return false if current_commit.empty?
        !latest.starts_with?(current_commit)
      else
        version = latest.starts_with?("v") ? latest.lchop("v") : latest
        version != current_version
      end
    end
  end
end
