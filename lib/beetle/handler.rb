module Beetle
  # Instances of class Handler are created by the message processing logic in class
  # Message. There should be no need to ever create them in client code, except for
  # testing purposes.
  #
  # Most applications will define Handler subclasses and override the process, error and
  # failure methods.
  class Handler
    include Logging

    # the Message instance which caused the handler to be created
    attr_reader :message

    def self.create(handler, opts={}) #:nodoc:
      if handler.is_a? Handler
        # a handler instance
        handler
      elsif handler.is_a?(Class) && handler.ancestors.include?(Handler)
        # handler class
        handler.new
      else
        # presumably something which responds to call
        new(handler, opts)
      end
    end

    # optionally capture processor, error and failure callbacks
    def initialize(processor=nil, opts={}) #:notnew:
      @processor = processor
      @error_callback = opts[:errback]
      @failure_callback = opts[:failback]
    end

    # called when a message should be processed. if the message was caused by an RPC, the
    # return value will be sent back to the caller. calls the initialized processor proc
    # if a processor proc was specified when creating the Handler instance. calls method
    # process if no proc was given. make sure to call super if you override this method in
    # a subclass.
    def call(message)
      @message = message
      if @processor
        @processor.call(message)
      else
        process
      end
    end

    # called for message processing if no processor was specfied when the handler instance
    # was created
    def process
      logger.info "Beetle: received message #{message.inspect}"
      send(routing_key, payload) if respond_to? routing_key
    end

    # should not be overriden in subclasses
    def process_exception(exception) #:nodoc:
      if @error_callback
        @error_callback.call(message, exception)
      else
        error(exception)
      end
    rescue Exception
      Beetle::reraise_expectation_errors!
    end

    # should not be overriden in subclasses
    def process_failure(result) #:nodoc:
      if @failure_callback
        @failure_callback.call(message, result)
      else
        failure(result)
      end
    rescue Exception
      Beetle::reraise_expectation_errors!
    end

    # should not be overriden in subclasses
    def processing_completed
      completed
    rescue Exception
      Beetle::reraise_expectation_errors!
    end

    # called when handler execution raised an exception and no error callback was
    # specified when the handler instance was created
    def error(exception)
      logger.error "Beetle: handler execution raised an exception: #{exception}"
    end

    # called when message processing has finally failed (i.e., the number of allowed
    # handler execution attempts or the number of allowed exceptions has been reached) and
    # no failure callback was specified when this handler instance was created.
    def failure(result)
      logger.error "Beetle: handler has finally failed"
    end

    # called after all normal processing has been completed. flushes the loggger, if it responds to flush.
    def completed
      logger.debug "Beetle: message processing completed"
      logger.flush if logger.respond_to?(:flush)
    end

    # returns the configured Beetle logger
    def self.logger
      Beetle.config.logger
    end

    # sets the given block as handler for the given keys
    def self.handle *keys, &block
      method_name, aliases = *keys
      define_method method_name, &block

      aliases.each do |key|
        alias_method key, method_name
      end if aliases
    end

  end
end
