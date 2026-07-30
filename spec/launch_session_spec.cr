require "./spec_helper"

describe BedrockLinuxGdk::SessionStore do
  it "lists default session first" do
    with_temp_dir("bedrock-sessions") do |home|
      store = BedrockLinuxGdk::SessionStore.new(
        File.join(home, "bedrock"),
        home
      )
      sessions = store.list
      sessions.size.should eq(1)
      sessions.first.key.should eq("default")
      sessions.first.isolated.should be_true
      sessions.first.environment(
        {} of String => String
      )["BEDROCK_LINUX_GDK_HOME"]
        .should eq(sessions.first.data_dir)
    end
  end

  it "creates independent launch roots" do
    with_temp_dir("bedrock-sessions") do |home|
      store = BedrockLinuxGdk::SessionStore.new(
        File.join(home, "bedrock"),
        home
      )
      created = store.create("Player Two")
      created.key.should eq("player-two")
      created.isolated.should be_true
      File.file?(File.join(created.data_dir, "session.json")).should be_true
      created.environment(
        {} of String => String
      )["BEDROCK_LINUX_GDK_HOME"]
        .should eq(created.data_dir)
    end
  end

  it "refuses duplicate session roots" do
    with_temp_dir("bedrock-sessions") do |home|
      store = BedrockLinuxGdk::SessionStore.new(
        File.join(home, "bedrock"),
        home
      )
      store.create("Player Two")
      expect_raises(ArgumentError, "Session already exists.") do
        store.create("player two")
      end
      store.list.map(&.key).should contain("player-two")
    end
  end
end
