module BedrockLinuxGdk
  class Backend
    enum Kind
      Native
      Missing
    end

    NATIVE_COMMAND = "bedrock-linux-gdk-engine"

    getter kind : Kind
    getter executable : String?

    def initialize(
      @kind : Kind,
      @executable : String? = nil,
    )
    end

    def self.detect(
      environment : Hash(String, String) = ENV.to_h,
    ) : Backend
      if override = environment["BEDROCK_LINUX_GDK_BACKEND"]?
        value = File.expand_path(override)
        return new(Kind::Native, value) if File::Info.executable?(value)
      end

      if native = find_executable(NATIVE_COMMAND, environment["PATH"]?)
        return new(Kind::Native, native)
      end

      if native = find_desktop_runtime(environment)
        return new(Kind::Native, native)
      end

      new(Kind::Missing)
    rescue File::Error
      new(Kind::Missing)
    end

    def available? : Bool
      !@kind.missing?
    end

    def label : String
      case @kind
      when .native?
        "Native backend"
      else
        "Not installed"
      end
    end

    def command(arguments : Array(String)) : Array(String)
      case @kind
      when .native?
        [@executable || NATIVE_COMMAND] + arguments
      else
        raise "GDK runtime is not installed"
      end
    end

    def self.find_executable(
      name : String,
      search_path : String?,
    ) : String?
      return if search_path.nil? || search_path.empty?

      search_path.split(':').each do |directory|
        next if directory.empty?
        candidate = File.join(directory, name)
        return candidate if File::Info.executable?(candidate)
      rescue File::Error
      end
      nil
    end

    def self.find_desktop_runtime(
      environment : Hash(String, String),
    ) : String?
      home = environment["HOME"]? || Path.home.to_s
      data_home = environment["XDG_DATA_HOME"]? ||
                  File.join(home, ".local", "share")
      directories = [
        File.join(File.expand_path(data_home, home), "applications"),
        "/usr/local/share/applications",
        "/usr/share/applications",
      ]

      directories.each do |directory|
        next unless Dir.exists?(directory)

        Dir.each_child(directory) do |entry|
          next unless entry.ends_with?(".desktop")

          contents = File.read(File.join(directory, entry))
          name = contents.each_line.find(&.starts_with?("Name="))
          next unless name

          searchable = name.downcase
          next unless searchable.includes?("bedrock") &&
                      searchable.includes?("linux")

          exec = contents.each_line.find(&.starts_with?("Exec="))
          next unless exec
          next unless exec.split(/\s+/).includes?("gui")

          command = desktop_command(exec.lchop("Exec=").strip)
          next unless command

          if command.starts_with?('/')
            return command if File::Info.executable?(command)
          elsif executable = find_executable(command, environment["PATH"]?)
            return executable
          end
        rescue File::Error
        end
      end
      nil
    end

    private def self.desktop_command(exec : String) : String?
      return if exec.empty?

      if exec.starts_with?('"')
        closing = exec.index('"', 1)
        return unless closing
        exec.byte_slice(1, closing - 1)
      else
        exec.split(/\s+/, 2).first?
      end
    end
  end
end
