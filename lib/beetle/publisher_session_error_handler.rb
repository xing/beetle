module Beetle
  # A bunny session error handler that handles errors occuring in background threads of bunny
  class PublisherSessionErrorHandler
    def initialize(logger, publisher, server_name)
      @publisher = publisher
      @server = server_name

      @error_mutex = Mutex.new
      @error_args = nil

      @reraise_errors = false
      @logger = logger
    end

    def exceptions?
      @error_args != nil
    end

    # Accepts an exception
    # If this method is called when code is executed ins inside #reraising_errors block
    # then the exception will be through in the same thread that the block runs.
    # If this method is called outside of the #rereaising_errors block then the error is recoreded
    # and will be through the next time #reraising_errors is called.
    #
    # This essentially delays the raise of excpeptions in the main thread until the code that is prepared to handle them is executed.
    def raise(*args)
      current_thread = Thread.current
      @logger.error "Beetle: bunny session handler errror. server=#{@server} reraise=#{@reraise_errors}  raised_in=#{current_thread.inspect}."

      # reraise in thread that created the session?
      Kernel.raise(*args) if @reraise_errors

      # don't reraise but record
      @error_mutex.synchronize { @error_args = args }
    end

    # Executes block which has to be prepared to handle errors from this session error handler
    # If the error handler has an exeption recorded it will be raised before the block is called
    # If the error handler does not have an exception recorded it will execute block, and every exception handled during execution
    # of the block, including those raised from another thread, will be re-raised here.
    def reraising_errors(&block)
      reraise_last_error!
      @reraise_errors = true
      block.call
    ensure
      @reraise_errors = false
    end

    private

    def reraise_last_error!
      return unless @error_args

      error = @error_args
      @error_mutex.synchronize { @error_args = nil }

      Kernel.raise(*error)
    end

  end
end
