require "json"
require "file_utils"

module BedrockLinuxGdk
  record LaunchSession,
    key : String,
    name : String,
    data_dir : String,
    isolated : Bool do
    def environment(base : Hash(String, String)) : Hash(String, String)
      values = base.dup
      values["BOL_HOME"] = @data_dir if @isolated
      values
    end
  end

  class SessionStore
    getter root : String

    def initialize(
      default_data_dir : String,
      home : String = Path.home.to_s,
      environment : Hash(String, String) = ENV.to_h,
    )
      data_home = environment["XDG_DATA_HOME"]? ||
                  File.join(home, ".local", "share")
      @root = File.join(
        File.expand_path(data_home, home),
        "bedrock-linux-gdk",
        "sessions"
      )
      @default = LaunchSession.new(
        "default",
        "Default",
        default_data_dir,
        false
      )
    end

    def list : Array(LaunchSession)
      sessions = [@default]
      return sessions unless Dir.exists?(@root)

      Dir.each_child(@root) do |slug|
        directory = File.join(@root, slug)
        next unless File.directory?(directory)

        metadata = File.join(directory, "session.json")
        next unless File.file?(metadata)
        name = JSON.parse(File.read(metadata))["name"]?.try(&.as_s?)
        next unless name && !name.strip.empty?

        sessions << LaunchSession.new(slug, name, directory, true)
      rescue JSON::ParseException | File::Error
      end
      sessions.sort_by! { |session| session.name.downcase }
      default = sessions.index(&.key.==("default")).not_nil!
      sessions.unshift(sessions.delete_at(default))
      sessions
    end

    def create(name : String) : LaunchSession
      created = false
      display = name.strip
      raise ArgumentError.new("Session name is required.") if display.empty?

      slug = self.class.slug(display)
      raise ArgumentError.new(
        "Session name needs at least one letter or number."
      ) if slug.empty?

      directory = File.join(@root, slug)
      raise ArgumentError.new("Session already exists.") if Dir.exists?(directory)

      Dir.mkdir_p(directory, 0o700)
      created = true
      File.write(
        File.join(directory, "session.json"),
        {"name" => display}.to_pretty_json + "\n",
        perm: 0o600
      )
      LaunchSession.new(slug, display, directory, true)
    rescue error
      if created && directory && Dir.exists?(directory) &&
         !File.exists?(File.join(directory, "settings.json"))
        FileUtils.rm_r(directory)
      end
      raise error
    end

    def self.slug(name : String) : String
      name.downcase
        .gsub(/[^a-z0-9]+/, "-")
        .strip('-')
        .byte_slice(0, 48)
        .to_s
        .strip('-')
    end
  end
end
