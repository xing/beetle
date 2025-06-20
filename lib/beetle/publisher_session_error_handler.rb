module Beetle
  # A bunny session error handler that handles errors occuring in background threads of bunny
  class PublisherSessionErrorHandler
    attr_reader :server, :reraise_target

    def initialize(logger, publisher, server_name, session_thread = Thread.current)
      @publisher = publisher
      @server = server_name
      @logger = logger

      # the thread which has a reference to the session and this error handler
      @session_thread = session_thread

      # the thread in which the error will be raised if re-reaise is enabled
      @reraise_target = nil
      @reraise_errors = false

      @error_mutex = Mutex.new
      @error_args = nil
    end

    def exceptions?
      @error_mutex.synchronize { !@error_args.nil? }
    end

    def reraise_errors?
      @reraise_errors
    end

    # Raise is called when a bunny component wants to signal an error
    # This method will mostly be called from a background thread of bunny (reader_loop, heartbeat_sender).
    #
    # The logic of this method depends on when it is invoked.
    #
    # If it is invoked in the context of `synchronize_errors`, it will raise the error in the thread that is bound to `@reraise_target`.
    # If it is invoked outside of `synchronize_errors`, it will record the error and kill the thread that called this method.
    #
    # @param args [Array] the arguments to raise, usually an exception class and a message
    def raise(*args)
      current_thread = Thread.current
      @logger.error "Beetle: bunny session handler errror. server=#{@server} reraise=#{@reraise_errors} raised_in=#{current_thread.inspect}."

      deliver_to_reraise_target!(*args)
      record_and_terminate_thread!(current_thread, *args)
    end

    # This is the main method to surface exceptions that might occur in another thread to the thread that runs this method.
    # Make sure that you wrap this with error handling code, that can deal with all errors that might have been signaled to the error handler.
    #
    # The error semantics are as follows:
    #
    # 1. If the error handler has recorded an error, it will raise the last recorded error in `Thread.current`
    # 2. If no error has been recorded before, it will execute `block` and reraise all exceptions (including those coming from background threads)
    #    while `block` is executing.
    #
    # This method is not thread-safe, so it should only be called from the same thread that has a reference to this error handler.
    #
    # Example usage:
    #
    # ```ruby
    #
    # begin
    #   my_error_handler.synchronize_errors do
    #     # run publishing code
    #   end
    # rescue Bunny::Exception => e
    #   # Handle all errors, those in Thread.current but also those that were raised in background threads.
    #   puts "Bunny error: #{e.message}"
    # end
    #
    # ```
    def synchronize_errors
      @reraise_errors = true
      @reraise_target = Thread.current
      flush_pending_errors!
      yield if block_given?
    ensure
      @reraise_errors = false
      @reraise_target = nil
    end

    private

    def deliver_to_reraise_target!(*args)
      @reraise_target.raise(*args) if @reraise_errors && @reraise_target
    end

    def record_and_terminate_thread!(thread, *args)
      @error_mutex.synchronize { @error_args = args }
      thread.kill if thread != @session_thread
    end

    def flush_pending_errors!
      error = @error_mutex.synchronize do
        err = @error_args
        @error_args = nil
        err
      end

      deliver_to_reraise_target!(*error) if error
    end
  end
end
