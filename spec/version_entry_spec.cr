require "./spec_helper"

describe BedrockLinuxGdk::VersionEntry do
  it "parses stable backend output" do
    entry = BedrockLinuxGdk::VersionEntry.parse(
      "  1.26.33.1      stable   912 MiB"
    ).not_nil!
    entry.tag.should eq("1.26.33.1")
    entry.beta.should be_false
    entry.size_mib.should eq(912)
    entry.display.should eq("26.33")
  end

  it "parses previews" do
    entry = BedrockLinuxGdk::VersionEntry.parse(
      "  1.26.40.23       beta   940 MiB"
    ).not_nil!
    entry.beta.should be_true
    entry.display.should eq("26.40.23  ·  PREVIEW")
  end

  it "ignores log lines" do
    BedrockLinuxGdk::VersionEntry.parse("info  Downloading…").should be_nil
  end
end
