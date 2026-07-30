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
end
