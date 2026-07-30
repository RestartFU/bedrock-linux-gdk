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

  it "runs the bundled engine through its shipped loader" do
    with_temp_dir("bedrock-bundle") do |root|
      executable = File.join(root, "bin", "bedrock-linux-gdk-engine")
      loader = File.join(root, "lib", "ld-linux-x86-64.so.2")
      Dir.mkdir_p(File.dirname(executable))
      Dir.mkdir_p(File.dirname(loader))
      File.write(executable, "#!/bin/sh\n", perm: 0o755)
      File.write(loader, "#!/bin/sh\n", perm: 0o755)

      backend = BedrockLinuxGdk::Backend.new(
        BedrockLinuxGdk::Backend::Kind::Native,
        executable
      )
      backend.command(["doctor"]).should eq([
        loader,
        "--library-path",
        File.join(root, "lib"),
        executable,
        "doctor",
      ])
    end
  end
end
