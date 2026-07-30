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
      sessions.first.environment(
        {} of String => String
      )["BEDROCK_LINUX_GDK_SHARED_HOME"]
        .should eq(File.join(home, "bedrock"))
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
      created.environment(
        {} of String => String
      )["BEDROCK_LINUX_GDK_SHARED_HOME"]
        .should eq(File.join(home, "bedrock"))
    end
  end

  it "refuses duplicate session roots" do
    with_temp_dir("bedrock-sessions") do |home|
      store = BedrockLinuxGdk::SessionStore.new(
        File.join(home, "bedrock"),
        home
      )
      store.create("Player Two")
      expect_raises(ArgumentError, "Account profile already exists.") do
        store.create("player two")
      end
      store.list.map(&.key).should contain("player-two")
    end
  end

  it "creates and names account profiles after sign-in" do
    with_temp_dir("bedrock-sessions") do |home|
      store = BedrockLinuxGdk::SessionStore.new(
        File.join(home, "bedrock"),
        home
      )
      pending = store.create_pending
      pending.key.should start_with("account-")
      pending.name.should eq("Signing in…")

      store.rename(pending, "Creeper")
      account = store.list.find(&.key.==(pending.key)).not_nil!
      account.name.should eq("Creeper")
    end
  end

  it "removes only temporary account profiles" do
    with_temp_dir("bedrock-sessions") do |home|
      store = BedrockLinuxGdk::SessionStore.new(
        File.join(home, "bedrock"),
        home
      )
      pending = store.create_pending
      store.delete_pending(pending)
      Dir.exists?(pending.data_dir).should be_false

      regular = store.create("Creeper")
      expect_raises(ArgumentError, "Invalid account profile key.") do
        store.delete_pending(regular)
      end
      Dir.exists?(regular.data_dir).should be_true
    end
  end
end
