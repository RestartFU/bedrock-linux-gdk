require "json"
require "file_utils"
require "random/secure"

module BedrockLinuxGdk
  record LaunchSession,
    key : String,
    name : String,
    data_dir : String,
    shared_dir : String,
    isolated : Bool do
    def environment(base : Hash(String, String)) : Hash(String, String)
      values = base.dup
      values["BEDROCK_LINUX_GDK_SHARED_HOME"] = @shared_dir
      if @isolated
        values["BEDROCK_LINUX_GDK_HOME"] = @data_dir
      end
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
        default_data_dir,
        true
      )
    end

    def list : Array(LaunchSession)
      sessions = [default_session]
      return sessions unless Dir.exists?(@root)

      Dir.each_child(@root) do |slug|
        directory = File.join(@root, slug)
        next unless File.directory?(directory)

        metadata = File.join(directory, "session.json")
        next unless File.file?(metadata)
        name = JSON.parse(File.read(metadata))["name"]?.try(&.as_s?)
        next unless name && !name.strip.empty?

        sessions << LaunchSession.new(
          slug,
          name,
          directory,
          @default.shared_dir,
          true
        )
      rescue JSON::ParseException | File::Error
      end
      sessions.sort_by! { |session| session.name.downcase }
      default = sessions.index(&.key.==("default")).not_nil!
      sessions.unshift(sessions.delete_at(default))
      sessions
    end

    def create_pending : LaunchSession
      loop do
        key = "account-#{Random::Secure.hex(6)}"
        next if Dir.exists?(File.join(@root, key))
        return create_with_key(key, "Signing in…")
      end
    end

    def create(name : String) : LaunchSession
      display = name.strip
      raise ArgumentError.new("Account name is required.") if display.empty?

      slug = self.class.slug(display)
      raise ArgumentError.new(
        "Account name needs at least one letter or number."
      ) if slug.empty?

      create_with_key(slug, display)
    end

    def rename(session : LaunchSession, name : String) : LaunchSession
      display = name.strip
      raise ArgumentError.new("Account name is required.") if display.empty?
      metadata = metadata_path(session)
      Dir.mkdir_p(File.dirname(metadata), 0o700)
      File.write(
        metadata,
        {"name" => display}.to_pretty_json + "\n",
        perm: 0o600
      )
      LaunchSession.new(
        session.key,
        display,
        session.data_dir,
        session.shared_dir,
        session.isolated
      )
    end

    def delete_pending(session : LaunchSession) : Nil
      raise ArgumentError.new("Default account cannot be removed.") if session.key == "default"
      expected = File.join(@root, session.key)
      raise ArgumentError.new("Invalid account profile path.") unless session.data_dir == expected
      raise ArgumentError.new("Invalid account profile key.") unless session.key.starts_with?("account-")

      FileUtils.rm_r(expected) if Dir.exists?(expected)
    end

    private def default_session : LaunchSession
      metadata = metadata_path(@default)
      return @default unless File.file?(metadata)

      name = JSON.parse(File.read(metadata))["name"]?.try(&.as_s?).to_s.strip
      return @default if name.empty?
      LaunchSession.new(
        @default.key,
        name,
        @default.data_dir,
        @default.shared_dir,
        @default.isolated
      )
    rescue JSON::ParseException | File::Error
      @default
    end

    private def metadata_path(session : LaunchSession) : String
      File.join(session.data_dir, "session.json")
    end

    private def create_with_key(key : String, display : String) : LaunchSession
      created = false
      directory = File.join(@root, key)
      raise ArgumentError.new("Account profile already exists.") if Dir.exists?(directory)

      Dir.mkdir_p(directory, 0o700)
      created = true
      File.write(
        File.join(directory, "session.json"),
        {"name" => display}.to_pretty_json + "\n",
        perm: 0o600
      )
      LaunchSession.new(
        key,
        display,
        directory,
        @default.shared_dir,
        true
      )
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
