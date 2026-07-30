require "gtk4"
require "../version"
require "./adw"
require "./style"
require "./window"

module BedrockLinuxGdk
  module UI
    extend self

    def run : Int32
      application = Adw::Application.new(
        APP_ID,
        Gio::ApplicationFlags::NonUnique
      )
      window : Window? = nil

      application.activate_signal.connect do
        begin
          application.style_manager.color_scheme =
            Adw::ColorScheme::ForceDark
          install_style
          window ||= Window.new(application)
          window.not_nil!.present
        rescue error
          show_startup_error(application, error)
        end
      end

      # GTK owns the main loop. Yield briefly so Crystal fibers can stream
      # backend output without adding a second event-loop model.
      GLib.timeout(10.milliseconds) do
        Fiber.yield
        true
      end

      application.run
    end

    private def install_style : Nil
      display = Gdk::Display.default
      return unless display

      provider = Gtk::CssProvider.new
      provider.load_from_string(STYLE)
      Gtk::StyleContext.add_provider_for_display(
        display,
        provider,
        (Gtk::STYLE_PROVIDER_PRIORITY_USER + 1).to_u32
      )
    end

    private def show_startup_error(
      application : Gtk::Application,
      error : Exception,
    ) : Nil
      window = Gtk::ApplicationWindow.new(application)
      window.title = APP_NAME
      window.set_default_size(620, 220)
      label = Gtk::Label.new(
        "#{APP_NAME} could not start\n\n" \
        "#{error.message || error.class.name}"
      )
      label.wrap = true
      label.margin_top = 28
      label.margin_bottom = 28
      label.margin_start = 28
      label.margin_end = 28
      window.child = label
      window.present
    end
  end
end
