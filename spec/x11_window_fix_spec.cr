require "./spec_helper"

describe BedrockLinuxGdk::X11WindowFix do
  it "crops the Wine fullscreen child to the X11 screen" do
    geometry = BedrockLinuxGdk::X11WindowFix::Geometry.new(
      -3,
      -3,
      2566_u32,
      1446_u32
    )

    correction = BedrockLinuxGdk::X11WindowFix.correction(
      2560,
      1440,
      geometry
    ).not_nil!
    correction.x.should eq(-4)
    correction.y.should eq(-30)
    correction.width.should eq(2566_u32)
    correction.height.should eq(1470_u32)
  end

  it "leaves windowed Minecraft alone" do
    geometry = BedrockLinuxGdk::X11WindowFix::Geometry.new(
      100,
      100,
      1280_u32,
      720_u32
    )

    BedrockLinuxGdk::X11WindowFix.correction(
      2560,
      1440,
      geometry
    ).should be_nil
  end

  it "builds Wine virtual desktop registry commands" do
    commands = BedrockLinuxGdk::X11WindowFix.registry_commands(2560, 1440)

    commands.size.should eq(2)
    commands[0].should contain("Desktop")
    commands[1].should contain("2560x1440")
  end

  it "matches both direct Wine and UMU Minecraft windows" do
    BedrockLinuxGdk::X11WindowFix.target_identity?(
      "minecraft.windows.exe",
      "minecraft.windows.exe",
      "Minecraft"
    ).should be_true
    BedrockLinuxGdk::X11WindowFix.target_identity?(
      "steam_app_default",
      "steam_app_default",
      "Minecraft"
    ).should be_true
    BedrockLinuxGdk::X11WindowFix.target_identity?(
      "steam_app_default",
      "steam_app_default",
      "Other game"
    ).should be_false
  end

  it "checks the configured Wine virtual desktop values" do
    with_temp_dir("x11-window-fix") do |directory|
      registry = File.join(directory, "user.reg")
      File.write(registry, <<-REGISTRY)
        [Software\\\\Wine\\\\Explorer] 1785466373
        "Desktop"="Default"

        [Software\\\\Wine\\\\Explorer\\\\Desktops] 1785466373
        "Default"="2560x1440"
        REGISTRY

      BedrockLinuxGdk::X11WindowFix.registry_configured?(
        registry,
        2560,
        1440
      ).should be_true
      BedrockLinuxGdk::X11WindowFix.registry_configured?(
        registry,
        1920,
        1080
      ).should be_false
    end
  end
end
