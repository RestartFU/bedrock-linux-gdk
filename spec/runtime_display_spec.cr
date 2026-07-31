require "./spec_helper"

describe BedrockLinuxGdk::RuntimeDisplay do
  it "uses stable XWayland presentation by default" do
    environment = {
      "WAYLAND_DISPLAY" => "wayland-0",
      "DISPLAY"         => ":0",
    }

    BedrockLinuxGdk::RuntimeDisplay.apply(environment, "auto")
      .should eq("x11")
    environment["PROTON_ENABLE_WAYLAND"].should eq("0")
    environment["WINE_DISABLE_VULKAN_OPWR"].should eq("1")
    environment["PROTON_NO_WM_DECORATION"].should eq("1")
    environment["DISPLAY"].should eq(":0")
  end

  it "detects XWayland from the session type when its socket is hidden" do
    environment = {
      "XDG_SESSION_TYPE" => "wayland",
      "DISPLAY"          => ":0",
    }

    BedrockLinuxGdk::RuntimeDisplay.apply(environment, "auto")
      .should eq("x11")
    environment["WINE_DISABLE_VULKAN_OPWR"].should eq("1")
    environment["PROTON_NO_WM_DECORATION"].should eq("1")
  end

  it "allows explicit native Wayland" do
    environment = {
      "WAYLAND_DISPLAY"         => "wayland-0",
      "DISPLAY"                 => ":0",
      "PROTON_NO_WM_DECORATION" => "1",
    }

    BedrockLinuxGdk::RuntimeDisplay.apply(environment, "wayland")
      .should eq("wayland")
    environment["PROTON_ENABLE_WAYLAND"].should eq("1")
    environment.has_key?("WINE_DISABLE_VULKAN_OPWR").should be_false
    environment.has_key?("PROTON_NO_WM_DECORATION").should be_false
    environment.has_key?("DISPLAY").should be_false
  end

  it "does not enable Wayland workarounds in native X11 sessions" do
    environment = {"DISPLAY" => ":0"}

    BedrockLinuxGdk::RuntimeDisplay.apply(environment, "auto")
      .should eq("x11")
    environment["PROTON_ENABLE_WAYLAND"].should eq("0")
    environment["PROTON_NO_WM_DECORATION"].should eq("1")
    environment.has_key?("WINE_DISABLE_VULKAN_OPWR").should be_false
  end
end
