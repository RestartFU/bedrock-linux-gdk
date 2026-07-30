module BedrockLinuxGdk
  class Paths
    DATA_DIRECTORY = "bedrock-linux-gdk"

    getter home : String

    def initialize(
      @home : String = Path.home.to_s,
      @environment : Hash(String, String) = ENV.to_h,
    )
    end

    def data_dir : String
      if override = @environment["BEDROCK_LINUX_GDK_HOME"]?
        clean = override.strip
        return File.expand_path(clean, @home) unless clean.empty?
      end

      data_home = @environment["XDG_DATA_HOME"]? ||
                  File.join(@home, ".local", "share")
      File.join(File.expand_path(data_home, @home), DATA_DIRECTORY)
    end

    def settings_file : String
      File.join(data_dir, "settings.json")
    end

    def token_file : String
      File.join(data_dir, "msa", "token.json")
    end

    def device_file : String
      File.join(data_dir, "winegdk-preauth", "device.json")
    end

    def games_dir : String
      File.join(data_dir, "games")
    end

    def logs_dir : String
      File.join(data_dir, "logs")
    end
  end
end
