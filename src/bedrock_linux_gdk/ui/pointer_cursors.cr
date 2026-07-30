require "gtk4"

module BedrockLinuxGdk
  module UI
    module PointerCursors
      extend self

      def apply(widget : Gtk::Widget) : Nil
        widget.cursor_from_name = "pointer" if widget.is_a?(Gtk::Button)

        child = widget.first_child
        while child
          apply(child)
          child = child.next_sibling
        end
      end

      def apply_all : Nil
        Gtk::Window.list_toplevels.each { |widget| apply(widget) }
      end
    end
  end
end
