module BedrockLinuxGdk
  module X11WindowFix
    extend self

    TARGET_CLASS = "minecraft.windows.exe"
    UMU_CLASS = "steam_app_default"
    TARGET_TITLE = "Minecraft"

    record Geometry,
      x : Int32,
      y : Int32,
      width : UInt32,
      height : UInt32

    record Correction,
      x : Int32,
      y : Int32,
      width : UInt32,
      height : UInt32

    def correction(
      screen_width : Int32,
      screen_height : Int32,
      geometry : Geometry,
    ) : Correction?
      return if screen_width <= 0 || screen_height <= 0
      return if geometry.width < screen_width || geometry.height < screen_height

      Correction.new(
        -4,
        -30,
        (screen_width + 6).to_u32,
        (screen_height + 30).to_u32
      )
    end

    def registry_commands(width : Int32, height : Int32) : Array(Array(String))
      size = "#{width}x#{height}"
      [
        [
          "reg.exe", "add", "HKCU\\Software\\Wine\\Explorer",
          "/v", "Desktop", "/t", "REG_SZ", "/d", "Default", "/f",
        ],
        [
          "reg.exe", "add", "HKCU\\Software\\Wine\\Explorer\\Desktops",
          "/v", "Default", "/t", "REG_SZ", "/d", size, "/f",
        ],
      ]
    end

    def target_identity?(name : String, klass : String, title : String) : Bool
      normalized_name = name.downcase
      normalized_class = klass.downcase
      return true if normalized_name == TARGET_CLASS || normalized_class == TARGET_CLASS

      title == TARGET_TITLE &&
        (normalized_name == UMU_CLASS || normalized_class == UMU_CLASS)
    end

    def open : Session?
      Session.open
    end

    class Session
      ERROR_HANDLER = ->(_display : LibX11::Display*, _event : Void*) { 0 }

      @display : LibX11::Display*
      getter screen_width : Int32
      getter screen_height : Int32

      private def initialize(
        @display : LibX11::Display*,
        @screen_width : Int32,
        @screen_height : Int32,
      )
      end

      def self.open : self?
        # Minecraft recreates its Wine desktop child while loading. Ignore
        # BadWindow races from windows that vanish between XQueryTree calls.
        LibX11.set_error_handler(ERROR_HANDLER)
        display = LibX11.open_display(nil)
        return if display.null?

        screen = LibX11.default_screen(display)
        width = LibX11.display_width(display, screen)
        height = LibX11.display_height(display, screen)
        if width <= 0 || height <= 0
          LibX11.close_display(display)
          return
        end
        new(display, width, height)
      rescue
        LibX11.close_display(display) if display && !display.null?
        nil
      end

      def apply : Nil
        root = LibX11.default_root_window(@display)
        scan(root)
        LibX11.flush(@display)
      rescue
      end

      def close : Nil
        display = @display
        return if display.null?
        @display = Pointer(Void).null.as(LibX11::Display*)
        LibX11.close_display(display)
      rescue
      end

      private def scan(window : LibX11::Window) : Nil
        fix(window) if target?(window)

        root = uninitialized LibX11::Window
        parent = uninitialized LibX11::Window
        children = Pointer(LibX11::Window).null
        count = 0_u32
        return unless LibX11.query_tree(
                        @display,
                        window,
                        pointerof(root),
                        pointerof(parent),
                        pointerof(children),
                        pointerof(count)
                      ) != 0

        count.times { |index| scan(children[index]) }
        LibX11.free(children.as(Void*)) unless children.null?
      end

      private def target?(window : LibX11::Window) : Bool
        hint = uninitialized LibX11::ClassHint
        return false if LibX11.get_class_hint(@display, window, pointerof(hint)) == 0

        name = hint.res_name.null? ? "" : String.new(hint.res_name)
        klass = hint.res_class.null? ? "" : String.new(hint.res_class)
        title = window_title(window)
        matches = X11WindowFix.target_identity?(name, klass, title)
        LibX11.free(hint.res_name.as(Void*)) unless hint.res_name.null?
        LibX11.free(hint.res_class.as(Void*)) unless hint.res_class.null?
        matches
      end

      private def window_title(window : LibX11::Window) : String
        title = Pointer(UInt8).null
        status = LibX11.fetch_name(@display, window, pointerof(title))
        value = status == 0 || title.null? ? "" : String.new(title)
        LibX11.free(title.as(Void*)) unless title.null?
        value
      end

      private def fix(window : LibX11::Window) : Nil
        root = uninitialized LibX11::Window
        x = 0
        y = 0
        width = 0_u32
        height = 0_u32
        border = 0_u32
        depth = 0_u32
        return if LibX11.get_geometry(
                    @display,
                    window,
                    pointerof(root),
                    pointerof(x),
                    pointerof(y),
                    pointerof(width),
                    pointerof(height),
                    pointerof(border),
                    pointerof(depth)
                  ) == 0

        geometry = Geometry.new(x, y, width, height)
        target = X11WindowFix.correction(
          @screen_width,
          @screen_height,
          geometry
        )
        return unless target
        return if geometry == Geometry.new(
                    target.x,
                    target.y,
                    target.width,
                    target.height
                  )

        LibX11.move_resize_window(
          @display,
          window,
          target.x,
          target.y,
          target.width,
          target.height
        )
      end
    end

    @[Link("X11")]
    lib LibX11
      alias Window = UInt64
      type Display = Void

      struct ClassHint
        res_name : UInt8*
        res_class : UInt8*
      end

      fun open_display = XOpenDisplay(display_name : UInt8*) : Display*
      fun set_error_handler = XSetErrorHandler(
        handler : (Display*, Void*) -> Int32,
      ) : (Display*, Void*) -> Int32
      fun close_display = XCloseDisplay(display : Display*) : Int32
      fun default_screen = XDefaultScreen(display : Display*) : Int32
      fun display_width = XDisplayWidth(display : Display*, screen : Int32) : Int32
      fun display_height = XDisplayHeight(display : Display*, screen : Int32) : Int32
      fun default_root_window = XDefaultRootWindow(display : Display*) : Window
      fun query_tree = XQueryTree(
        display : Display*,
        window : Window,
        root_return : Window*,
        parent_return : Window*,
        children_return : Window**,
        child_count_return : UInt32*,
      ) : Int32
      fun get_class_hint = XGetClassHint(
        display : Display*,
        window : Window,
        hint : ClassHint*,
      ) : Int32
      fun fetch_name = XFetchName(
        display : Display*,
        window : Window,
        window_name_return : UInt8**,
      ) : Int32
      fun get_geometry = XGetGeometry(
        display : Display*,
        drawable : Window,
        root_return : Window*,
        x_return : Int32*,
        y_return : Int32*,
        width_return : UInt32*,
        height_return : UInt32*,
        border_width_return : UInt32*,
        depth_return : UInt32*,
      ) : Int32
      fun move_resize_window = XMoveResizeWindow(
        display : Display*,
        window : Window,
        x : Int32,
        y : Int32,
        width : UInt32,
        height : UInt32,
      ) : Int32
      fun flush = XFlush(display : Display*) : Int32
      fun free = XFree(data : Void*) : Int32
    end
  end
end
