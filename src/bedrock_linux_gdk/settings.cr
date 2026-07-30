require "json"
require "./paths"

module BedrockLinuxGdk
  class Settings
    getter path : String

    @values : Hash(String, JSON::Any)

    def initialize(@path : String)
      @values = load_values
    end

    def self.for(paths : Paths) : Settings
      new(paths.settings_file)
    end

    def reload : Nil
      @values = load_values
    end

    def [](key : String) : JSON::Any?
      @values[key]?
    end

    def string(key : String, fallback : String = "") : String
      @values[key]?.try(&.as_s?) || fallback
    end

    def bool(key : String, fallback : Bool = false) : Bool
      @values[key]?.try(&.as_bool?) || fallback
    end

    def set(key : String, value : String) : Nil
      @values[key] = JSON::Any.new(value)
      save
    end

    def set(key : String, value : Bool) : Nil
      @values[key] = JSON::Any.new(value)
      save
    end

    def delete(key : String) : Nil
      @values.delete(key)
      save
    end

    def to_h : Hash(String, JSON::Any)
      @values.dup
    end

    def save : Nil
      directory = File.dirname(@path)
      Dir.mkdir_p(directory, 0o700)
      temporary = File.join(
        directory,
        ".settings-#{Process.pid}-#{Random.rand(UInt32)}.tmp"
      )

      File.open(temporary, "w", 0o600) do |file|
        @values.to_pretty_json(file)
        file << '\n'
        file.flush
      end
      File.chmod(temporary, 0o600)
      File.rename(temporary, @path)
    ensure
      if temporary && File.exists?(temporary)
        File.delete(temporary)
      end
    end

    private def load_values : Hash(String, JSON::Any)
      return {} of String => JSON::Any unless File.file?(@path)

      JSON.parse(File.read(@path)).as_h
    rescue JSON::ParseException | File::Error
      {} of String => JSON::Any
    end
  end
end
