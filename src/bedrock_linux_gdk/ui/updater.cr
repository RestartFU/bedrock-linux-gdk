require "gtk4"
require "../host_environment"
require "../update_channel"
require "../version"

module BedrockLinuxGdk
  module UI
    class Updater
      FIRST_CHECK = 6.seconds
      POLL        = 10.minutes

      getter widget : Gtk::Button

      private enum State
        Quiet
        Checking
        Available
        Failed
      end

      def initialize(
        @parent : Gtk::Window,
        @on_log : Proc(String, Nil),
      )
        @state = State::Quiet
        @closed = false
        @check_id = 0_u32

        @widget = Gtk::Button.new_from_icon_name("view-refresh-symbolic")
        @widget.add_css_class("flat")
        @widget.tooltip_text = "Check for client updates"
        @widget.clicked_signal.connect { clicked }

        schedule
      end

      def close : Nil
        @closed = true
        GLib.source_remove(@check_id) unless @check_id == 0
        @check_id = 0_u32
      end

      private def schedule : Nil
        @check_id = GLib.timeout(FIRST_CHECK) do
          check(silent: true)
          @check_id = GLib.timeout(POLL) do
            check(silent: true)
            !@closed
          end
          false
        end
      end

      private def clicked : Nil
        if @state.available?
          install
        else
          check(silent: false)
        end
      end

      private def check(silent : Bool) : Nil
        return if @closed || @state.checking?

        @state = State::Checking
        @widget.sensitive = false
        @widget.tooltip_text = "Checking for updates…"
        @on_log.call("Checking for client updates…") unless silent

        spawn do
          output = IO::Memory.new
          status = Process.run(
            "curl",
            [
              "-fsSL",
              "--max-time", "20",
              "-H", "Accept: application/vnd.github+json",
              UpdateChannel.check_url,
            ],
            env: HostEnvironment.values,
            clear_env: true,
            input: Process::Redirect::Close,
            output: output,
            error: Process::Redirect::Close
          )
          latest = status.success? ? UpdateChannel.latest_from_reply(output.to_s) : nil
          GLib.idle_add do
            if !@closed && UpdateChannel.newer?(latest)
              set_available
              @on_log.call("Client update available.")
            else
              set_quiet
              @on_log.call("Client is up to date.") unless silent
            end
            false
          end
        rescue error : File::Error | IO::Error
          GLib.idle_add do
            unless @closed
              @state = State::Failed
              @widget.sensitive = true
              @widget.tooltip_text =
                error.message || "Update check failed"
              @on_log.call("Client update check failed.") unless silent
            end
            false
          end
        end
      end

      private def set_available : Nil
        @state = State::Available
        @widget.icon_name = "document-save-symbolic"
        @widget.add_css_class("suggested-action")
        @widget.sensitive = true
        @widget.tooltip_text = "Update available — click to install"
      end

      private def set_quiet : Nil
        @state = State::Quiet
        @widget.icon_name = "view-refresh-symbolic"
        @widget.remove_css_class("suggested-action")
        @widget.sensitive = true
        @widget.tooltip_text = "Check for client updates"
      end

      private def install : Nil
        unless installed_bundle?
          @on_log.call(
            "Update requires one-line installer or installed bundle."
          )
          return
        end

        @on_log.call("Installing client update after shutdown…")
        Process.new(
          ["sh", "-c", UpdateChannel.install_command],
          env: HostEnvironment.values,
          clear_env: true,
          input: Process::Redirect::Close,
          output: Process::Redirect::Close,
          error: Process::Redirect::Close
        )
        @parent.application.try(&.quit)
      rescue error : File::Error | IO::Error
        @on_log.call(
          "Could not start updater: #{error.message || error.class.name}"
        )
      end

      private def installed_bundle? : Bool
        executable = Process.executable_path
        return false unless executable

        expected = File.join(
          Path.home.to_s,
          ".local",
          "opt",
          INSTALL_NAME,
          "bin",
          "bedrock-linux-gdk"
        )
        File.realpath(executable) == File.realpath(expected)
      rescue File::Error
        false
      end
    end
  end
end
