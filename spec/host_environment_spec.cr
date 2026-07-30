require "./spec_helper"

describe BedrockLinuxGdk::HostEnvironment do
  it "isolates backend processes from bundled GTK and adds bundled Python" do
    with_temp_dir("bedrock-host-environment") do |root|
      executable = File.join(root, "bin", "bedrock-linux-gdk")
      python = File.join(root, "share", "bedrock-linux-gdk", "python")
      Dir.mkdir_p(File.dirname(executable))
      Dir.mkdir_p(python)

      environment = BedrockLinuxGdk::HostEnvironment.values(
        {
          "GIO_EXTRA_MODULES"          => "/nix/store/incompatible",
          "GI_TYPELIB_PATH"            => "/nix/store/incompatible",
          "GTK_PATH"                   => "/nix/store/incompatible",
          "BEDROCK_HOST_XDG_DATA_DIRS" => "/host/share",
          "PYTHONPATH"                 => "/existing/python",
        },
        executable
      )

      environment["XDG_DATA_DIRS"].should eq("/host/share")
      environment["PYTHONPATH"].should eq("#{python}:/existing/python")
      environment.has_key?("GIO_EXTRA_MODULES").should be_false
      environment.has_key?("GI_TYPELIB_PATH").should be_false
      environment.has_key?("GTK_PATH").should be_false
    end
  end
end
