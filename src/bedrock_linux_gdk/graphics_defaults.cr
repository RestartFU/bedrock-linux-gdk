module BedrockLinuxGdk
  module GraphicsDefaults
    extend self

    MAX_SAFE_VIEW_DISTANCE = 512
    LAPTOP_VIEW_DISTANCE   = 256
    MARKER                 = ".graphics-defaults-v1"

    def apply(root : String) : Bool
      marker = File.join(root, MARKER)
      return false if File.file?(marker)

      options = Dir.glob(File.join(
        root,
        "compatdata",
        "pfx",
        "drive_c",
        "users",
        "steamuser",
        "AppData",
        "Roaming",
        "Minecraft Bedrock",
        "Users",
        "*",
        "games",
        "com.mojang",
        "minecraftpe",
        "options.txt"
      ))
      return false if options.empty?

      changed = false
      options.each do |path|
        changed = cap_view_distance(path) || changed
      end
      File.write(marker, "#{Time.utc}\n", perm: 0o600)
      changed
    end

    private def cap_view_distance(path : String) : Bool
      temporary = nil.as(String?)
      content = File.read(path)
      changed = false
      lines = content.lines(chomp: false).map do |line|
        value = line.rstrip.match(/\Agfx_viewdistance:(\d+)\z/)
        unless value && value[1].to_i > MAX_SAFE_VIEW_DISTANCE
          next line
        end

        changed = true
        ending = if line.ends_with?("\r\n")
                   "\r\n"
                 elsif line.ends_with?('\n')
                   "\n"
                 else
                   ""
                 end
        "gfx_viewdistance:#{LAPTOP_VIEW_DISTANCE}#{ending}"
      end
      return false unless changed

      temporary = "#{path}.bedrock-linux-gdk"
      File.write(temporary, lines.join, perm: 0o600)
      File.rename(temporary, path)
      true
    ensure
      File.delete(temporary) if temporary && File.exists?(temporary)
    end
  end
end
