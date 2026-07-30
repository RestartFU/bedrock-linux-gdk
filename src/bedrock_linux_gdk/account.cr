require "json"
require "./paths"

module BedrockLinuxGdk
  record AccountState,
    signed_in : Bool,
    user_id : String?,
    gamertag : String? do
    def self.read(paths : Paths) : AccountState
      return new(false, nil, nil) unless File.file?(paths.account_file)
      account = JSON.parse(File.read(paths.account_file))
      raw_user_id = account["user_id"]?.try(&.as_s?).to_s.strip
      user_id = raw_user_id.empty? ? nil : raw_user_id
      raw_gamertag = account["gamertag"]?.try(&.as_s?).to_s.strip
      gamertag = raw_gamertag.empty? ? nil : raw_gamertag
      new(!user_id.nil?, user_id, gamertag)
    rescue JSON::ParseException | File::Error
      new(false, nil, nil)
    end
  end
end
