require "digest/sha256"
require "http/client"
require "json"
require "file_utils"
require "./bedrock_linux_gdk/version"
require "./bedrock_linux_gdk/xbox_auth"

module BedrockLinuxGdk
  module Engine
    extend self

    RELEASES_URL       = "https://api.github.com/repos/bubbles-wow/mcbe-gdk-unpack-archive/releases?per_page=100"
    PROTON_RELEASE_URL = "https://api.github.com/repos/Weather-OS/GDK-Proton/releases/latest"
    UMU_RELEASE_URL    = "https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest"
    DXVK_VERSION       = "3.0.1"
    DXVK_URL           = "https://github.com/doitsujin/dxvk/releases/download/v#{DXVK_VERSION}/dxvk-#{DXVK_VERSION}.tar.gz"
    DXVK_SHA256        = "bebb6284db590535b7b005c102ebf6850c98842cff0fded9aacb74babae14c49"
    GAME_INPUT_VERSION = "3.5.262"
    GAME_INPUT_URL     = "https://api.nuget.org/v3-flatcontainer/microsoft.gameinput/#{GAME_INPUT_VERSION}/microsoft.gameinput.#{GAME_INPUT_VERSION}.nupkg"
    record Release,
      tag : String,
      beta : Bool,
      url : String,
      name : String,
      size : Int64

    def run(arguments : Array(String)) : Int32
      command = arguments.shift?
      case command
      when "versions"
        versions(arguments.includes?("--beta"))
      when "doctor"
        doctor
      when "setup"
        setup(option(arguments, "--mc"))
      when "play"
        play
      when "login"
        login
      when "update"
        ok("Engine updates with Bedrock Linux GDK.")
        0
      when "repair"
        error("Repair is not needed unless prefix files are damaged.")
        1
      when "--version", "version"
        puts "bedrock-linux-gdk-engine #{BedrockLinuxGdk.version_string}"
        0
      else
        error("Usage: bedrock-linux-gdk-engine versions|doctor|setup|play|login|update")
        2
      end
    rescue exception
      error(exception.message || exception.class.name)
      1
    end

    private def root : String
      override = ENV["BEDROCK_LINUX_GDK_HOME"]?.to_s.strip
      return File.expand_path(override) unless override.empty?

      data_home = ENV["XDG_DATA_HOME"]? ||
                  File.join(Path.home.to_s, ".local", "share")
      File.join(data_home, "bedrock-linux-gdk")
    end

    private def shared_root : String
      override = ENV["BEDROCK_LINUX_GDK_SHARED_HOME"]?.to_s.strip
      override.empty? ? root : File.expand_path(override)
    end

    private def versions(include_beta : Bool) : Int32
      releases.each do |release|
        next if release.beta && !include_beta
        channel = release.beta ? "beta" : "stable"
        size = (release.size / 1024 / 1024).to_i
        puts "#{release.tag.ljust(14)} #{channel.ljust(8)} #{size} MiB"
      end
      0
    end

    private def releases : Array(Release)
      body = fetch_releases
      JSON.parse(body).as_a.compact_map do |item|
        object = item.as_h
        tag = object["tag_name"]?.try(&.as_s?).to_s
        next unless tag.matches?(/^\d+\.\d+\.\d+(?:\.\d+)?$/)

        asset = object["assets"]?.try(&.as_a?).try do |assets|
          assets.find do |candidate|
            name = candidate["name"]?.try(&.as_s?).to_s.downcase
            name.ends_with?(".zip") && name.includes?("minecraft")
          end
        end
        next unless asset

        url = asset["browser_download_url"]?.try(&.as_s?).to_s
        next if url.empty?

        Release.new(
          tag,
          object["prerelease"]?.try(&.as_bool?) || false,
          url,
          asset["name"]?.try(&.as_s?).to_s,
          asset["size"]?.try(&.as_i64?) || 0_i64
        )
      end
    rescue JSON::ParseException | TypeCastError
      raise "Minecraft version service returned invalid data."
    end

    private def fetch_releases : String
      cache = File.join(shared_root, "cache", "minecraft-releases.json")
      begin
        response = HTTP::Client.get(
          RELEASES_URL,
          headers: HTTP::Headers{
            "Accept"     => "application/vnd.github+json",
            "User-Agent" => "bedrock-linux-gdk/#{BedrockLinuxGdk::VERSION}",
          }
        )
        raise "Minecraft version service returned HTTP #{response.status_code}." unless response.success?
        Dir.mkdir_p(File.dirname(cache), 0o700)
        File.write(cache, response.body, perm: 0o600)
        response.body
      rescue exception
        return File.read(cache) if File.file?(cache)
        raise exception
      end
    end

    private def doctor : Int32
      info("Bedrock Linux GDK engine — system check")
      missing = [] of String
      {
        "curl"  => find_command("curl"),
        "tar"   => find_command("tar"),
        "unzip" => find_command("unzip"),
      }.each do |name, path|
        if path
          puts "#{name.ljust(12)} : OK"
        else
          puts "#{name.ljust(12)} : MISSING"
          missing << name
        end
      end

      unless missing.empty?
        warn("Install missing tools: #{missing.join(", ")}")
        return 1
      end

      ok("System ready.")
      0
    end

    private def setup(tag : String?) : Int32
      raise "Choose a Minecraft version first." unless tag
      Dir.mkdir_p(root, 0o700)

      game = find_game(tag)
      unless game
        release = releases.find(&.tag.==(tag))
        raise "Minecraft version #{tag} is unavailable." unless release
        game = install_game(release)
      end

      umu = ensure_umu
      engine = ensure_proton
      ensure_dxvk(engine)
      ensure_prefix(umu, engine)
      ensure_game_input(umu, engine)
      ensure_runtime_bridge(engine)

      save_game(tag, game)
      ok("Minecraft #{tag} ready.")
      0
    end

    private def install_game(release : Release) : String
      curl = find_command("curl") || raise "curl is missing."
      unzip = find_command("unzip") || raise "unzip is missing."
      cache = File.join(shared_root, "cache")
      games = File.join(shared_root, "games")
      archive = File.join(cache, release.name)
      staging = File.join(games, ".#{release.tag}.installing")
      target = File.join(games, release.tag)
      Dir.mkdir_p(cache, 0o700)
      Dir.mkdir_p(games, 0o700)

      unless File.file?(archive) && File.size(archive) == release.size
        partial = "#{archive}.partial"
        info("Downloading Minecraft #{release.tag} …")
        status = Process.run(
          curl,
          ["--fail", "--location", "--output", partial, release.url],
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
        raise "Minecraft download failed." unless status.success?
        File.rename(partial, archive)
      end

      FileUtils.rm_r(staging) if Dir.exists?(staging)
      Dir.mkdir_p(staging, 0o700)
      info("Installing Minecraft #{release.tag} …")
      status = Process.run(
        unzip,
        ["-q", archive, "-d", staging],
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )
      raise "Minecraft archive extraction failed." unless status.success?
      game = find_game_root(staging) || raise "Minecraft archive is incomplete."
      FileUtils.rm_r(target) if Dir.exists?(target)
      File.rename(staging, target)
      game.sub(staging, target)
    end

    private def find_game(tag : String) : String?
      find_game_root(File.join(shared_root, "games", tag))
    end

    private def find_game_root(directory : String) : String?
      return unless Dir.exists?(directory)
      Dir.glob(File.join(directory, "**", "Minecraft.Windows.exe")).each do |exe|
        parent = File.dirname(exe)
        return parent if File.file?(File.join(parent, "AppxManifest.xml")) ||
                         File.file?(File.join(parent, "appxmanifest.xml"))
      end
      nil
    end

    private def save_game(tag : String, game : String) : Nil
      settings = load_settings
      %w(proton proton_source proton_tag winegdk_built).each do |key|
        settings.delete(key)
      end
      settings["mc_version"] = JSON::Any.new(tag)
      settings["game_dir"] = JSON::Any.new(game)
      write_json(File.join(root, "settings.json"), JSON::Any.new(settings))

      content = File.join(root, "content")
      if File.symlink?(content)
        File.delete(content)
      elsif File.exists?(content)
        return
      end
      File.symlink(game, content)
    end

    private def play : Int32
      game = selected_game || raise "No game installed — choose a Minecraft version first."
      engine = proton || raise "Compatibility engine missing — run Install / Update."
      umu = umu_command || raise "umu-run is missing."
      ensure_dxvk(engine)
      patch_compatibility_engine(engine)
      prefix = File.join(root, "compatdata", "pfx")
      raise "Wine prefix missing — run Install / Update." unless File.file?(File.join(prefix, "system.reg"))
      raise "No Microsoft account linked — click Sign in first." unless account_linked?
      ensure_runtime_bridge(engine)
      auth = XboxAuth.refresh(root)
      XboxAuth.seed_refresh_token(root, auth.refresh_token)

      environment = compatibility_environment(engine)
      environment["WINEGDK_PREAUTH_DEVICE"] = wine_path(
        XboxAuth.preauth_path(root)
      )
      environment["WINEDLLOVERRIDES"] =
        "xgameruntime=n,b;cryptbase=n,b;vrclient=;vrclient_x64=;openvr_api=;wineopenxr=;amd_ags_x64="
      environment["MICROSOFT_WINDOWSAPPRUNTIME_BOOTSTRAP_INITIALIZE_SHOWUI"] = "0"
      environment["MICROSOFT_WINDOWSAPPRUNTIME_BOOTSTRAP_INITIALIZE_FAILFAST"] = "0"
      environment["MICROSOFT_WINDOWSAPPRUNTIME_DEPLOYMENT_INITIALIZE_ONERRORSHOWUI"] = "0"
      info("Starting Minecraft.")
      status = Process.run(
        umu,
        [File.join(game, "Minecraft.Windows.exe")],
        env: environment,
        chdir: game,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )
      status.exit_code
    end

    private def login : Int32
      game = selected_game ||
             raise "Install Minecraft before signing in."
      engine = proton ||
               raise "Compatibility engine missing — run Install / Update."
      prefix = File.join(root, "compatdata", "pfx")
      raise "Wine prefix missing — run Install / Update." unless File.file?(File.join(prefix, "system.reg"))

      ensure_runtime_bridge(engine)
      account = XboxAuth.sign_in(root) do |url, code|
        puts "device\t#{url}\t#{code}"
      end
      XboxAuth.seed_refresh_token(root, account.refresh_token)
      write_json(
        File.join(root, "account.json"),
        JSON.parse({
          "user_id"   => account.user_id,
          "gamertag"  => account.gamertag,
          "linked_at" => Time.utc.to_unix,
        }.to_json)
      )
      ok(
        "Microsoft account linked" \
        "#{account.gamertag.empty? ? "" : " as #{account.gamertag}"}."
      )
      0
    end

    private def selected_game : String?
      game = load_settings["game_dir"]?.try(&.as_s?)
      return game if game && File.file?(File.join(game, "Minecraft.Windows.exe"))
      version = load_settings["mc_version"]?.try(&.as_s?)
      version ? find_game(version) : nil
    end

    private def account_linked? : Bool
      path = File.join(root, "account.json")
      return false unless File.file?(path)
      !JSON.parse(File.read(path))["user_id"]?.try(&.as_s?).to_s.empty?
    rescue JSON::ParseException | File::Error
      false
    end

    private def ensure_umu : String
      if command = umu_command
        return command
      end

      asset = github_asset(UMU_RELEASE_URL) do |name|
        name.ends_with?("-zipapp.tar")
      end
      archive = File.join(shared_root, "cache", asset[:name])
      staging = File.join(shared_root, "tools", ".umu.installing")
      target = File.join(shared_root, "tools", "umu")
      download(asset[:url], archive, asset[:size])

      FileUtils.rm_r(staging) if Dir.exists?(staging)
      Dir.mkdir_p(staging, 0o700)
      extract_tar(archive, staging)
      source = Dir.glob(File.join(staging, "**", "umu-run"))
        .find { |path| File::Info.executable?(path) }
      raise "UMU archive is incomplete." unless source

      FileUtils.rm_r(target) if Dir.exists?(target)
      File.rename(File.dirname(source), target)
      FileUtils.rm_r(staging) if Dir.exists?(staging)
      command = File.join(target, "umu-run")
      ok("UMU launcher ready.")
      command
    end

    private def ensure_proton : String
      if engine = proton
        return engine
      end

      asset = github_asset(PROTON_RELEASE_URL) do |name|
        name.ends_with?(".tar.gz")
      end
      archive = File.join(shared_root, "cache", asset[:name])
      staging = File.join(shared_root, "proton", ".gdk-proton.installing")
      target = File.join(shared_root, "proton", "GDK-Proton")
      download(asset[:url], archive, asset[:size])

      FileUtils.rm_r(staging) if Dir.exists?(staging)
      Dir.mkdir_p(staging, 0o700)
      extract_tar(archive, staging)
      source = Dir.glob(File.join(staging, "**", "proton"))
        .find { |path| File::Info.executable?(path) }
      raise "GDK-Proton archive is incomplete." unless source

      FileUtils.rm_r(target) if Dir.exists?(target)
      File.rename(File.dirname(source), target)
      FileUtils.rm_r(staging) if Dir.exists?(staging)
      engine = target
      ok("GDK-Proton ready.")
      engine
    end

    private def ensure_dxvk(engine : String) : Nil
      target = File.join(engine, "files", "lib", "wine", "dxvk")
      version_file = File.join(target, "version")
      if File.file?(version_file) &&
         File.read(version_file).includes?("v#{DXVK_VERSION}")
        return
      end

      archive = File.join(shared_root, "cache", "dxvk-#{DXVK_VERSION}.tar.gz")
      download(DXVK_URL, archive, 0)
      digest = Digest::SHA256.hexdigest(File.read(archive))
      raise "DXVK archive checksum mismatch." unless digest == DXVK_SHA256

      staging = File.join(shared_root, "proton", ".dxvk.installing")
      FileUtils.rm_r(staging) if Dir.exists?(staging)
      Dir.mkdir_p(staging, 0o700)
      extract_tar(archive, staging)
      source = File.join(staging, "dxvk-#{DXVK_VERSION}")
      raise "DXVK archive is incomplete." unless Dir.exists?(source)

      {
        "x64" => "x86_64-windows",
        "x32" => "i386-windows",
      }.each do |source_arch, target_arch|
        %w(d3d9 d3d10core d3d11 dxgi).each do |name|
          from = File.join(source, source_arch, "#{name}.dll")
          to = File.join(target, target_arch, "#{name}.dll")
          raise "DXVK archive is incomplete." unless File.file?(from)
          File.copy(to, "#{to}.gdk-base") unless File.file?("#{to}.gdk-base")
          File.copy(from, to)
        end
      end
      File.write(
        version_file,
        "v#{DXVK_VERSION} dxvk (v#{DXVK_VERSION})\n"
      )
      FileUtils.rm_r(staging)
      ok("DXVK #{DXVK_VERSION} ready.")
    end

    private def patch_compatibility_engine(engine : String) : Nil
      wine = File.join(engine, "files", "lib", "wine", "x86_64-windows")
      patch_export(
        File.join(wine, "combase.dll"),
        "RoOriginateErrorW",
        Bytes[0x31, 0xc0, 0xc3, 0x90]
      )
      patch_export(
        File.join(wine, "ntdll.dll"),
        "NtQueryWnfStateData",
        Bytes[0xb8, 0x02, 0x00, 0x00, 0xc0, 0xc3],
        required: false
      )
    end

    private def patch_export(
      path : String,
      export_name : String,
      replacement : Bytes,
      required : Bool = true,
    ) : Nil
      raise "Compatibility DLL missing: #{File.basename(path)}." unless File.file?(path)
      bytes = File.read(path).to_slice.dup
      offset = pe_export_offset(bytes, export_name)
      unless offset
        raise "Compatibility export missing: #{export_name}." if required
        return
      end
      raise "Compatibility export is outside its DLL." if offset + replacement.size > bytes.size

      current = bytes[offset, replacement.size]
      return if current == replacement

      backup = "#{path}.gdk-original"
      File.copy(path, backup) unless File.file?(backup)
      bytes[offset, replacement.size].copy_from(replacement)
      File.open(path, "wb") { |file| file.write(bytes) }
      ok("#{File.basename(path)}.#{export_name} patched.")
    end

    private def pe_export_offset(bytes : Bytes, name : String) : Int32?
      raise "Invalid compatibility DLL." unless bytes.size >= 0x40 &&
                                                bytes[0] == 0x4d &&
                                                bytes[1] == 0x5a
      pe = read_u32(bytes, 0x3c).to_i
      raise "Invalid compatibility DLL." unless pe + 24 < bytes.size &&
                                                bytes[pe, 4] == Bytes[0x50, 0x45, 0x00, 0x00]

      coff = pe + 4
      section_count = read_u16(bytes, coff + 2).to_i
      optional = coff + 20
      raise "Unsupported compatibility DLL." unless read_u16(bytes, optional) == 0x20b

      export_rva = read_u32(bytes, optional + 112)
      section_table = optional + read_u16(bytes, coff + 16).to_i
      sections = [] of Tuple(UInt32, UInt32, UInt32, UInt32)
      section_count.times do |index|
        base = section_table + index * 40
        sections << {
          read_u32(bytes, base + 12),
          read_u32(bytes, base + 8),
          read_u32(bytes, base + 20),
          read_u32(bytes, base + 16),
        }
      end

      exports = rva_to_offset(export_rva, sections)
      return unless exports
      name_count = read_u32(bytes, exports + 24).to_i
      functions = rva_to_offset(read_u32(bytes, exports + 28), sections)
      names = rva_to_offset(read_u32(bytes, exports + 32), sections)
      ordinals = rva_to_offset(read_u32(bytes, exports + 36), sections)
      return unless functions && names && ordinals

      name_count.times do |index|
        name_offset = rva_to_offset(
          read_u32(bytes, names + index * 4),
          sections
        )
        next unless name_offset
        finish = name_offset
        while finish < bytes.size && bytes[finish] != 0
          finish += 1
        end
        next unless String.new(bytes[name_offset, finish - name_offset]) == name

        ordinal = read_u16(bytes, ordinals + index * 2).to_i
        function_rva = read_u32(bytes, functions + ordinal * 4)
        return rva_to_offset(function_rva, sections)
      end
      nil
    end

    private def rva_to_offset(
      rva : UInt32,
      sections : Array(Tuple(UInt32, UInt32, UInt32, UInt32)),
    ) : Int32?
      sections.each do |section|
        virtual_address, virtual_size, raw_offset, raw_size = section
        size = Math.max(virtual_size, raw_size)
        if rva >= virtual_address && rva < virtual_address + size
          return (raw_offset + rva - virtual_address).to_i
        end
      end
      nil
    end

    private def read_u16(bytes : Bytes, offset : Int32) : UInt16
      bytes[offset].to_u16 |
        (bytes[offset + 1].to_u16 << 8)
    end

    private def read_u32(bytes : Bytes, offset : Int32) : UInt32
      bytes[offset].to_u32 |
        (bytes[offset + 1].to_u32 << 8) |
        (bytes[offset + 2].to_u32 << 16) |
        (bytes[offset + 3].to_u32 << 24)
    end

    private def ensure_prefix(umu : String, engine : String) : Nil
      prefix = File.join(root, "compatdata", "pfx")
      return if File.file?(File.join(prefix, "system.reg"))

      Dir.mkdir_p(File.dirname(prefix), 0o700)
      info("Initialising compatibility prefix …")
      status = Process.run(
        umu,
        ["wineboot", "-u"],
        env: compatibility_environment(engine),
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )
      raise "Compatibility prefix initialisation failed." unless status.success?
      raise "Compatibility prefix is incomplete." unless File.file?(File.join(prefix, "system.reg"))
      ok("Compatibility prefix ready.")
    end

    private def ensure_game_input(umu : String, engine : String) : Nil
      installed = File.join(
        root,
        "compatdata",
        "pfx",
        "drive_c",
        "Program Files",
        "Microsoft GameInput",
        "x64",
        "GameInputRedist.dll"
      )
      return if File.file?(installed)

      archive = File.join(
        shared_root,
        "cache",
        "Microsoft.GameInput.#{GAME_INPUT_VERSION}.nupkg"
      )
      installer = File.join(shared_root, "cache", "GameInputRedist.msi")
      download(GAME_INPUT_URL, archive, 0_i64)
      unzip = find_command("unzip") || raise "unzip is missing."
      File.open(installer, "wb", perm: 0o600) do |output|
        status = Process.run(
          unzip,
          ["-p", archive, "redist/GameInputRedist.msi"],
          output: output,
          error: Process::Redirect::Inherit
        )
        raise "GameInput archive extraction failed." unless status.success?
      end

      info("Installing Microsoft GameInput …")
      status = Process.run(
        umu,
        [
          "msiexec.exe", "/i", wine_path(installer),
          "/qn", "/norestart",
        ],
        env: compatibility_environment(engine),
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )
      unless status.success? || status.exit_code == 194
        raise "Microsoft GameInput installation failed."
      end
      raise "Microsoft GameInput installation is incomplete." unless File.file?(installed)
      ok("Microsoft GameInput ready.")
    end

    private def ensure_runtime_bridge(engine : String) : Nil
      source = runtime_asset("xgameruntime.dll")
      wine = File.join(engine, "files", "lib", "wine", "x86_64-windows")
      threading = File.join(wine, "xgameruntime.dll.threading")
      target = File.join(wine, "xgameruntime.dll")
      raise "Official Xbox runtime is missing from GDK-Proton." unless File.file?(threading)
      raise "GDK-Proton runtime directory is missing." unless Dir.exists?(wine)

      changed = copy_if_changed(source, target, backup: "#{target}.gdk-stock")
      prefix_target = File.join(
        root,
        "compatdata",
        "pfx",
        "drive_c",
        "windows",
        "system32",
        "xgameruntime.dll"
      )
      if Dir.exists?(File.dirname(prefix_target))
        changed = copy_if_changed(source, prefix_target) || changed
      end
      ok("Xbox runtime bridge ready.") if changed
    end

    private def runtime_asset(name : String) : String
      directory = ENV["BEDROCK_LINUX_GDK_RUNTIME_DIR"]?.to_s.strip
      raise "Bundled runtime directory is unavailable — reinstall Bedrock Linux GDK." if directory.empty?
      path = File.join(directory, name)
      raise "Bundled runtime asset is missing: #{name}." unless File.file?(path)
      path
    end

    private def copy_if_changed(
      source : String,
      target : String,
      backup : String? = nil,
    ) : Bool
      if File.file?(target)
        return false if Digest::SHA256.hexdigest(File.read(source)) ==
                          Digest::SHA256.hexdigest(File.read(target))
        File.copy(target, backup) if backup && !File.file?(backup)
      end
      Dir.mkdir_p(File.dirname(target), 0o700)
      File.copy(source, target)
      true
    end

    private def wine_path(path : String) : String
      "Z:#{File.expand_path(path).gsub('/', '\\')}"
    end

    private def compatibility_environment(engine : String) : Hash(String, String)
      environment = ENV.to_h
      environment["PROTONPATH"] = engine
      environment["PROTON_VERB"] = "run"
      environment["WINEPREFIX"] = File.join(root, "compatdata", "pfx")
      environment["GAMEID"] = "umu-default"
      environment["PROTON_USE_WOW64"] = "1"
      environment["UMU_FOLDERS_PATH"] = shared_root
      environment["UMU_RUNTIME_UPDATE"] = "0"
      unless environment["WAYLAND_DISPLAY"]?.to_s.strip.empty?
        environment["PROTON_ENABLE_WAYLAND"] = "1"
        environment.delete("DISPLAY")
        environment.delete("WINE_DISABLE_VULKAN_OPWR")
      else
        environment["PROTON_ENABLE_WAYLAND"] = "0"
        environment.delete("WINE_DISABLE_VULKAN_OPWR")
      end
      environment
    end

    private def github_asset(
      url : String,
      &matches : String -> Bool
    ) : NamedTuple(name: String, url: String, size: Int64)
      response = HTTP::Client.get(
        url,
        headers: HTTP::Headers{
          "Accept"     => "application/vnd.github+json",
          "User-Agent" => "bedrock-linux-gdk/#{BedrockLinuxGdk::VERSION}",
        }
      )
      raise "Dependency service returned HTTP #{response.status_code}." unless response.success?

      release = JSON.parse(response.body)
      asset = release["assets"].as_a.find do |candidate|
        name = candidate["name"]?.try(&.as_s?).to_s
        matches.call(name)
      end
      raise "Required dependency archive is unavailable." unless asset

      {
        name: asset["name"].as_s,
        url:  asset["browser_download_url"].as_s,
        size: asset["size"].as_i64,
      }
    rescue JSON::ParseException | TypeCastError
      raise "Dependency service returned invalid data."
    end

    private def download(url : String, path : String, size : Int64) : Nil
      return if File.file?(path) && (size <= 0 || File.size(path) == size)

      curl = find_command("curl") || raise "curl is missing."
      Dir.mkdir_p(File.dirname(path), 0o700)
      partial = "#{path}.partial"
      info("Downloading #{File.basename(path)} …")
      status = Process.run(
        curl,
        ["--fail", "--location", "--output", partial, url],
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )
      raise "Dependency download failed." unless status.success?
      if size > 0 && File.size(partial) != size
        raise "Dependency download is incomplete."
      end
      File.rename(partial, path)
    end

    private def extract_tar(archive : String, destination : String) : Nil
      tar = find_command("tar") || raise "tar is missing."
      status = Process.run(
        tar,
        ["-xf", archive, "-C", destination],
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )
      raise "Dependency archive extraction failed." unless status.success?
    end

    private def proton : String?
      path = File.join(shared_root, "proton", "GDK-Proton")
      executable = File.join(path, "proton")
      manifest = File.join(path, "toolmanifest.vdf")
      File::Info.executable?(executable) && File.file?(manifest) ? path : nil
    rescue File::Error
      nil
    end

    private def umu_command : String?
      bundled = File.join(shared_root, "tools", "umu", "umu-run")
      return bundled if File::Info.executable?(bundled)
      override = ENV["BEDROCK_LINUX_GDK_UMU"]?
      return override if override && File::Info.executable?(override)
      find_command("umu-run")
    rescue File::Error
      nil
    end

    private def find_command(name : String) : String?
      ENV["PATH"]?.to_s.split(':').each do |directory|
        next if directory.empty?
        candidate = File.join(directory, name)
        return candidate if File::Info.executable?(candidate)
      rescue File::Error
      end
      nil
    end

    private def load_settings : Hash(String, JSON::Any)
      path = File.join(root, "settings.json")
      return {} of String => JSON::Any unless File.file?(path)
      JSON.parse(File.read(path)).as_h.dup
    rescue JSON::ParseException | TypeCastError | File::Error
      {} of String => JSON::Any
    end

    private def write_json(path : String, value : JSON::Any) : Nil
      Dir.mkdir_p(File.dirname(path), 0o700)
      temporary = "#{path}.tmp"
      File.write(temporary, value.to_pretty_json + "\n", perm: 0o600)
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.exists?(temporary)
    end

    private def option(arguments : Array(String), name : String) : String?
      index = arguments.index(name)
      index ? arguments[index + 1]? : nil
    end

    private def info(message : String) : Nil
      puts "info   #{message}"
    end

    private def ok(message : String) : Nil
      puts "ok     #{message}"
    end

    private def warn(message : String) : Nil
      puts "warn   #{message}"
    end

    private def error(message : String) : Nil
      STDERR.puts "error  #{message}"
    end
  end
end

exit BedrockLinuxGdk::Engine.run(ARGV)
