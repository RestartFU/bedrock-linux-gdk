require "gtk4"
require "../account"
require "../backend"
require "../host_environment"
require "../launch_session"
require "../paths"
require "../process_job"
require "../settings"
require "../version"
require "../version_entry"
require "./adw"
require "./dialogs"
require "./host_launch"
require "./pointer_cursors"
require "./updater"

module BedrockLinuxGdk
  module UI
    class Window
      getter widget : Adw::ApplicationWindow

      @versions = [] of VersionEntry
      @log_lines = [] of String
      @pending_log_lines = [] of String
      @job = ProcessJob.new
      @launch_jobs = {} of String => ProcessJob
      @refreshing_versions = false
      @syncing_version = false
      @syncing_session = false
      @operation_cancelled = false
      @progress_indeterminate = false
      @progress_pulse_id = 0_u32
      @log_flush_scheduled = false
      @nav_buttons = {} of String => Gtk::Button

      def initialize(application : Gtk::Application)
        @backend = Backend.detect
        @paths = Paths.new
        @settings = Settings.for(@paths)
        @session_store = SessionStore.new(
          @paths.data_dir,
          environment: ENV.to_h
        )
        @sessions = @session_store.list
        @current_session = @sessions.first

        @widget = Adw::ApplicationWindow.new(application: application)
        @widget.title = APP_NAME
        @widget.set_default_size(1180, 760)

        @stack = Gtk::Stack.new
        @stack.transition_type = :crossfade
        @stack.transition_duration = 130_u32
        @stack.hexpand = true
        @stack.vexpand = true

        @version_model = Gtk::StringList.new(["Loading versions…"])
        @version_row = Adw::ComboRow.new
        @version_row.title = "Minecraft version"
        @version_row.subtitle = "Stable releases"
        @version_row.add_css_class("gdk-version")
        @version_row.notify_signal["selected"].connect do |_property|
          version_selected
        end

        @session_model = Gtk::StringList.new(@sessions.map(&.name))
        @session_row = Adw::ComboRow.new
        @session_row.title = "Account"
        @session_row.subtitle = "Separate credentials, worlds and Wine prefix"
        @session_row.add_css_class("gdk-version")
        @session_row.notify_signal["selected"].connect do |_property|
          session_selected
        end

        @play_button = Gtk::Button.new_with_label("Play")
        @play_button.add_css_class("suggested-action")
        @play_button.clicked_signal.connect { play }

        @setup_button = Gtk::Button.new_with_label("Install / Update")
        @setup_button.clicked_signal.connect { setup }

        @uninstall_button = Gtk::Button.new_with_label("Uninstall")
        @uninstall_button.add_css_class("destructive-action")
        @uninstall_button.visible = false
        @uninstall_button.clicked_signal.connect { uninstall }

        @cancel_button = Gtk::Button.new_with_label("Cancel")
        @cancel_button.add_css_class("destructive-action")
        @cancel_button.visible = false
        @cancel_button.clicked_signal.connect { cancel_operation }

        @status_label = Gtk::Label.new("")
        @status_label.xalign = 0_f32
        @status_label.add_css_class("gdk-status")

        @spinner = Gtk::Spinner.new
        @spinner.visible = false

        @progress_bar = Gtk::ProgressBar.new
        @progress_bar.show_text = true
        @progress_bar.visible = false
        @progress_bar.add_css_class("gdk-progress")

        @log_view = Gtk::TextView.new
        @log_view.editable = false
        @log_view.cursor_visible = false
        @log_view.monospace = true
        @log_view.wrap_mode = :word_char
        @log_view.add_css_class("gdk-log")

        @account_button = Gtk::Button.new_with_label("Sign in")
        @account_button.add_css_class("flat")
        @account_button.add_css_class("gdk-account")
        @account_button.clicked_signal.connect { show_account_manager }

        build_pages
        @updater = Updater.new(@widget, ->(line : String) { append_log(line) })
        @widget.content = build_shell
        PointerCursors.apply(@widget)
        @widget.close_request_signal.connect do
          @updater.close
          stop_progress_pulse
          false
        end

        refresh_account
        normalize_account_profile_names
        refresh_install_state
        set_backend_state

        GLib.timeout(120.milliseconds) do
          refresh_versions
          false
        end
      end

      def present : Nil
        @widget.present
      end

      private def build_shell : Gtk::Widget
        sidebar = build_sidebar

        title = Adw::WindowTitle.new(
          title: APP_NAME,
          subtitle: "Windows GDK launcher"
        )
        header = Adw::HeaderBar.new
        header.title_widget = title
        header.pack_end(@account_button)
        header.pack_end(@updater.widget)

        toolbar = Adw::ToolbarView.new
        toolbar.add_top_bar(header)
        toolbar.content = @stack
        toolbar.add_css_class("gdk-content")

        split = Gtk::Paned.new(:horizontal)
        split.start_child = sidebar
        split.end_child = toolbar
        split.position = 214
        split.resize_start_child = false
        split.shrink_start_child = false
        split.resize_end_child = true
        split.shrink_end_child = false
        split
      end

      private def build_sidebar : Gtk::Widget
        brand_icon = Gtk::Image.new_from_icon_name(APP_ID)
        brand_icon.pixel_size = 34
        brand_title = Gtk::Label.new("BEDROCK")
        brand_title.xalign = 0_f32
        brand_title.add_css_class("title-3")
        brand_subtitle = Gtk::Label.new("LINUX GDK")
        brand_subtitle.xalign = 0_f32
        brand_subtitle.add_css_class("dim-label")

        brand_text = Gtk::Box.new(:vertical, 0)
        brand_text.append(brand_title)
        brand_text.append(brand_subtitle)
        brand = Gtk::Box.new(:horizontal, 10)
        brand.append(brand_icon)
        brand.append(brand_text)
        brand.add_css_class("gdk-brand")

        navigation = Gtk::Box.new(:vertical, 4)
        navigation.append(nav_button("home", "Home", "go-home-symbolic"))
        navigation.append(
          nav_button("settings", "Settings", "emblem-system-symbolic")
        )
        navigation.append(
          nav_button(
            "diagnostics",
            "Diagnostics",
            "utilities-system-monitor-symbolic"
          )
        )

        backend_label = Gtk::Label.new(@backend.label)
        backend_label.xalign = 0_f32
        backend_label.ellipsize = :end
        backend_label.add_css_class("dim-label")
        backend_label.margin_start = 10
        backend_label.margin_end = 10
        backend_label.margin_bottom = 8

        spacer = Gtk::Box.new(:vertical, 0)
        spacer.vexpand = true

        sidebar = Gtk::Box.new(:vertical, 0)
        sidebar.set_size_request(214, -1)
        sidebar.append(brand)
        sidebar.append(navigation)
        sidebar.append(spacer)
        sidebar.append(backend_label)
        sidebar.add_css_class("gdk-sidebar")
        select_page("home")
        sidebar
      end

      private def nav_button(
        page : String,
        label : String,
        icon : String,
      ) : Gtk::Button
        button = Gtk::Button.new
        image = Gtk::Image.new_from_icon_name(icon)
        text = Gtk::Label.new(label)
        text.xalign = 0_f32
        text.hexpand = true
        row = Gtk::Box.new(:horizontal, 10)
        row.append(image)
        row.append(text)
        button.child = row
        button.add_css_class("flat")
        button.add_css_class("gdk-nav")
        button.clicked_signal.connect { select_page(page) }
        @nav_buttons[page] = button
        button
      end

      private def select_page(page : String) : Nil
        @stack.visible_child_name = page
        @nav_buttons.each do |name, button|
          if name == page
            button.add_css_class("selected")
          else
            button.remove_css_class("selected")
          end
        end
      end

      private def build_pages : Nil
        @stack.add_named(build_home, "home")
        @stack.add_named(build_settings, "settings")
        @stack.add_named(build_diagnostics, "diagnostics")
      end

      private def build_home : Gtk::Widget
        icon = Gtk::Image.new_from_icon_name(APP_ID)
        icon.pixel_size = 72

        title = Gtk::Label.new("Minecraft Bedrock")
        title.xalign = 0_f32
        title.add_css_class("title-1")
        subtitle = Gtk::Label.new(
          "Windows GDK Edition · Proton · native Xbox multiplayer"
        )
        subtitle.xalign = 0_f32
        subtitle.add_css_class("dim-label")

        heading = Gtk::Box.new(:vertical, 3)
        heading.hexpand = true
        heading.append(title)
        heading.append(subtitle)

        hero_head = Gtk::Box.new(:horizontal, 16)
        hero_head.append(icon)
        hero_head.append(heading)

        actions = Gtk::Box.new(:horizontal, 8)
        actions.halign = :end
        actions.append(@spinner)
        actions.append(@cancel_button)
        actions.append(@uninstall_button)
        actions.append(@setup_button)
        actions.append(@play_button)

        footer = Gtk::Box.new(:horizontal, 12)
        footer.margin_top = 14
        footer.append(@status_label)
        @status_label.hexpand = true
        footer.append(actions)

        choices = Gtk::ListBox.new
        choices.selection_mode = :none
        choices.add_css_class("gdk-choices")
        choices.append(@session_row)
        choices.append(@version_row)
        @session_row.model = @session_model
        @version_row.model = @version_model

        hero = Gtk::Box.new(:vertical, 12)
        hero.append(hero_head)
        hero.append(choices)
        hero.append(@progress_bar)
        hero.append(footer)
        hero.add_css_class("gdk-card")
        hero.add_css_class("gdk-hero")

        log_title = Gtk::Label.new("ACTIVITY")
        log_title.xalign = 0_f32
        log_title.add_css_class("caption-heading")

        clear = Gtk::Button.new_with_label("Clear")
        clear.add_css_class("flat")
        clear.clicked_signal.connect do
          @pending_log_lines.clear
          @log_lines.clear
          @log_view.buffer.text = ""
        end

        log_header = Gtk::Box.new(:horizontal, 8)
        log_header.append(log_title)
        log_title.hexpand = true
        log_header.append(clear)

        log_scroll = Gtk::ScrolledWindow.new
        log_scroll.vexpand = true
        log_scroll.hscrollbar_policy = :never
        log_scroll.vscrollbar_policy = :automatic
        log_scroll.child = @log_view

        activity = Gtk::Box.new(:vertical, 8)
        activity.append(log_header)
        activity.append(log_scroll)
        activity.vexpand = true

        content = Gtk::Box.new(:vertical, 16)
        content.margin_top = 22
        content.margin_bottom = 22
        content.margin_start = 22
        content.margin_end = 22
        content.append(hero)
        content.append(activity)

        clamp = Adw::Clamp.new(
          child: content,
          maximum_size: 1050,
          tightening_threshold: 920
        )
        clamp
      end

      private def build_settings : Gtk::Widget
        page = Adw::PreferencesPage.new
        page.title = "Settings"

        general = Adw::PreferencesGroup.new
        general.title = "General"
        general.description =
          "Saved directly to this account profile."

        betas = switch_row(
          "Show preview versions",
          "Include Minecraft beta and preview builds.",
          "show_betas"
        )
        general.add(betas)

        confine = switch_row(
          "Confine pointer",
          "Keep mouse input inside Minecraft while playing.",
          "confine_cursor"
        )
        general.add(confine)

        diagnostics = switch_row(
          "Advanced diagnostics",
          "Enable detailed WineGDK and network logging.",
          "diagnostics"
        )
        general.add(diagnostics)

        renderer = Adw::SwitchRow.new
        renderer.title = "Legacy compatibility renderer"
        renderer.subtitle = "Use OpenGL instead of Vulkan."
        renderer.active = @settings.string("renderer", "auto") == "opengl"
        renderer.notify_signal["active"].connect do |_property|
          @settings.set(
            "renderer",
            renderer.active? ? "opengl" : "auto"
          )
        end
        general.add(renderer)
        page.add(general)

        runtime = Adw::PreferencesGroup.new
        runtime.title = "Runtime"

        input_model = Gtk::StringList.new([
          "Automatic",
          "X11",
          "Wayland (experimental)",
        ])
        input = Adw::ComboRow.new
        input.title = "Input backend"
        input.subtitle = "X11 is most compatible with WineGDK."
        runtime.add(input)
        input.model = input_model
        input.selected = case @settings.string("input_backend", "auto")
                         when "x11"     then 1_u32
                         when "wayland" then 2_u32
                         else                0_u32
                         end
        input.notify_signal["selected"].connect do |_property|
          value = ["auto", "x11", "wayland"][input.selected.to_i]? || "auto"
          @settings.set("input_backend", value)
        end
        custom_env = Adw::EntryRow.new
        custom_env.title = "Custom environment variables"
        custom_env.text = @settings.string("custom_env")
        custom_env.notify_signal["text"].connect do |_property|
          @settings.set("custom_env", custom_env.text)
        end
        runtime.add(custom_env)

        gamescope = Adw::EntryRow.new
        gamescope.title = "Gamescope arguments"
        gamescope.text = @settings.string("gamescope")
        gamescope.notify_signal["text"].connect do |_property|
          @settings.set("gamescope", gamescope.text)
        end
        runtime.add(gamescope)
        page.add(runtime)

        storage = Adw::PreferencesGroup.new
        storage.title = "Storage"
        data = Adw::ActionRow.new
        data.title = "Game files"
        data.subtitle = @paths.data_dir
        data.subtitle_lines = 3
        storage.add(data)
        page.add(storage)
        page
      end

      private def switch_row(
        title : String,
        subtitle : String,
        setting : String,
      ) : Adw::SwitchRow
        row = Adw::SwitchRow.new
        row.title = title
        row.subtitle = subtitle
        row.active = @settings.bool(setting)
        row.notify_signal["active"].connect do |_property|
          @settings.set(setting, row.active?)
          refresh_versions if setting == "show_betas"
        end
        row
      end

      private def build_diagnostics : Gtk::Widget
        page = Adw::PreferencesPage.new
        page.title = "Diagnostics"

        state = Adw::PreferencesGroup.new
        state.title = "Runtime"

        backend = Adw::ActionRow.new
        backend.title = "Game engine"
        backend.subtitle = @backend.label
        state.add(backend)

        storage = Adw::ActionRow.new
        storage.title = "Data directory"
        storage.subtitle = @paths.data_dir
        storage.subtitle_lines = 3
        state.add(storage)
        page.add(state)

        tools = Adw::PreferencesGroup.new
        tools.title = "Tools"
        tools.description =
          "Commands stream into Activity on the Home page."

        doctor = action_row(
          "Run system doctor",
          "Check GPU, Vulkan, WineGDK, UMU and host requirements.",
          "Run"
        ) { run_simple("System doctor", ["doctor"]) }
        tools.add(doctor)

        network = action_row(
          "Run network diagnostics",
          "Read-only Xbox and Minecraft connectivity checks.",
          "Run"
        ) { run_simple("Network diagnostics", ["doctor", "--network"]) }
        tools.add(network)

        update = action_row(
          "Update GDK runtime",
          "Check and install runtime updates.",
          "Check"
        ) { run_simple("Backend update", ["update"]) }
        tools.add(update)

        repair = action_row(
          "Reset Wine prefix",
          "Rebuild runtime prefix. Worlds and Minecraft files are preserved.",
          "Repair",
          destructive: true
        ) do
          Dialogs.confirm(
            @widget,
            "Reset Wine prefix?",
            "This removes the managed Wine prefix and rebuilds it on next " \
            "launch. Worlds and downloaded Minecraft versions remain.",
            "Reset prefix"
          ) { run_simple("Wine prefix repair", ["repair"]) }
        end
        tools.add(repair)
        page.add(tools)
        page
      end

      private def action_row(
        title : String,
        subtitle : String,
        label : String,
        destructive : Bool = false,
        &action : -> Nil
      ) : Adw::ActionRow
        row = Adw::ActionRow.new
        row.title = title
        row.subtitle = subtitle
        button = Gtk::Button.new_with_label(label)
        button.valign = :center
        button.add_css_class("destructive-action") if destructive
        button.clicked_signal.connect { action.call }
        row.add_suffix(button)
        row.activatable_widget = button
        row
      end

      private def version_selected : Nil
        return if @syncing_version
        entry = @versions[@version_row.selected.to_i]?
        return unless entry

        @settings.set("mc_version", entry.tag)
        refresh_install_state
      end

      private def session_selected : Nil
        return if @syncing_session
        session = @sessions[@session_row.selected.to_i]?
        return unless session

        @current_session = session
        environment = session.environment(ENV.to_h)
        @paths = Paths.new(
          environment: environment
        )
        @settings = Settings.for(@paths)
        sync_version_selection
        refresh_account
        refresh_install_state
        append_log("Account: #{session.name} · #{@paths.data_dir}")
      end

      private def refresh_versions : Nil
        return if @refreshing_versions || @job.running || !@backend.available?

        @refreshing_versions = true
        args = ["versions"]
        args << "--beta" if @settings.bool("show_betas")
        run_operation(
          "Loading Minecraft versions",
          args,
          ->(lines : Array(String), success : Bool) {
            @refreshing_versions = false
            if success
              versions = lines.compact_map { |line| VersionEntry.parse(line) }
              install_versions(versions)
            else
              install_versions([] of VersionEntry)
            end
          }
        )
      end

      private def install_versions(versions : Array(VersionEntry)) : Nil
        @versions = versions
        labels = versions.map(&.display)
        labels = ["No versions available"] if labels.empty?
        @version_model.splice(
          0_u32,
          @version_model.n_items,
          labels
        )
        sync_version_selection
        refresh_install_state
      end

      private def sync_version_selection : Nil
        @syncing_version = true
        selected = @versions.index do |entry|
          entry.tag == @settings.string("mc_version")
        end
        @version_row.selected = (selected || 0).to_u32
        @version_row.sensitive = !@versions.empty? && !@job.running
        @syncing_version = false
        version_selected unless @versions.empty? || selected
      end

      private def play : Nil
        unless @backend.available?
          Dialogs.error(
            @widget,
            "Game engine is not installed",
            "Reinstall Bedrock Linux GDK, then reopen this client."
          )
          return
        end

        version = selected_version
        unless version
          Dialogs.error(
            @widget,
            "Minecraft versions are still loading",
            "Wait for the version list, then press Play again."
          )
          return
        end

        unless version_installed?(version.tag)
          preflight_install(version, launch_after: true)
          return
        end

        unless AccountState.read(@paths).signed_in
          @status_label.text = "Sign in before playing."
          show_account_manager
          return
        end

        launch_current_session
      end

      private def launch_current_session : Nil
        session = @current_session
        if @launch_jobs[session.key]?.try(&.running)
          append_log("#{session.name} is already running.")
          return
        end

        job = ProcessJob.new
        @launch_jobs[session.key] = job
        append_log("› Launching Minecraft · #{session.name}")
        refresh_install_state
        environment = session.environment(HostEnvironment.values)
        command = @backend.command(["play"])

        job.start(
          command,
          ->(line : String) {
            GLib.idle_add do
              append_log("[#{session.name}] #{line}")
              false
            end
          },
          ->(exit_code : Int32?, error : String?) {
            GLib.idle_add do
              @launch_jobs.delete(session.key)
              success = exit_code == 0 && error.nil?
              if error
                append_log("[#{session.name}] error: #{error}")
              elsif success
                append_log("✓ #{session.name} game closed")
              else
                append_log(
                  "error: #{session.name} game failed" \
                  "#{exit_code ? " (#{exit_code})" : ""}"
                )
              end
              refresh_install_state if @current_session.key == session.key
              false
            end
          },
          environment
        )
      end

      private def setup : Nil
        version = selected_version
        unless version
          Dialogs.error(
            @widget,
            "Minecraft versions are still loading",
            "Wait for the version list, then try again."
          )
          return
        end

        preflight_install(version, launch_after: false)
      end

      private def uninstall : Nil
        version = selected_version
        return unless version
        if @launch_jobs.any? { |_key, job| job.running }
          Dialogs.error(
            @widget,
            "Minecraft is running",
            "Close every Minecraft window before uninstalling a version."
          )
          return
        end

        Dialogs.confirm(
          @widget,
          "Uninstall Minecraft #{version.tag}?",
          "Removes this shared game version for every account. Accounts, " \
          "worlds, settings, and Wine prefixes stay untouched.",
          "Uninstall"
        ) do
          run_operation(
            "Uninstalling Minecraft",
            ["uninstall", "--mc", version.tag],
            ->(_lines : Array(String), success : Bool) {
              refresh_install_state if success
            }
          )
        end
      end

      private def preflight_install(
        version : VersionEntry,
        launch_after : Bool,
      ) : Nil
        run_operation(
          "Checking system requirements",
          ["doctor"],
          ->(lines : Array(String), healthy : Bool) {
            if healthy
              run_operation(
                "Preparing Minecraft",
                ["setup", "--mc", version.tag],
                ->(_setup_lines : Array(String), installed : Bool) {
                  if installed
                    mark_version_installed(version.tag)
                    refresh_install_state
                    if launch_after
                      GLib.timeout(250.milliseconds) do
                        play
                        false
                      end
                    end
                  end
                }
              )
            else
              Dialogs.error(
                @widget,
                "System check failed",
                doctor_failure_message(lines)
              )
            end
          }
        )
      end

      private def doctor_failure_message(lines : Array(String)) : String
        details = lines.select do |line|
          normalized = line.downcase
          normalized.includes?("missing") ||
            normalized.includes?("install") ||
            normalized.includes?("failed") ||
            normalized.starts_with?("warn") ||
            normalized.starts_with?("error")
        end.last(6)

        return "Nothing was downloaded. Fix reported requirements, then try again." if details.empty?

        "Nothing was downloaded.\n\n#{details.join('\n')}"
      end

      private def selected_version : VersionEntry?
        @versions[@version_row.selected.to_i]?
      end

      private def version_installed?(version : String) : Bool
        File.directory?(File.join(@paths.games_dir, version)) &&
          File.file?(setup_marker(version))
      end

      private def setup_marker(version : String) : String
        File.join(@paths.data_dir, ".setup-complete-#{version}")
      end

      private def mark_version_installed(version : String) : Nil
        Dir.mkdir_p(@paths.data_dir, 0o700)
        File.write(setup_marker(version), "#{Time.utc}\n", perm: 0o600)
      rescue error : File::Error
        append_log("warn: could not write setup marker: #{error.message}")
      end

      private def start_sign_in(
        pending_profile : Bool = false,
        fallback_key : String = "default",
      ) : Nil
        state = AccountState.read(@paths)
        if state.signed_in
          append_log("Microsoft account already linked.")
          return
        end

        return if @job.running

        dialog, content, footer = panel_window(
          "Microsoft account",
          "Complete sign-in on Microsoft's official page.",
          560
        )

        status = Gtk::Label.new("Preparing secure sign-in…")
        status.xalign = 0_f32
        status.wrap = true
        status.add_css_class("title-3")

        hint = Gtk::Label.new(
          "Your browser opens with sign-in already prepared. Minecraft stays closed."
        )
        hint.xalign = 0_f32
        hint.wrap = true
        hint.add_css_class("dim-label")

        open = Gtk::Button.new_with_label("Open Microsoft sign-in again")
        open.add_css_class("suggested-action")
        open.sensitive = false
        sign_in_url = ""
        open.clicked_signal.connect do
          unless sign_in_url.empty? || HostLaunch.open_uri(sign_in_url)
            Dialogs.error(
              dialog,
              "Could not open browser",
              "Open #{sign_in_url} in your browser."
            )
          end
        end

        spinner = Gtk::Spinner.new
        spinner.start
        spinner.visible = true

        content.append(spinner)
        content.append(status)
        content.append(hint)
        content.append(open)

        cancel = Gtk::Button.new_with_label("Cancel")
        cancel.add_css_class("gdk-panel-action")
        cancelled = false
        cancel.clicked_signal.connect do
          cancelled = true
          cancel.label = "Cancelling…"
          cancel.sensitive = false
          @job.stop
          dialog.destroy
        end
        footer.append(cancel)
        dialog.destroy_signal.connect do
          if @job.running
            cancelled = true
            @job.stop
          end
        end

        session = @current_session
        environment = session.environment(HostEnvironment.values)
        command = @backend.command(["login"])
        failure_detail = ""
        append_log("› Microsoft sign-in · #{session.name}")
        set_busy(true, "Waiting for Microsoft sign-in")

        @job.start(
          command,
          ->(line : String) {
            GLib.idle_add do
              if line.starts_with?("device\t")
                parts = line.split('\t', 3)
                if parts.size == 3
                  sign_in_url = parts[1]
                  opened = sign_in_url.starts_with?("https://") &&
                           HostLaunch.open_uri(sign_in_url)
                  status.text = opened ? "Finish sign-in in your browser" : "Open Microsoft sign-in"
                  hint.text = if opened
                                "Sign-in page opened and ready."
                              else
                                "Could not open browser automatically. Use button below."
                              end
                  open.sensitive = sign_in_url.starts_with?("https://")
                  spinner.stop
                  spinner.visible = false
                end
              elsif !line.starts_with?("account\t")
                append_log(line)
                failure_detail = line if line.starts_with?("error")
              end
              false
            end
          },
          ->(exit_code : Int32?, error : String?) {
            success = exit_code == 0 && error.nil?
            GLib.idle_add do
              set_busy(false, success ? "Signed in" : "Microsoft sign-in failed")
              if success
                selected_key = finish_account_sign_in(session, pending_profile)
                reload_sessions(selected_key: selected_key)
                append_log("✓ Microsoft sign-in complete")
                dialog.destroy
              elsif cancelled
                discard_pending_profile(session, fallback_key) if pending_profile
                append_log("Microsoft sign-in cancelled.")
              else
                if pending_profile
                  discard_pending_profile(session, fallback_key)
                end
                dialog.destroy
                Dialogs.error(
                  @widget,
                  "Microsoft sign-in failed",
                  error ||
                  (failure_detail.empty? ? "Microsoft rejected or cancelled sign-in." : failure_detail)
                )
              end
              false
            end
          },
          environment
        )
        dialog.present
        PointerCursors.apply_all
      end

      private def show_account_manager : Nil
        normalize_account_profile_names
        dialog, content, footer = panel_window(
          "Microsoft accounts",
          "Each account owns one profile. Minecraft downloads stay shared.",
          680,
          500
        )

        list = Gtk::ListBox.new
        list.selection_mode = :none
        list.add_css_class("boxed-list")

        @sessions.each do |session|
          paths = Paths.new(
            environment: session.environment(ENV.to_h)
          )
          account = AccountState.read(paths)
          current = session.key == @current_session.key

          row = Adw::ActionRow.new
          row.title = account.gamertag || session.name
          row.subtitle = if account.signed_in
                           current ? "Current account" : "Microsoft account"
                         else
                           "Sign-in incomplete"
                         end

          folder = Gtk::Button.new_from_icon_name("folder-open-symbolic")
          folder.valign = :center
          folder.tooltip_text = "Open Minecraft game data"
          folder.add_css_class("flat")
          folder.clicked_signal.connect do
            game_data = paths.game_data_dir
            begin
              Dir.mkdir_p(game_data, 0o700)
            rescue error : File::Error
              Dialogs.error(
                dialog,
                "Could not create game-data folder",
                error.message || game_data
              )
              next
            end
            unless HostLaunch.open_path(game_data)
              Dialogs.error(
                dialog,
                "Could not open game-data folder",
                game_data
              )
            end
          end
          row.add_suffix(folder)

          action = Gtk::Button.new_with_label(
            if current && account.signed_in
              "Current"
            elsif account.signed_in
              "Use"
            else
              "Sign in"
            end
          )
          action.sensitive = !(current && account.signed_in)
          action.add_css_class("suggested-action") unless account.signed_in
          action.clicked_signal.connect do
            select_session(session.key)
            dialog.destroy
            start_sign_in unless account.signed_in
          end
          row.add_suffix(action)
          row.activatable_widget = action
          list.append(row)
        end

        scroller = Gtk::ScrolledWindow.new
        scroller.hscrollbar_policy = :never
        scroller.vscrollbar_policy = :automatic
        scroller.vexpand = true
        scroller.child = list
        content.append(scroller)

        add = Gtk::Button.new_with_label("Add account")
        add.add_css_class("suggested-action")
        add.clicked_signal.connect do
          begin
            fallback_key = @current_session.key
            previous_version = @settings.string("mc_version")
            session = @session_store.create_pending
            unless previous_version.empty?
              Settings.new(File.join(session.data_dir, "settings.json"))
                .set("mc_version", previous_version)
            end
            reload_sessions(selected_key: session.key)
            dialog.destroy
            start_sign_in(
              pending_profile: true,
              fallback_key: fallback_key
            )
          rescue error : ArgumentError | File::Error
            Dialogs.error(
              dialog,
              "Could not add account",
              error.message || error.class.name
            )
          end
        end
        footer.append(add)

        close = Gtk::Button.new_with_label("Close")
        close.add_css_class("gdk-panel-action")
        close.clicked_signal.connect { dialog.destroy }
        footer.append(close)

        dialog.present
        PointerCursors.apply_all
      end

      private def select_session(key : String) : Nil
        selected = @sessions.index(&.key.==(key))
        return unless selected

        if @session_row.selected == selected.to_u32
          session_selected
        else
          @session_row.selected = selected.to_u32
        end
      end

      private def reload_sessions(
        selected_key : String = @current_session.key,
      ) : Nil
        @sessions = @session_store.list
        @syncing_session = true
        @session_model.splice(
          0_u32,
          @session_model.n_items,
          @sessions.map(&.name)
        )
        selected = @sessions.index(&.key.==(selected_key)) || 0
        @session_row.selected = selected.to_u32
        @syncing_session = false
        session_selected
      end

      private def finish_account_sign_in(
        session : LaunchSession,
        pending_profile : Bool,
      ) : String
        paths = Paths.new(environment: session.environment(ENV.to_h))
        account = AccountState.read(paths)
        user_id = account.user_id
        name = account.gamertag
        raise "Microsoft account metadata is incomplete." unless user_id && name

        duplicate = @session_store.list.find do |candidate|
          next false if candidate.key == session.key
          candidate_paths = Paths.new(
            environment: candidate.environment(ENV.to_h)
          )
          AccountState.read(candidate_paths).user_id == user_id
        end
        if pending_profile && duplicate
          @session_store.delete_pending(session)
          append_log("Account #{name} already exists; using existing profile.")
          return duplicate.key
        end

        @session_store.rename(session, name)
        session.key
      rescue error : ArgumentError | File::Error | RuntimeError
        append_log("warn: could not finalize account profile: #{error.message}")
        session.key
      end

      private def discard_pending_profile(
        session : LaunchSession,
        fallback_key : String = "default",
      ) : Nil
        @session_store.delete_pending(session)
        reload_sessions(selected_key: fallback_key)
      rescue error : ArgumentError | File::Error
        append_log("warn: could not remove incomplete account: #{error.message}")
      end

      private def normalize_account_profile_names : Nil
        selected_key = @current_session.key
        changed = false
        @session_store.list.each do |session|
          paths = Paths.new(environment: session.environment(ENV.to_h))
          account = AccountState.read(paths)
          name = account.gamertag
          next unless account.signed_in && name
          next if session.name == name

          @session_store.rename(session, name)
          changed = true
        end
        reload_sessions(selected_key: selected_key) if changed
      rescue error : ArgumentError | File::Error
        append_log("warn: could not update account profile name: #{error.message}")
      end

      private def panel_window(
        title : String,
        description : String,
        width : Int32,
        height : Int32 = -1,
      ) : {Gtk::Window, Gtk::Box, Gtk::Box}
        heading = Gtk::Label.new(title)
        heading.xalign = 0_f32
        heading.add_css_class("title-3")

        subtitle = Gtk::Label.new(description)
        subtitle.xalign = 0_f32
        subtitle.wrap = true
        subtitle.add_css_class("dim-label")

        header = Gtk::Box.new(:vertical, 5)
        header.append(heading)
        header.append(subtitle)
        header.add_css_class("gdk-panel-bar")
        header.add_css_class("gdk-panel-head")

        content = Gtk::Box.new(:vertical, 14)
        content.margin_top = 20
        content.margin_bottom = 20
        content.margin_start = 20
        content.margin_end = 20
        content.vexpand = true

        footer = Gtk::Box.new(:horizontal, 10)
        spacer = Gtk::Box.new(:horizontal, 0)
        spacer.hexpand = true
        footer.append(spacer)
        footer.add_css_class("gdk-panel-bar")
        footer.add_css_class("gdk-panel-foot")

        root = Gtk::Box.new(:vertical, 0)
        root.append(header)
        root.append(content)
        root.append(footer)

        window = Gtk::Window.new
        window.title = title
        window.transient_for = @widget
        window.application = @widget.application
        window.destroy_with_parent = true
        window.modal = true
        window.decorated = false
        window.resizable = false
        window.set_default_size(width, height)
        window.add_css_class("gdk-panel")
        window.child = root
        window.close_request_signal.connect do
          window.destroy
          true
        end

        keys = Gtk::EventControllerKey.new
        keys.propagation_phase = :capture
        keys.key_pressed_signal.connect do |keyval, _keycode, _state|
          if keyval == Gdk::KEY_Escape
            window.destroy
            true
          else
            false
          end
        end
        window.add_controller(keys)
        {window, content, footer}
      end

      private def run_simple(label : String, args : Array(String)) : Nil
        run_operation(
          label,
          args,
          ->(_lines : Array(String), _success : Bool) {
            refresh_account
            refresh_install_state
          }
        )
      end

      private def run_operation(
        label : String,
        arguments : Array(String),
        after : Proc(Array(String), Bool, Nil)? = nil,
      ) : Nil
        unless @backend.available?
          Dialogs.error(
            @widget,
            "Game engine is not installed",
            "Reinstall Bedrock Linux GDK, then reopen this client."
          )
          return
        end
        return if @job.running

        session = @current_session
        environment = session.environment(HostEnvironment.values)
        command = @backend.command(arguments)
        lines = [] of String
        @operation_cancelled = false
        append_log("› #{label} · #{session.name}")
        set_busy(true, label)

        @job.start(
          command,
          ->(line : String) {
            if line.starts_with?("progress\t")
              GLib.idle_add do
                update_progress(line)
                false
              end
            else
              lines << line
              GLib.idle_add do
                append_log(line)
                false
              end
            end
          },
          ->(exit_code : Int32?, error : String?) {
            cancelled = @operation_cancelled
            success = !cancelled && exit_code == 0 && error.nil?
            GLib.idle_add do
              if cancelled
                append_log("Cancelled #{label.downcase}.")
              elsif error
                append_log("error: #{error}")
              elsif success
                append_log("✓ #{label} complete")
              else
                append_log(
                  "error: #{label} failed" \
                  "#{exit_code ? " (#{exit_code})" : ""}"
                )
              end
              status = if cancelled
                         "Cancelled"
                       elsif success
                         "Ready"
                       else
                         "#{label} failed"
                       end
              set_busy(false, status)
              after.try(&.call(lines, success)) unless cancelled
              @operation_cancelled = false
              false
            end
          },
          environment
        )
      end

      private def set_busy(busy : Bool, status : String) : Nil
        session_running = @launch_jobs[@current_session.key]?.try(&.running) ||
                          false
        @play_button.sensitive =
          !busy && !session_running && @backend.available?
        @setup_button.sensitive =
          !busy && !session_running && @backend.available?
        @uninstall_button.sensitive =
          !busy && @launch_jobs.none? { |_key, job| job.running } &&
            @backend.available?
        @version_row.sensitive = !busy && !@versions.empty?
        @session_row.sensitive = !busy
        @cancel_button.visible = busy
        @cancel_button.label = "Cancel"
        @cancel_button.sensitive = busy
        @spinner.visible = busy
        busy ? @spinner.start : @spinner.stop
        @progress_bar.visible = busy
        if busy
          @progress_bar.fraction = 0.0
          @progress_bar.text = status
          @progress_indeterminate = true
          start_progress_pulse
        else
          @progress_indeterminate = false
          stop_progress_pulse
        end
        @status_label.text = status
      end

      private def cancel_operation : Nil
        return unless @job.running

        @operation_cancelled = true
        return unless @job.stop

        @cancel_button.label = "Cancelling…"
        @cancel_button.sensitive = false
        @status_label.text = "Cancelling…"
        @progress_bar.text = "Cancelling…"
        @progress_indeterminate = true
      end

      private def update_progress(line : String) : Nil
        parts = line.split('\t', 3)
        return unless parts.size == 3
        fraction = parts[1].to_f64?
        return unless fraction

        if fraction < 0
          @progress_bar.text = parts[2]
          @progress_indeterminate = true
          @progress_bar.pulse
          start_progress_pulse
        else
          percent = (fraction.clamp(0.0, 1.0) * 100).round.to_i
          @progress_bar.text = "#{parts[2]} · #{percent}%"
          @progress_indeterminate = false
          @progress_bar.fraction = fraction.clamp(0.0, 1.0)
          stop_progress_pulse
        end
      end

      private def append_log(line : String) : Nil
        clean = line.strip
        return if clean.empty?

        @pending_log_lines << clean
        return if @log_flush_scheduled

        @log_flush_scheduled = true
        GLib.timeout(50.milliseconds) do
          flush_logs
          false
        end
      end

      private def flush_logs : Nil
        pending = @pending_log_lines.dup
        @pending_log_lines.clear
        @log_flush_scheduled = false
        return if pending.empty?

        @log_lines.concat(pending)
        trimmed = false
        while @log_lines.size > 500
          @log_lines.shift
          trimmed = true
        end
        buffer = @log_view.buffer
        if trimmed
          buffer.text = @log_lines.join('\n')
        else
          batch = pending.join('\n')
          text = buffer.char_count.zero? ? batch : "\n#{batch}"
          buffer.insert(buffer.end_iter, text, -1)
        end
        buffer.place_cursor(buffer.end_iter)
        @log_view.scroll_mark_onscreen(buffer.insert)
      end

      private def start_progress_pulse : Nil
        return unless @progress_pulse_id.zero?

        @progress_pulse_id = GLib.timeout(160.milliseconds) do
          if @progress_bar.visible? && @progress_indeterminate
            @progress_bar.pulse
            true
          else
            @progress_pulse_id = 0_u32
            false
          end
        end
      end

      private def stop_progress_pulse : Nil
        return if @progress_pulse_id.zero?

        GLib.source_remove(@progress_pulse_id)
        @progress_pulse_id = 0_u32
      end

      private def refresh_account : Nil
        account = AccountState.read(@paths)
        @account_button.label = if account.signed_in
                                  account.gamertag || "Signed in"
                                else
                                  "Sign in"
                                end
        if account.signed_in
          @account_button.add_css_class("gdk-success")
        else
          @account_button.remove_css_class("gdk-success")
        end
      end

      private def refresh_install_state : Nil
        version = @settings.string("mc_version")
        game_available = !version.empty? &&
                         File.directory?(File.join(@paths.games_dir, version))
        installed = !version.empty? && version_installed?(version)
        running = @launch_jobs[@current_session.key]?.try(&.running) || false
        @play_button.label = running ? "Running" : "Play"
        @play_button.sensitive =
          !@job.running && !running && @backend.available?
        @setup_button.sensitive =
          !@job.running && !running && @backend.available?
        @uninstall_button.visible = game_available
        @uninstall_button.sensitive =
          !@job.running && @launch_jobs.none? { |_key, job| job.running } &&
            @backend.available?
        @setup_button.label = if installed
                                "Verify / Update"
                              elsif game_available
                                "Prepare account"
                              else
                                "Install / Update"
                              end
        unless @job.running
          @status_label.text = if running
                                 "#{@current_session.name} running"
                               elsif version.empty?
                                 "Select a version to play."
                               elsif installed
                                 "#{version} installed"
                               elsif game_available
                                 "#{version} shared · account needs preparation"
                               else
                                 "#{version} will install on first launch"
                               end
        end
      end

      private def set_backend_state : Nil
        enabled = @backend.available?
        @play_button.sensitive = enabled
        @setup_button.sensitive = enabled
        if enabled
          append_log("Backend: #{@backend.label}")
          append_log("Data: #{@paths.data_dir}")
        else
          @status_label.text = "Game engine not found"
          append_log("error: game engine not found")
        end
      end
    end
  end
end
