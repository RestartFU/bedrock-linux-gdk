require "./spec_helper"

describe BedrockLinuxGdk::Settings do
  it "preserves unknown backend settings" do
    with_temp_dir("bedrock-settings") do |directory|
      path = File.join(directory, "settings.json")
      File.write(path, %({"future_key":{"nested":7},"show_betas":false}))

      settings = BedrockLinuxGdk::Settings.new(path)
      settings.set("show_betas", true)

      stored = JSON.parse(File.read(path))
      stored["show_betas"].as_bool.should be_true
      stored["future_key"]["nested"].as_i.should eq(7)
    end
  end

  it "recovers from malformed JSON" do
    with_temp_dir("bedrock-settings") do |directory|
      path = File.join(directory, "settings.json")
      File.write(path, "{not-json")
      settings = BedrockLinuxGdk::Settings.new(path)
      settings.string("mc_version").should eq("")
    end
  end
end
