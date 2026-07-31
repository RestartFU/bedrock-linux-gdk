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

    def shared_dir : String
      if override = @environment["BEDROCK_LINUX_GDK_SHARED_HOME"]?
        clean = override.strip
        return File.expand_path(clean, @home) unless clean.empty?
      end
      data_dir
    end

    def account_file : String
      File.join(data_dir, "account.json")
    end

    def games_dir : String
      File.join(shared_dir, "games")
    end

    def logs_dir : String
      File.join(data_dir, "logs")
    end

    def game_data_dir : String
      users = File.join(
        data_dir,
        "compatdata",
        "pfx",
        "drive_c",
        "users",
        "steamuser",
        "AppData",
        "Roaming",
        "Minecraft Bedrock",
        "Users"
      )
      if Dir.exists?(users)
        Dir.each_child(users) do |name|
          next if name == "Shared"
          candidate = File.join(users, name, "games", "com.mojang")
          return candidate if Dir.exists?(candidate)
        end
      end

      File.join(users, "Shared", "games", "com.mojang")
    rescue File::Error
      File.join(
        data_dir,
        "compatdata",
        "pfx",
        "drive_c",
        "users",
        "steamuser",
        "AppData",
        "Roaming",
        "Minecraft Bedrock",
        "Users",
        "Shared",
        "games",
        "com.mojang"
      )
    end
  end
end
