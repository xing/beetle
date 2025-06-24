module Beetle
  # A bunny session error handler detects failures originating from background threads, that belong to a bunny connection.
  # Using this instead of the default `Thread.current` prevents hard to manage asynchronous exceptions.
  class PublisherSessionErrorHandler
    attr_reader :server

    # @param logger [Logger] a logger to log errors to
    # @param server_name [String] the name of the server this error handler is bound to
    def initialize(logger, server_name)
      @server = server_name
      @logger = logger

      @error_mutex = Mutex.new
      @error_args = nil
    end

    # Predicate to check if the error handler has detected an error.
    #
    # @return [Boolean] true if an error has been recorded, false otherwise
    def exception?
      @error_mutex.synchronize { !!@error_args }
    end

    # Resets the error state of this error handler.
    #
    # @return [Array, nil] the error arguments that were previously recorded, or nil if no error was recorded
    def clear_exception!
      @error_mutex.synchronize do
        error_args = @error_args
        @error_args = nil
        error_args
      end
    end

    def raise_pending_exception!
      error = clear_exception!
      Kernel.raise(*error) if error
    end

    # Raise is called when a bunny component wants to signal an error.
    # It will mostly be called from a background thread of bunny (reader_loop, heartbeat_sender).
    #
    # @param args [Array] the arguments to raise, usually an exception class and a message
    def raise(*args)
      source_thread = Thread.current # the thread that invoked this method
      @logger.error "Beetle: bunny session handler error. server=#{@server} raised_from=#{source_thread.inspect}."
      @error_mutex.synchronize { @error_args ||= args }
    end
  end
end
