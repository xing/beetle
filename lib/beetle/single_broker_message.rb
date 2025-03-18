module Beetle
  class SingleBrokerMessage < Message
    def ack!
      logger.debug "Beetle: ack! for message #{msg_id}"
      header.ack
    end

    def set_timeout!; end
    def timed_out?(_t = nil) = false
    def timed_out!; end

    def redundant?
      false
    end

    def aquire_mutex!
      true
    end

    def delete_mutex!
      true
    end

    private

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
        if @store.setnx_completed!(msg_id)
          run_handler(handler) == RC::HandlerCrash ? RC::AttemptsLimitReached : RC::OK
        else
          RC::OK
        end
      elsif !key_exists?
        run_handler!(handler)
      else
        status, delay, timeout, attempts, exceptions = fetch_status_delay_timeout_attempts_exceptions
        if status == "completed"
          ack!
          RC::OK
        elsif delay && delayed?(delay)
          logger.warn "Beetle: ignored delayed message (#{msg_id})!"
          RC::Delayed
        elsif !(timeout && timed_out?(timeout))
          RC::HandlerNotYetTimedOut
        elsif attempts && attempts_limit_reached?(attempts)
          completed!
          ack!
          logger.warn "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
          RC::AttemptsLimitReached
        elsif exceptions && exceptions_limit_reached?(exceptions)
          completed!
          ack!
          logger.warn "Beetle: reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
          RC::ExceptionsLimitReached
        else
          set_timeout!
          if aquire_mutex!
            run_handler!(handler)
          else
            RC::MutexLocked
          end
        end
      end
    end
  end
end
