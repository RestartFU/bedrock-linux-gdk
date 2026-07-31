require "./spec_helper"

describe BedrockLinuxGdk::GraphicsDefaults do
  it "caps an excessive first-run render distance once" do
    with_temp_dir("bedrock-graphics") do |root|
      options = File.join(
        root,
        "compatdata/pfx/drive_c/users/steamuser/AppData/Roaming",
        "Minecraft Bedrock/Users/123/games/com.mojang/minecraftpe/options.txt"
      )
      Dir.mkdir_p(File.dirname(options))
      File.write(options, "gfx_viewdistance:800\ngfx_vsync:1\n")

      BedrockLinuxGdk::GraphicsDefaults.apply(root).should be_true
      File.read(options).should eq("gfx_viewdistance:256\ngfx_vsync:1\n")

      File.write(options, "gfx_viewdistance:800\n")
      BedrockLinuxGdk::GraphicsDefaults.apply(root).should be_false
      File.read(options).should eq("gfx_viewdistance:800\n")
    end
  end

  it "leaves sane render distance unchanged" do
    with_temp_dir("bedrock-graphics") do |root|
      options = File.join(
        root,
        "compatdata/pfx/drive_c/users/steamuser/AppData/Roaming",
        "Minecraft Bedrock/Users/123/games/com.mojang/minecraftpe/options.txt"
      )
      Dir.mkdir_p(File.dirname(options))
      File.write(options, "gfx_viewdistance:128\n")

      BedrockLinuxGdk::GraphicsDefaults.apply(root).should be_false
      File.read(options).should eq("gfx_viewdistance:128\n")
    end
  end
end
