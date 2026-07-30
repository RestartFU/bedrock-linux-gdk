require "./spec_helper"

describe BedrockLinuxGdk::HostEnvironment do
  it "isolates backend processes from bundled GTK and finds system UMU" do
    with_temp_dir("bedrock-host-environment") do |root|
      executable = File.join(root, "bin", "bedrock-linux-gdk")
      tools = File.join(root, "tools")
      umu = File.join(tools, "umu-run")
      Dir.mkdir_p(File.dirname(executable))
      Dir.mkdir_p(tools)
      File.write(umu, "#!/bin/sh\n", perm: 0o755)

      environment = BedrockLinuxGdk::HostEnvironment.values(
        {
          "GIO_EXTRA_MODULES"          => "/nix/store/incompatible",
          "GI_TYPELIB_PATH"            => "/nix/store/incompatible",
          "GTK_PATH"                   => "/nix/store/incompatible",
          "BEDROCK_HOST_XDG_DATA_DIRS" => "/host/share",
          "PATH"                       => tools,
        },
        executable
      )

      environment["XDG_DATA_DIRS"].should eq("/host/share")
      environment["BEDROCK_LINUX_GDK_UMU"].should eq(umu)
      environment.has_key?("GIO_EXTRA_MODULES").should be_false
      environment.has_key?("GI_TYPELIB_PATH").should be_false
      environment.has_key?("GTK_PATH").should be_false
    end
  end
end
