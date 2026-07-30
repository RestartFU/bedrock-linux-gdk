require "./host_environment"

module BedrockLinuxGdk
  class ProcessJob
    getter running = false

    @process : Process?

    def initialize
      @process = nil
    end

    def start(
      command : Array(String),
      on_line : Proc(String, Nil),
      on_done : Proc(Process::Status?, String?, Nil),
      environment : Hash(String, String) = HostEnvironment.values,
    ) : Bool
      return false if @running
      raise ArgumentError.new("empty command") if command.empty?

      reader, writer = IO.pipe
      process = Process.new(
        command,
        env: environment,
        clear_env: true,
        input: Process::Redirect::Close,
        output: writer,
        error: writer
      )
      writer.close
      @process = process
      @running = true

      spawn do
        error : String? = nil
        status : Process::Status? = nil
        begin
          while line = reader.gets
            on_line.call(line.rstrip)
            Fiber.yield
          end
          status = process.wait
        rescue exception : IO::Error | RuntimeError
          error = exception.message || exception.class.name
        ensure
          reader.close
          @process = nil
          @running = false
          on_done.call(status, error)
        end
      end
      true
    rescue exception : File::Error | IO::Error
      writer.try(&.close)
      reader.try(&.close)
      @process = nil
      @running = false
      on_done.call(nil, exception.message || exception.class.name)
      false
    end

    def stop : Nil
      @process.try(&.terminate(graceful: false))
    rescue RuntimeError
    end
  end
end
