require "json"
require "./paths"

module BedrockLinuxGdk
  record AccountState, signed_in : Bool, gamertag : String? do
    def self.read(paths : Paths) : AccountState
      return new(false, nil) unless File.file?(paths.account_file)
      account = JSON.parse(File.read(paths.account_file))
      user_id = account["user_id"]?.try(&.as_s?).to_s
      raw_gamertag = account["gamertag"]?.try(&.as_s?).to_s.strip
      gamertag = raw_gamertag.empty? ? nil : raw_gamertag
      new(!user_id.empty?, gamertag)
    rescue JSON::ParseException | File::Error
      new(false, nil)
    end
  end
end
