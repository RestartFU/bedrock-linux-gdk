require "./spec_helper"

describe BedrockLinuxGdk::XboxAuth do
  it "keeps private handoff files inside the selected session" do
    root = "/profiles/player-two"
    BedrockLinuxGdk::XboxAuth.oauth_path(root)
      .should eq("/profiles/player-two/auth/oauth-session")
    BedrockLinuxGdk::XboxAuth.preauth_path(root)
      .should eq("/profiles/player-two/auth/xbox-session.json")
  end

  it "seeds and replaces a per-session Wine refresh token" do
    with_temp_dir("bedrock-xbox-auth") do |root|
      prefix = File.join(root, "compatdata", "pfx")
      registry = File.join(prefix, "system.reg")
      Dir.mkdir_p(prefix)
      File.write(
        registry,
        "WINE REGISTRY Version 2\n\n" \
        "[Software\\\\Example] 1\n" \
        "\"Value\"=\"preserved\"\n"
      )

      BedrockLinuxGdk::XboxAuth.seed_refresh_token(root, "first-token")
      first = File.read(registry)
      first.should contain("\"Value\"=\"preserved\"\n")
      first.should contain("\"RefreshToken\"=\"first-token\"\n")

      BedrockLinuxGdk::XboxAuth.seed_refresh_token(root, "second-token")
      second = File.read(registry)
      second.should contain("\"RefreshToken\"=\"second-token\"\n")
      second.should_not contain("first-token")
      second.scan("\"RefreshToken\"=").size.should eq(1)
    end
  end

  it "rejects refresh tokens that could corrupt the Wine registry" do
    expect_raises(Exception, "Microsoft refresh token is invalid.") do
      BedrockLinuxGdk::XboxAuth.seed_refresh_token("/tmp/profile", "bad\nvalue")
    end
  end
end
