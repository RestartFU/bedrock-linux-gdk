require "./spec_helper"

describe BedrockLinuxGdk::UpdateChannel do
  it "reads release tags" do
    body = %({"tag_name":"v0.2.0","target_commitish":"main"})
    latest = BedrockLinuxGdk::UpdateChannel.latest_from_reply(
      body,
      BedrockLinuxGdk::UpdateChannel::Channel::Release
    )
    latest.should eq("v0.2.0")
  end

  it "reads nightly commit targets" do
    body = %({"tag_name":"nightly","target_commitish":"abcdef123456"})
    latest = BedrockLinuxGdk::UpdateChannel.latest_from_reply(
      body,
      BedrockLinuxGdk::UpdateChannel::Channel::Nightly
    )
    latest.should eq("abcdef123456")
  end

  it "compares nightly commits by prefix" do
    channel = BedrockLinuxGdk::UpdateChannel::Channel::Nightly
    BedrockLinuxGdk::UpdateChannel.newer?(
      "abcdef123456",
      channel,
      current_commit: "abcdef1"
    ).should be_false
    BedrockLinuxGdk::UpdateChannel.newer?(
      "987654321",
      channel,
      current_commit: "abcdef1"
    ).should be_true
  end
end
