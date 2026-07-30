require "gtk4"
require "../host_environment"

module BedrockLinuxGdk
  module UI
    module HostLaunch
      extend self

      def open_uri(uri : String) : Bool
        return false unless uri.starts_with?("https://")

        launch(uri)
      end

      def open_path(path : String) : Bool
        expanded = File.expand_path(path)
        return false unless Dir.exists?(expanded)

        launch(expanded)
      rescue File::Error
        false
      end

      private def launch(target : String) : Bool
        process = Process.new(
          ["xdg-open", target],
          env: HostEnvironment.values,
          clear_env: true,
          input: Process::Redirect::Close,
          output: Process::Redirect::Close,
          error: Process::Redirect::Close
        )
        spawn do
          process.wait
        rescue RuntimeError
        end
        true
      rescue File::Error | IO::Error
        false
      end
    end
  end
end
