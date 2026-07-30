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
end
