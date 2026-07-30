require "./spec_helper"

describe BedrockLinuxGdk::Backend do
  it "builds native commands" do
    backend = BedrockLinuxGdk::Backend.new(
      BedrockLinuxGdk::Backend::Kind::Native,
      "/opt/bedrock-on-linux"
    )
    backend.command(["setup", "--mc", "1.26.33.1"]).should eq([
      "/opt/bedrock-on-linux",
      "setup",
      "--mc",
      "1.26.33.1",
    ])
  end

  it "builds Flatpak commands without hard-coding a branch" do
    backend = BedrockLinuxGdk::Backend.new(
      BedrockLinuxGdk::Backend::Kind::Flatpak,
      "/usr/bin/flatpak"
    )
    backend.command(["play"]).should eq([
      "/usr/bin/flatpak",
      "run",
      "--command=bedrock-on-linux",
      "io.github.wyze3306.BedrockOnLinux",
      "play",
    ])
  end

  it "finds an executable in PATH" do
    with_temp_dir("bedrock-backend") do |directory|
      executable = File.join(directory, "bedrock-on-linux")
      File.write(executable, "#!/bin/sh\n")
      File.chmod(executable, 0o755)
      BedrockLinuxGdk::Backend.find_executable(
        "bedrock-on-linux",
        directory
      ).should eq(executable)
    end
  end
end
