require "json"
require "./paths"

module BedrockLinuxGdk
  record AccountState, signed_in : Bool, gamertag : String? do
    def self.read(paths : Paths) : AccountState
      signed_in = token_present?(paths.token_file)
      gamertag = signed_in ? read_gamertag(paths.device_file) : nil
      new(signed_in, gamertag)
    end

    private def self.token_present?(path : String) : Bool
      return false unless File.file?(path)
      token = JSON.parse(File.read(path))
      !token["refresh_token"]?.try(&.as_s?).to_s.empty?
    rescue JSON::ParseException | File::Error
      false
    end

    private def self.read_gamertag(path : String) : String?
      return unless File.file?(path)
      JSON.parse(File.read(path))["xbl_gamertag"]?.try(&.as_s?)
    rescue JSON::ParseException | File::Error
      nil
    end
  end
end
