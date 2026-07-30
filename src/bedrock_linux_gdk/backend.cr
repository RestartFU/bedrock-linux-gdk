module BedrockLinuxGdk
  class Backend
    enum Kind
      Native
      Flatpak
      Missing
    end

    FLATPAK_APP_ID = "io.github.wyze3306.BedrockOnLinux"

    getter kind : Kind
    getter executable : String?

    def initialize(@kind : Kind, @executable : String? = nil)
    end

    def self.detect(
      environment : Hash(String, String) = ENV.to_h,
      probe_flatpak : Bool = true,
    ) : Backend
      if override = environment["BEDROCK_LINUX_GDK_BACKEND"]?
        value = File.expand_path(override)
        return new(Kind::Native, value) if File::Info.executable?(value)
      end

      if native = find_executable("bedrock-on-linux", environment["PATH"]?)
        return new(Kind::Native, native)
      end

      if flatpak = find_executable("flatpak", environment["PATH"]?)
        if !probe_flatpak || flatpak_installed?(flatpak)
          return new(Kind::Flatpak, flatpak)
        end
      end

      new(Kind::Missing)
    rescue File::Error
      new(Kind::Missing)
    end

    def available? : Bool
      !@kind.missing?
    end

    def flatpak? : Bool
      @kind.flatpak?
    end

    def label : String
      case @kind
      when .native?
        @executable || "bedrock-on-linux"
      when .flatpak?
        "Flatpak · #{FLATPAK_APP_ID}"
      else
        "Not installed"
      end
    end

    def command(arguments : Array(String)) : Array(String)
      case @kind
      when .native?
        [@executable || "bedrock-on-linux"] + arguments
      when .flatpak?
        [
          @executable || "flatpak",
          "run",
          "--command=bedrock-on-linux",
          FLATPAK_APP_ID,
        ] + arguments
      else
        raise "BedrockOnLinux backend is not installed"
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

    private def self.flatpak_installed?(flatpak : String) : Bool
      Process.run(
        flatpak,
        ["info", FLATPAK_APP_ID],
        input: Process::Redirect::Close,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      ).success?
    rescue File::Error | IO::Error
      false
    end
  end
end
