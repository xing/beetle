module Beetle
  class Handler
    attr_reader :message

    def self.create(block_or_handler, opts={})
      if block_or_handler.is_a? Handler
        block_or_handler
      elsif block_or_handler.is_a?(Class) && block_or_handler.ancestors.include?(Handler)
        block_or_handler.new
      else
        new(block_or_handler, opts)
      end
    end

    def initialize(processor=nil, opts={})
      @processor = processor
      @error_callback = opts[:errback]
      @failure_callback = opts[:failback]
    end

    def call(message)
      @message = message
      if @processor
        @processor.call(@message)
      else
        process
      end
    end

    def process(message)
      logger.info "Beetle: received message #{message.inspect}"
    end

    def process_exception(exception)
      begin
        if @error_callback
          @error_callback.call(message, exception)
        else
          error(exception)
        end
      rescue Exception
      end
    end

    def process_failure(result)
      begin
        if @failure_callback
          @failure_callback.call(message, result)
        else
          failure(result)
        end
      rescue Exception
      end
    end

    def error(exception)
      logger.error "Beetle: handler execution raised an exeption: #{exception}"
    end

    def failure(result)
      logger.error "Beetle: handler has finally failed"
    end

    def logger
      Beetle.config.logger
    end

    def self.logger
      Beetle.config.logger
    end

  end
end
