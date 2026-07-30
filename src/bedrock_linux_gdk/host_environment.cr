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
      add_bundled_python(environment, executable)
      environment
    end

    private def add_bundled_python(
      environment : Hash(String, String),
      executable : String?,
    ) : Nil
      return unless executable

      root = File.dirname(File.dirname(executable))
      python = File.join(root, "share", "bedrock-linux-gdk", "python")
      return unless Dir.exists?(python)

      existing = environment["PYTHONPATH"]?
      environment["PYTHONPATH"] =
        existing && !existing.empty? ? "#{python}:#{existing}" : python
    end
  end
end
