module Beetle
  class SingleBrokerMessage < Message
    def initialize(*args, **kwargs)
      super(*args, **kwargs)
      @store = nil
    end

    def ack!
      logger.debug "Beetle: ack! for message #{msg_id}"
      header.ack
    end

    def set_delay!
      log_not_supported("delay between retries")
    end

    def delayed?
      log_not_supported("delay between retries")
      false
    end

    def redundant?
      false
    end

    def increment_execution_attempts!; end

    def attempts_limit_reached?(_attempts = nil)
      # TODO: implement
      false
    end

    def exceptions_limit_reached?
      # TODO: implement
      false
    end

    private

    def log_not_supported(what)
      logger.warn "Beetle: Feature not supported in single broker mode => #{what}"
    end

    def run_handler!(handler)
      case result = run_handler(handler)
      when RC::OK
        ack!
        result
      else
        handler_failed!(result)
      end
    end

    def handler_failed!(result)
      if attempts_limit_reached?
        ack!
        logger.debug "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
        RC::AttemptsLimitReached
      elsif exceptions_limit_reached?
        ack!
        logger.debug "Beetle: reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
        RC::ExceptionsLimitReached
      elsif !exception_accepted?
        ack!
        logger.debug "Beetle: `#{@exception.class.name}` not accepted: `retry_on`=[#{retry_on.join(',')}] on #{msg_id}"
        RC::ExceptionNotAccepted
      else
        result
      end
    end

    # Open questions:
    # - do we need to support timeouts that span executions?
    def process_internal(handler)
      if @exception
        ack!
        RC::DecodingError
      elsif @pre_exception
        ack!
        RC::PreprocessingError
      elsif expired?
        logger.warn "Beetle: ignored expired message (#{msg_id})!"
        ack!
        RC::Ancient
      elsif simple?
        ack!
        run_handler(handler) == RC::HandlerCrash ? RC::AttemptsLimitReached : RC::OK
      elsif attempts_limit_reached?
        ack!
        logger.warn "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
        RC::AttemptsLimitReached
      elsif exceptions_limit_reached?
        ack!
        logger.warn "Beetle: reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
        RC::ExceptionsLimitReached
      else
        run_handler!(handler)
      end
    end
  end
end
