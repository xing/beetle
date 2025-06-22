module Beetle
  # A bunny session error handler that handles errors occuring in background threads of bunny
  class PublisherSessionErrorHandler
    attr_reader :server

    # An error that is raised when `synchronize_errors` is called in an unsupported context.
    class SynchronizationError < StandardError; end

    # @param logger [Logger] a logger to log errors to
    # @param server_name [String] the name of the server this error handler is bound to
    # @param terminate_thread [Boolean] whether the thread that raised the error should be terminated. Defaults to true.
    def initialize(logger, server_name, terminate_thread: true)
      # the thread which has a reference to the session and this error handler
      @session_thread = Thread.current

      @server = server_name
      @logger = logger
      @terminate_thread = terminate_thread # shall threads be terminated when raise is invoked?

      @synchronous_errors = false
      @synchronous_errors_mutex = Mutex.new

      @error_mutex = Mutex.new
      @error_args = nil
    end

    def exceptions?
      @error_mutex.synchronize { !@error_args.nil? }
    end

    def synchronous_errors?
      @synchronous_errors_mutex.synchronize { @synchronous_errors }
    end

    # Raise is called when a bunny component wants to signal an error
    # This method will mostly be called from a background thread of bunny (reader_loop, heartbeat_sender).
    #
    # The logic of this method depends on when it is invoked.
    #
    # If it is invoked in the context of `synchronize_errors`, it will raise the error in the thread that is bound to `@session_thread`
    # If it is invoked outside of `synchronize_errors`, it will record the error and potentially kill the thread that called this method.
    #
    # @param args [Array] the arguments to raise, usually an exception class and a message
    def raise(*args)
      source_thread = Thread.current # the thread that invoked this method
      is_synchronous = synchronous_errors?

      @logger.error "Beetle: bunny session handler error. server=#{@server} reraise=#{is_synchronous} raised_in=#{source_thread.inspect}."

      reraise!(*args) if is_synchronous
      record_and_terminate_thread!(source_thread, *args)
    end

    # This is the main method to surface exceptions that might occur in another thread to the thread that runs this method.
    # Make sure that you wrap this with error handling code, that can deal with all errors that might have been signaled to the error handler.
    #
    # The error semantics are as follows:
    #
    # 1. If the error handler has recorded an error, it will raise the first recorded error in the thread that calls the method
    # 2. If no error has been recorded before, it will execute `block` and reraise all exceptions (including those coming from background threads)
    #    while `block` is executing.
    #
    # This method is not reentrant and not thread-safe, so it should only be called from the same thread that has a reference to this error handler.
    # In fact we will enforce this, by raising a `SynchronizationError` if this method is called where its not allowed.
    #
    # Example usage:
    #
    # ```ruby
    #
    # begin
    #   my_error_handler.synchronize_errors do
    #     # run code that uses the bunny session
    #   end
    # rescue Bunny::Exception => e
    #   # Handle all errors, those in Thread.current but also those that were raised in background threads.
    #   puts "Bunny error: #{e.message}"
    # end
    #
    # ```
    def synchronize_errors
      # both of these will exit early without changing the state @synchronous_errors
      # so that we make sure a nested call is fine
      Kernel.raise SynchronizationError, "synchronize_errors must be called from the thread that created the error handler." unless Thread.current == @session_thread
      Kernel.raise SynchronizationError, "synchronize_errors cannot be nested / re-entered" if synchronous_errors?

      begin
        @synchronous_errors_mutex.synchronize do
          @synchronous_errors = true
        end

        raise_pending_error!
        yield if block_given?
      ensure
        @synchronous_errors_mutex.synchronize do
          @synchronous_errors = false
        end
      end
    end

    private

    # safes the first recorded error since it is closes to be the root cause
    # kill the thread that called this method, unless it is the session thread
    def record_and_terminate_thread!(source_thread, *args)
      @error_mutex.synchronize { @error_args ||= args }

      return unless @terminate_thread
      return if source_thread == @session_thread

      source_thread.kill
    end

    def raise_pending_error!
      error = @error_mutex.synchronize do
        err = @error_args
        @error_args = nil
        err
      end

      reraise!(*error) if error
    end

    def reraise!(*args)
      @session_thread.raise(*args)
    end
  end
end
