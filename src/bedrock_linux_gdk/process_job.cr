require "gtk4"
require "./host_environment"

module BedrockLinuxGdk
  class ProcessJob
    getter running = false
    getter stopping = false

    @process : Gio::Subprocess?
    @stream : Gio::DataInputStream?
    @cancellable : Gio::Cancellable?
    @on_line : Proc(String, Nil)?
    @on_done : Proc(Int32?, String?, Nil)?
    @exit_code : Int32?
    @error : String?
    @read_done = false
    @wait_done = false

    def initialize
      @process = nil
      @stream = nil
      @cancellable = nil
      @on_line = nil
      @on_done = nil
      @exit_code = nil
      @error = nil
    end

    def start(
      command : Array(String),
      on_line : Proc(String, Nil),
      on_done : Proc(Int32?, String?, Nil),
      environment : Hash(String, String) = HostEnvironment.values,
    ) : Bool
      return false if @running
      raise ArgumentError.new("empty command") if command.empty?

      flags = Gio::SubprocessFlags::StdoutPipe |
              Gio::SubprocessFlags::StderrMerge
      launcher = Gio::SubprocessLauncher.new(flags)
      launcher.environ = environment.map { |key, value| "#{key}=#{value}" }
      process = launcher.spawnv(command)
      stream = Gio::DataInputStream.new(
        base_stream: process.stdout_pipe.not_nil!,
        close_base_stream: true
      )

      @process = process
      @stream = stream
      @cancellable = Gio::Cancellable.new
      @on_line = on_line
      @on_done = on_done
      @exit_code = nil
      @error = nil
      @read_done = false
      @wait_done = false
      @running = true
      @stopping = false

      read_next_line
      process.wait_async(@cancellable) do |_source, result|
        begin
          process.wait_finish(result)
          @exit_code = if process.if_exited
                         process.exit_status
                       elsif process.if_signaled
                         128 + process.term_sig
                       end
        rescue exception
          @error ||= exception.message || exception.class.name
        ensure
          @wait_done = true
          finish_if_ready
        end
      end
      true
    rescue exception
      reset
      on_done.call(nil, exception.message || exception.class.name)
      false
    end

    def stop : Bool
      return false unless @running
      return false if @stopping

      @stopping = true
      process = @process
      process.try(&.send_signal(Signal::TERM.value))
      GLib.timeout(1.second) do
        if @running && @process == process
          process.try(&.force_exit)
        end
        false
      end
      true
    rescue
      @process.try(&.force_exit)
      true
    end

    private def read_next_line : Nil
      stream = @stream
      return unless stream

      stream.read_line_async(GLib::PRIORITY_DEFAULT, @cancellable) do |_source, result|
        begin
          if line = stream.read_line_finish_utf8(result)
            @on_line.try(&.call(line.rstrip))
            read_next_line
          else
            @read_done = true
            finish_if_ready
          end
        rescue exception
          @error ||= exception.message || exception.class.name
          @read_done = true
          finish_if_ready
        end
      end
    end

    private def finish_if_ready : Nil
      return unless @running && @read_done && @wait_done

      on_done = @on_done
      exit_code = @exit_code
      error = @error
      reset
      on_done.try(&.call(exit_code, error))
    end

    private def reset : Nil
      @process = nil
      @stream = nil
      @cancellable = nil
      @on_line = nil
      @on_done = nil
      @exit_code = nil
      @error = nil
      @read_done = false
      @wait_done = false
      @running = false
      @stopping = false
    end
  end
end
