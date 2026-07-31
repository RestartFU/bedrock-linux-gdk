require "./spec_helper"

describe BedrockLinuxGdk::Paths do
  it "uses native XDG storage" do
    paths = BedrockLinuxGdk::Paths.new(
      "/home/test",
      {"XDG_DATA_HOME" => "/data", "XDG_CONFIG_HOME" => "/config"}
    )
    paths.data_dir.should eq("/data/bedrock-linux-gdk")
  end

  it "uses the launcher-owned default storage" do
    paths = BedrockLinuxGdk::Paths.new(
      "/home/test",
      {} of String => String
    )
    paths.data_dir.should eq("/home/test/.local/share/bedrock-linux-gdk")
  end

  it "honors BEDROCK_LINUX_GDK_HOME" do
    paths = BedrockLinuxGdk::Paths.new(
      "/home/test",
      {"BEDROCK_LINUX_GDK_HOME" => "/games/bedrock"}
    )
    paths.data_dir.should eq("/games/bedrock")
  end

  it "shares game installs across account profiles" do
    paths = BedrockLinuxGdk::Paths.new(
      "/home/test",
      {
        "BEDROCK_LINUX_GDK_HOME"        => "/profiles/player-two",
        "BEDROCK_LINUX_GDK_SHARED_HOME" => "/games/bedrock",
      }
    )
    paths.data_dir.should eq("/profiles/player-two")
    paths.games_dir.should eq("/games/bedrock/games")
  end

  it "resolves account-owned Minecraft data" do
    paths = BedrockLinuxGdk::Paths.new(
      "/home/test",
      {"BEDROCK_LINUX_GDK_HOME" => "/profiles/creeper"}
    )
    paths.game_data_dir.should eq(
      "/profiles/creeper/compatdata/pfx/drive_c/users/steamuser/" \
      "AppData/Roaming/Minecraft Bedrock/Users/Shared/games/com.mojang"
    )
  end

  it "prefers Minecraft's existing account data directory" do
    with_temp_dir("bedrock-game-data") do |home|
      profile = File.join(home, "profile")
      game_data = File.join(
        profile,
        "compatdata/pfx/drive_c/users/steamuser/AppData/Roaming/" \
        "Minecraft Bedrock/Users/8675309/games/com.mojang"
      )
      Dir.mkdir_p(game_data)
      paths = BedrockLinuxGdk::Paths.new(
        home,
        {"BEDROCK_LINUX_GDK_HOME" => profile}
      )
      paths.game_data_dir.should eq(game_data)
    end
  end
end
