require "./spec_helper"

describe BedrockLinuxGdk::Paths do
  it "uses native XDG storage" do
    paths = BedrockLinuxGdk::Paths.new(
      "/home/test",
      false,
      {"XDG_DATA_HOME" => "/data", "XDG_CONFIG_HOME" => "/config"}
    )
    paths.data_dir.should eq("/data/bedrock-on-linux")
    paths.install_location_file.should eq(
      "/config/bedrock-on-linux/install_location"
    )
  end

  it "uses Flatpak private XDG storage" do
    paths = BedrockLinuxGdk::Paths.new("/home/test", true, {} of String => String)
    paths.data_dir.should eq(
      "/home/test/.var/app/io.github.wyze3306.BedrockOnLinux/data/" \
      "bedrock-on-linux"
    )
  end

  it "honors BOL_HOME" do
    paths = BedrockLinuxGdk::Paths.new(
      "/home/test",
      false,
      {"BOL_HOME" => "/games/bedrock"}
    )
    paths.data_dir.should eq("/games/bedrock")
  end
end
