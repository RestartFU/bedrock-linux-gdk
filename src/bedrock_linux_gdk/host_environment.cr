module BedrockLinuxGdk
  module HostEnvironment
    extend self

    RESTORED = {
      "XDG_DATA_DIRS" => "BEDROCK_HOST_XDG_DATA_DIRS",
      "LANG"          => "BEDROCK_HOST_LANG",
      "LC_ALL"        => "BEDROCK_HOST_LC_ALL",
    }

    BUNDLE_ONLY = %w(
      BEDROCK_HOST_GIO_EXTRA_MODULES
      BEDROCK_HOST_GTK_PATH
      BEDROCK_HOST_GTK_THEME
      GIO_MODULE_DIR
      GIO_EXTRA_MODULES
      GI_TYPELIB_PATH
      GDK_PIXBUF_MODULE_FILE
      GSETTINGS_SCHEMA_DIR
      NIX_GSETTINGS_OVERRIDES_DIR
      GTK_PATH
      GTK_THEME
      GTK_MODULES
      GTK_IM_MODULE
      GTK_IM_MODULE_FILE
      GTK_EXE_PREFIX
      GTK_DATA_PREFIX
      FONTCONFIG_PATH
      FONTCONFIG_FILE
      LOCPATH
      OPENSSL_MODULES
      XKB_CONFIG_ROOT
      XLOCALEDIR
      __EGL_VENDOR_LIBRARY_FILENAMES
      LIBGL_DRIVERS_PATH
    )

    def values(
      environment : Hash(String, String) = ENV.to_h,
      executable : String? = Process.executable_path,
    ) : Hash(String, String)
      environment = environment.dup
      BUNDLE_ONLY.each { |key| environment.delete(key) }

      RESTORED.each do |key, saved|
        value = environment.delete(saved)
        if value && !value.empty?
          environment[key] = value
        else
          environment.delete(key)
        end
      end
      add_system_umu(environment)
      environment
    end

    private def add_system_umu(environment : Hash(String, String)) : Nil
      return if environment.has_key?("BEDROCK_LINUX_GDK_UMU")
      return unless path = environment["PATH"]?

      path.split(':').each do |directory|
        next if directory.empty?
        candidate = File.join(directory, "umu-run")
        if File::Info.executable?(candidate)
          environment["BEDROCK_LINUX_GDK_UMU"] = candidate
          return
        end
      rescue File::Error
      end
    end
  end
end
