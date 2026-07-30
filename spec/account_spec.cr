require "./spec_helper"

describe BedrockLinuxGdk::AccountState do
  it "reads launcher account metadata" do
    with_temp_dir("bedrock-account") do |home|
      paths = BedrockLinuxGdk::Paths.new(
        home,
        {"BEDROCK_LINUX_GDK_HOME" => File.join(home, "profile")}
      )
      Dir.mkdir_p(paths.data_dir)
      File.write(
        paths.account_file,
        %({"user_id":"281474976710655","gamertag":"Creeper"})
      )

      account = BedrockLinuxGdk::AccountState.read(paths)
      account.signed_in.should be_true
      account.gamertag.should eq("Creeper")
    end
  end

  it "rejects incomplete account metadata" do
    with_temp_dir("bedrock-account") do |home|
      paths = BedrockLinuxGdk::Paths.new(
        home,
        {"BEDROCK_LINUX_GDK_HOME" => File.join(home, "profile")}
      )
      Dir.mkdir_p(paths.data_dir)
      File.write(paths.account_file, %({"gamertag":"Creeper"}))

      BedrockLinuxGdk::AccountState.read(paths).signed_in.should be_false
    end
  end
end
