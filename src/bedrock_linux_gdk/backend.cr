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
        "Bundled Crystal engine"
      else
        "Not installed"
      end
    end

    def command(arguments : Array(String)) : Array(String)
      case @kind
      when .native?
        executable = @executable || NATIVE_COMMAND
        bundled_command(executable) + arguments
      else
        raise "Bedrock Linux GDK engine is not installed"
      end
    end

    private def bundled_command(executable : String) : Array(String)
      return [executable] unless executable.starts_with?('/')

      root = File.dirname(File.dirname(executable))
      loader = File.join(root, "lib", "ld-linux-x86-64.so.2")
      libraries = File.join(root, "lib")
      if File::Info.executable?(loader) && Dir.exists?(libraries)
        [loader, "--library-path", libraries, executable]
      else
        [executable]
      end
    rescue File::Error
      [executable]
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
  end
end
