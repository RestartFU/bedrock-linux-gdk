module BedrockLinuxGdk
  module HostEnvironment
    extend self

    RESTORED = {
      "XDG_DATA_DIRS"     => "BEDROCK_HOST_XDG_DATA_DIRS",
      "LANG"              => "BEDROCK_HOST_LANG",
      "LC_ALL"            => "BEDROCK_HOST_LC_ALL",
      "GIO_EXTRA_MODULES" => "BEDROCK_HOST_GIO_EXTRA_MODULES",
      "GTK_PATH"          => "BEDROCK_HOST_GTK_PATH",
      "GTK_THEME"         => "BEDROCK_HOST_GTK_THEME",
    }

    BUNDLE_ONLY = %w(
      GIO_MODULE_DIR
      GDK_PIXBUF_MODULE_FILE
      GSETTINGS_SCHEMA_DIR
      FONTCONFIG_PATH
      FONTCONFIG_FILE
      LOCPATH
      OPENSSL_MODULES
      XKB_CONFIG_ROOT
      XLOCALEDIR
      __EGL_VENDOR_LIBRARY_FILENAMES
      LIBGL_DRIVERS_PATH
    )

    def values : Hash(String, String)
      environment = ENV.to_h
      BUNDLE_ONLY.each { |key| environment.delete(key) }

      RESTORED.each do |key, saved|
        value = environment.delete(saved)
        if value && !value.empty?
          environment[key] = value
        else
          environment.delete(key)
        end
      end
      environment
    end
  end
end
