module BedrockLinuxGdk
  module RuntimeDisplay
    extend self

    def apply(
      environment : Hash(String, String),
      preference : String,
    ) : String
      wayland = !environment["WAYLAND_DISPLAY"]?.to_s.strip.empty?
      display = !environment["DISPLAY"]?.to_s.strip.empty?
      requested = preference.strip.downcase
      backend = case requested
                when "wayland"
                  wayland ? "wayland" : "x11"
                when "x11"
                  "x11"
                else
                  display ? "x11" : (wayland ? "wayland" : "x11")
                end

      if backend == "wayland"
        environment["PROTON_ENABLE_WAYLAND"] = "1"
        environment.delete("DISPLAY")
        environment.delete("WINE_DISABLE_VULKAN_OPWR")
      else
        environment["PROTON_ENABLE_WAYLAND"] = "0"
        if wayland
          environment["WINE_DISABLE_VULKAN_OPWR"] = "1"
        else
          environment.delete("WINE_DISABLE_VULKAN_OPWR")
        end
      end
      backend
    end
  end
end
