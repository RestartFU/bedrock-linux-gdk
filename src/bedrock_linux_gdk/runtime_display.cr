module BedrockLinuxGdk
  module RuntimeDisplay
    extend self

    def apply(
      environment : Hash(String, String),
      preference : String,
    ) : String
      wayland_display = !environment["WAYLAND_DISPLAY"]?.to_s.strip.empty?
      wayland_session =
        wayland_display ||
          environment["XDG_SESSION_TYPE"]?.to_s.strip.downcase == "wayland"
      display = !environment["DISPLAY"]?.to_s.strip.empty?
      requested = preference.strip.downcase
      backend = case requested
                when "wayland"
                  wayland_display ? "wayland" : "x11"
                when "x11"
                  "x11"
                else
                  display ? "x11" : (wayland_display ? "wayland" : "x11")
                end

      if backend == "wayland"
        environment["PROTON_ENABLE_WAYLAND"] = "1"
        environment.delete("DISPLAY")
        environment.delete("WINE_DISABLE_VULKAN_OPWR")
        environment.delete("PROTON_NO_WM_DECORATION")
      else
        environment["PROTON_ENABLE_WAYLAND"] = "0"
        environment["PROTON_NO_WM_DECORATION"] = "1"
        if wayland_session
          environment["WINE_DISABLE_VULKAN_OPWR"] = "1"
        else
          environment.delete("WINE_DISABLE_VULKAN_OPWR")
        end
      end
      backend
    end
  end
end
