module BedrockLinuxGdk
  class Paths
    FLATPAK_APP_ID = "io.github.wyze3306.BedrockOnLinux"

    getter home : String
    getter flatpak : Bool

    def initialize(
      @home : String = Path.home.to_s,
      @flatpak : Bool = false,
      @environment : Hash(String, String) = ENV.to_h,
    )
    end

    def data_dir : String
      if override = @environment["BOL_HOME"]?
        clean = override.strip
        return File.expand_path(clean, @home) unless clean.empty?
      end

      if pointer = install_location
        return pointer
      end

      if @flatpak
        File.join(
          @home,
          ".var",
          "app",
          FLATPAK_APP_ID,
          "data",
          "bedrock-on-linux"
        )
      else
        data_home = @environment["XDG_DATA_HOME"]? ||
                    File.join(@home, ".local", "share")
        File.join(File.expand_path(data_home, @home), "bedrock-on-linux")
      end
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

    def install_location_file : String
      config_home = if @flatpak
                      File.join(
                        @home,
                        ".var",
                        "app",
                        FLATPAK_APP_ID,
                        "config"
                      )
                    else
                      @environment["XDG_CONFIG_HOME"]? ||
                        File.join(@home, ".config")
                    end
      File.join(
        File.expand_path(config_home, @home),
        "bedrock-on-linux",
        "install_location"
      )
    end

    private def install_location : String?
      path = install_location_file
      return unless File.file?(path)

      value = File.read(path).strip
      return if value.empty?
      File.expand_path(value, @home)
    rescue File::Error
      nil
    end
  end
end
