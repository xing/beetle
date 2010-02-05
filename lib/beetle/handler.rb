module Beetle
  class Handler
    attr_reader :message

    def self.create(block_or_handler, opts={})
      if block_or_handler.is_a? Handler
        block_or_handler
      elsif block_or_handler.is_a?(Class) && block_or_handler.ancestors.include?(Handler)
        block_or_handler.new
      else
        new(opts[:errback], block_or_handler)
      end
    end

    def initialize(error_callback=nil, processor=nil)
      @processor = processor
      @error_callback = error_callback
    end

    def call(message)
      @message = message
      if @processor
        @processor.call(@message)
      else
        process
      end
    end

    def process
      logger.info "received message #{m.inspect}"
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

    def error(exception)
      logger.error "Handler execution raised an exeption: #{exception}"
    end

    def logger
      self.class.logger
    end

    def self.logger
      Beetle.config.logger
    end

  end
end
