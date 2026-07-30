require "./spec_helper"

describe BedrockLinuxGdk::Backend do
  it "builds native commands" do
    backend = BedrockLinuxGdk::Backend.new(
      BedrockLinuxGdk::Backend::Kind::Native,
      "/opt/bedrock-linux-gdk-engine"
    )
    backend.command(["setup", "--mc", "1.26.33.1"]).should eq([
      "/opt/bedrock-linux-gdk-engine",
      "setup",
      "--mc",
      "1.26.33.1",
    ])
  end

  it "finds an executable in PATH" do
    with_temp_dir("bedrock-backend") do |directory|
      executable = File.join(directory, "bedrock-linux-gdk-engine")
      File.write(executable, "#!/bin/sh\n")
      File.chmod(executable, 0o755)
      BedrockLinuxGdk::Backend.find_executable(
        "bedrock-linux-gdk-engine",
        directory
      ).should eq(executable)
    end
  end

  it "discovers a compatible native runtime from its desktop entry" do
    with_temp_dir("bedrock-runtime") do |home|
      executable = File.join(home, "runtime")
      applications = File.join(home, ".local", "share", "applications")
      Dir.mkdir_p(applications)
      File.write(executable, "#!/bin/sh\n")
      File.chmod(executable, 0o755)
      File.write(
        File.join(applications, "runtime.desktop"),
        "[Desktop Entry]\n" \
        "Name=Bedrock Linux Runtime\n" \
        "Exec=#{executable} gui\n"
      )

      BedrockLinuxGdk::Backend.find_desktop_runtime({
        "HOME" => home,
        "PATH" => home,
      }).should eq(executable)
    end
  end
end
