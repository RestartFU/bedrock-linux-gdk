require "gtk4"
require "./adw"

module BedrockLinuxGdk
  module UI
    module Dialogs
      extend self

      def error(parent : Gtk::Window, heading : String, body : String) : Nil
        dialog = Adw::AlertDialog.new(heading: heading, body: body)
        dialog.add_response("close", "Close")
        dialog.default_response = "close"
        dialog.close_response = "close"
        dialog.present(parent)
      end

      def confirm(
        parent : Gtk::Window,
        heading : String,
        body : String,
        accept : String,
        &on_accept : -> Nil
      ) : Nil
        dialog = Adw::AlertDialog.new(heading: heading, body: body)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("accept", accept)
        dialog.set_response_appearance("accept", :destructive)
        dialog.default_response = "cancel"
        dialog.close_response = "cancel"
        dialog.choose(parent, nil) do |_source, result|
          on_accept.call if dialog.choose_finish(result) == "accept"
        end
      end
    end
  end
end
