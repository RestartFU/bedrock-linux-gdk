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
require "./pointer_cursors"
require "./updater"

module BedrockLinuxGdk
  module UI
    class Window
      getter widget : Adw::ApplicationWindow

      @versions = [] of VersionEntry
      @log_lines = [] of String
      @job = ProcessJob.new
      @launch_jobs = {} of String => ProcessJob
      @refreshing_versions = false
      @syncing_version = false
      @syncing_session = false
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
        @version_row.add_css_class("bol-version")
        @version_row.notify_signal["selected"].connect do |_property|
          version_selected
        end

        @session_model = Gtk::StringList.new(@sessions.map(&.name))
        @session_row = Adw::ComboRow.new
        @session_row.title = "Session"
        @session_row.subtitle = "Independent account, worlds and game files"
        @session_row.add_css_class("bol-version")
        @session_row.notify_signal["selected"].connect do |_property|
          session_selected
        end

        @play_button = Gtk::Button.new_with_label("Play")
        @play_button.add_css_class("suggested-action")
        @play_button.clicked_signal.connect { play }

        @setup_button = Gtk::Button.new_with_label("Install / Update")
        @setup_button.clicked_signal.connect { setup }

        @cancel_button = Gtk::Button.new_with_label("Cancel")
        @cancel_button.add_css_class("destructive-action")
        @cancel_button.visible = false
        @cancel_button.clicked_signal.connect { @job.stop }

        @status_label = Gtk::Label.new("")
        @status_label.xalign = 0_f32
        @status_label.add_css_class("bol-status")

        @spinner = Gtk::Spinner.new
        @spinner.visible = false

        @log_view = Gtk::TextView.new
        @log_view.editable = false
        @log_view.cursor_visible = false
        @log_view.monospace = true
        @log_view.wrap_mode = :word_char
        @log_view.add_css_class("bol-log")

        @account_button = Gtk::Button.new_with_label("Sign in")
        @account_button.add_css_class("flat")
        @account_button.add_css_class("bol-account")
        @account_button.clicked_signal.connect { show_account_manager }

        @session_entry = Gtk::Entry.new
        @sessions_output = Gtk::Label.new("")

        build_pages
        @updater = Updater.new(@widget, ->(line : String) { append_log(line) })
        @widget.content = build_shell
        PointerCursors.apply(@widget)
        @widget.close_request_signal.connect do
          @updater.close
          false
        end

        refresh_account
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
        toolbar.add_css_class("bol-content")

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
        brand.add_css_class("bol-brand")

        navigation = Gtk::Box.new(:vertical, 4)
        navigation.append(nav_button("home", "Home", "go-home-symbolic"))
        navigation.append(
          nav_button("sessions", "Sessions", "system-users-symbolic")
        )
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
        sidebar.add_css_class("bol-sidebar")
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
        button.add_css_class("bol-nav")
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
        @stack.add_named(build_sessions, "sessions")
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
        actions.append(@setup_button)
        actions.append(@play_button)

        footer = Gtk::Box.new(:horizontal, 12)
        footer.margin_top = 14
        footer.append(@status_label)
        @status_label.hexpand = true
        footer.append(actions)

        choices = Gtk::ListBox.new
        choices.selection_mode = :none
        choices.add_css_class("bol-choices")
        choices.append(@session_row)
        choices.append(@version_row)
        @session_row.model = @session_model
        @version_row.model = @version_model

        hero = Gtk::Box.new(:vertical, 12)
        hero.append(hero_head)
        hero.append(choices)
        hero.append(footer)
        hero.add_css_class("bol-card")
        hero.add_css_class("bol-hero")

        log_title = Gtk::Label.new("ACTIVITY")
        log_title.xalign = 0_f32
        log_title.add_css_class("caption-heading")

        clear = Gtk::Button.new_with_label("Clear")
        clear.add_css_class("flat")
        clear.clicked_signal.connect do
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
          "Saved directly to this session's GDK settings file."

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

      private def build_sessions : Gtk::Widget
        title = Gtk::Label.new("Concurrent sessions")
        title.xalign = 0_f32
        title.add_css_class("title-1")

        description = Gtk::Label.new(
          "Each session has its own account, Wine prefix, worlds and game " \
          "files, so sessions can run simultaneously. Expect several " \
          "gigabytes per session."
        )
        description.xalign = 0_f32
        description.wrap = true
        description.add_css_class("dim-label")

        @session_entry.placeholder_text = "Session name"
        @session_entry.hexpand = true
        @session_entry.activate_signal.connect { create_session }

        create = Gtk::Button.new_with_label("Create session")
        create.add_css_class("suggested-action")
        create.clicked_signal.connect { create_session }

        form = Gtk::Box.new(:horizontal, 8)
        form.append(@session_entry)
        form.append(create)

        @sessions_output.xalign = 0_f32
        @sessions_output.yalign = 0_f32
        @sessions_output.wrap = true
        @sessions_output.selectable = true
        @sessions_output.add_css_class("bol-status")

        refresh = Gtk::Button.new_with_label("Refresh")
        refresh.halign = :start
        refresh.clicked_signal.connect { refresh_sessions }

        card = Gtk::Box.new(:vertical, 12)
        card.append(title)
        card.append(description)
        card.append(form)
        card.append(@sessions_output)
        card.append(refresh)
        card.add_css_class("bol-card")

        content = Gtk::Box.new(:vertical, 16)
        content.margin_top = 24
        content.margin_bottom = 24
        content.margin_start = 24
        content.margin_end = 24
        content.append(card)

        clamp = Adw::Clamp.new(
          child: content,
          maximum_size: 860,
          tightening_threshold: 760
        )
        refresh_sessions
        clamp
      end

      private def build_diagnostics : Gtk::Widget
        page = Adw::PreferencesPage.new
        page.title = "Diagnostics"

        state = Adw::PreferencesGroup.new
        state.title = "Runtime"

        backend = Adw::ActionRow.new
        backend.title = "GDK runtime"
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
        refresh_sessions
        append_log("Session: #{session.name} · #{@paths.data_dir}")
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
            "GDK runtime is not installed",
            "Install a compatible GDK runtime, then reopen this client."
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

        unless AccountState.read(@paths).signed_in
          @status_label.text = "Sign in before installing or playing."
          show_account_manager
          return
        end

        unless version_installed?(version.tag)
          preflight_install(version, launch_after: true)
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
        refresh_sessions
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
              refresh_sessions
              success = exit_code == 0 && error.nil?
              if error
                append_log("[#{session.name}] error: #{error}")
              elsif success
                append_log("✓ #{session.name} session ended")
              else
                append_log(
                  "error: #{session.name} session failed" \
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

        unless AccountState.read(@paths).signed_in
          @status_label.text = "Sign in before installing Minecraft."
          show_account_manager
          return
        end

        preflight_install(version, launch_after: false)
      end

      private def preflight_install(
        version : VersionEntry,
        launch_after : Bool,
      ) : Nil
        run_operation(
          "Checking system requirements",
          ["doctor"],
          ->(_lines : Array(String), healthy : Bool) {
            if healthy
              run_operation(
                "Installing Minecraft",
                ["setup", "--mc", version.tag],
                ->(_setup_lines : Array(String), installed : Bool) {
                  if installed
                    mark_version_installed(version.tag)
                    refresh_install_state
                    launch_current_session if launch_after
                  end
                }
              )
            else
              Dialogs.error(
                @widget,
                "System check failed",
                "Nothing was downloaded. Fix the reported requirements, " \
                "then try again."
              )
            end
          }
        )
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

      private def start_sign_in : Nil
        state = AccountState.read(@paths)
        if state.signed_in
          append_log("Microsoft account already linked.")
          return
        end
        run_operation(
          "Microsoft sign-in",
          ["login"],
          ->(_lines : Array(String), _success : Bool) {
            refresh_account
          }
        )
      end

      private def show_account_manager : Nil
        dialog = Adw::Dialog.new(
          title: "Accounts",
          content_width: 560,
          content_height: 520
        )

        header = Adw::HeaderBar.new
        header.title_widget = Adw::WindowTitle.new(
          title: "Accounts",
          subtitle: "Independent Microsoft account profiles"
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
          row.title = session.name
          row.subtitle = if account.signed_in
                           account.gamertag || "Microsoft account linked"
                         else
                           "Not signed in"
                         end

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
            dialog.close
            start_sign_in unless account.signed_in
          end
          row.add_suffix(action)
          row.activatable_widget = action
          list.append(row)
        end

        account_name = Gtk::Entry.new
        account_name.placeholder_text = "New account profile name"
        account_name.hexpand = true

        add = Gtk::Button.new_with_label("Add & Sign in")
        add.add_css_class("suggested-action")
        add.clicked_signal.connect do
          name = account_name.text.strip
          unless name.empty?
            begin
              previous_version = @settings.string("mc_version")
              session = @session_store.create(name)
              unless previous_version.empty?
                Settings.new(File.join(session.data_dir, "settings.json"))
                  .set("mc_version", previous_version)
              end
              reload_sessions(selected_key: session.key)
              dialog.close
              start_sign_in
            rescue error : ArgumentError | File::Error
              Dialogs.error(
                @widget,
                "Could not add account",
                error.message || error.class.name
              )
            end
          end
        end

        add_row = Gtk::Box.new(:horizontal, 8)
        add_row.append(account_name)
        add_row.append(add)

        note = Gtk::Label.new(
          "Each account profile keeps separate credentials, worlds, game " \
          "files and Wine prefix."
        )
        note.wrap = true
        note.xalign = 0_f32
        note.add_css_class("dim-label")

        content = Gtk::Box.new(:vertical, 16)
        content.margin_top = 18
        content.margin_bottom = 18
        content.margin_start = 18
        content.margin_end = 18
        content.append(list)
        content.append(add_row)
        content.append(note)

        scroller = Gtk::ScrolledWindow.new
        scroller.hscrollbar_policy = :never
        scroller.vscrollbar_policy = :automatic
        scroller.child = content

        toolbar = Adw::ToolbarView.new
        toolbar.add_top_bar(header)
        toolbar.content = scroller
        dialog.child = toolbar
        dialog.present(@widget)

        GLib.idle_add do
          PointerCursors.apply_all
          false
        end
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

      private def create_session : Nil
        name = @session_entry.text.strip
        return if name.empty?

        previous_version = @settings.string("mc_version")
        session = @session_store.create(name)
        unless previous_version.empty?
          Settings.new(File.join(session.data_dir, "settings.json"))
            .set("mc_version", previous_version)
        end
        @session_entry.text = ""
        reload_sessions(selected_key: session.key)
        select_page("home")
        append_log(
          "Created independent session #{session.name}. Install its game " \
          "files before first play."
        )
      rescue error : ArgumentError | File::Error
        Dialogs.error(
          @widget,
          "Could not create session",
          error.message || error.class.name
        )
      end

      private def refresh_sessions : Nil
        lines = @sessions.map do |session|
          running = @launch_jobs[session.key]?.try(&.running) ? " · running" : ""
          "#{session.name}#{running}\n#{session.data_dir}"
        end
        @sessions_output.text = lines.join("\n\n")
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
            "GDK runtime is not installed",
            "Install a compatible GDK runtime, then reopen this client."
          )
          return
        end
        return if @job.running

        session = @current_session
        environment = session.environment(HostEnvironment.values)
        command = @backend.command(arguments)
        lines = [] of String
        append_log("› #{label} · #{session.name}")
        set_busy(true, label)

        @job.start(
          command,
          ->(line : String) {
            lines << line
            GLib.idle_add do
              append_log(line)
              false
            end
          },
          ->(exit_code : Int32?, error : String?) {
            success = exit_code == 0 && error.nil?
            GLib.idle_add do
              if error
                append_log("error: #{error}")
              elsif success
                append_log("✓ #{label} complete")
              else
                append_log(
                  "error: #{label} failed" \
                  "#{exit_code ? " (#{exit_code})" : ""}"
                )
              end
              set_busy(false, success ? "Ready" : "#{label} failed")
              after.try(&.call(lines, success))
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
        @version_row.sensitive = !busy && !@versions.empty?
        @session_row.sensitive = !busy
        @cancel_button.visible = busy
        @spinner.visible = busy
        busy ? @spinner.start : @spinner.stop
        @status_label.text = status
      end

      private def append_log(line : String) : Nil
        clean = line.strip
        return if clean.empty?

        @log_lines << clean
        while @log_lines.size > 500
          @log_lines.shift
        end
        @log_view.buffer.text = @log_lines.join('\n')
      end

      private def refresh_account : Nil
        account = AccountState.read(@paths)
        @account_button.label = if account.signed_in
                                  account.gamertag || "Signed in"
                                else
                                  "Sign in"
                                end
        if account.signed_in
          @account_button.add_css_class("bol-success")
        else
          @account_button.remove_css_class("bol-success")
        end
      end

      private def refresh_install_state : Nil
        version = @settings.string("mc_version")
        installed = !version.empty? && version_installed?(version)
        running = @launch_jobs[@current_session.key]?.try(&.running) || false
        @play_button.label = running ? "Running" : "Play"
        @play_button.sensitive =
          !@job.running && !running && @backend.available?
        @setup_button.sensitive =
          !@job.running && !running && @backend.available?
        @setup_button.label = installed ? "Reinstall" : "Install / Update"
        unless @job.running
          @status_label.text = if running
                                 "#{@current_session.name} running"
                               elsif version.empty?
                                 "Select a version to play."
                               elsif installed
                                 "#{version} installed"
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
          @status_label.text = "GDK runtime not found"
          append_log("error: GDK runtime not found")
        end
      end
    end
  end
end
