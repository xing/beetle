module Beetle
  class Message
    FORMAT_VERSION = 1
    FLAG_REDUNDANT = 1
    DEFAULT_TTL = 1.day
    DEFAULT_HANDLER_TIMEOUT = 300.seconds
    DEFAULT_HANDLER_EXECUTION_ATTEMPTS = 5
    DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY = 10.seconds
    DEFAULT_EXCEPTION_LIMIT = 1

    attr_reader :server, :queue, :header, :body, :uuid, :data, :format_version, :flags, :expires_at
    attr_reader :timeout, :delay, :attempts_limit, :exceptions_limit

    def initialize(queue, header, body, opts = {})
      @queue  = queue
      @header = header
      @body   = body
      setup(opts)
      decode
    end

    def setup(opts)
      @server = opts[:server]
      @timeout          = opts[:timeout]    || DEFAULT_HANDLER_TIMEOUT
      @attempts_limit   = opts[:attempts]   || DEFAULT_HANDLER_EXECUTION_ATTEMPTS
      @delay            = opts[:delay]      || DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY
      @exceptions_limit = opts[:exceptions] || DEFAULT_EXCEPTION_LIMIT
    end

    def decode
      @format_version, @flags, @expires_at, @uuid, @data = @body.unpack("nnNA36A*")
    end

    def self.encode(data, opts = {})
      expires_at = ttl_to_expiration_time(opts[:ttl] || DEFAULT_TTL)
      flags = 0
      flags |= FLAG_REDUNDANT if opts[:redundant]
      [FORMAT_VERSION, flags, expires_at, generate_uuid.to_s, data.to_s].pack("nnNA36A*")
    end

    def msg_id
      @msg_id ||= "msgid:#{queue}:#{uuid}"
    end

    def now
      Time.now.to_i
    end

    def expired?(expiration_time = Time.now.to_i)
      @expires_at < expiration_time
    end

    def self.ttl_to_expiration_time(ttl)
      Time.now.to_i + ttl.to_i
    end

    def self.generate_uuid
      UUID4R::uuid(1)
    end

    def redundant?
      @flags & FLAG_REDUNDANT == FLAG_REDUNDANT
    end

    def set_timeout!
      redis.set(timeout_key, now + timeout)
    end

    def timed_out?
      (t = redis.get(timeout_key)) && t.to_i < now
    end

    def timed_out!
      redis.set(timeout_key, 0)
    end

    def completed?
      redis.get(status_key) == "completed"
    end

    def completed!
      redis.set(status_key, "completed")
      timed_out!
    end

    def delayed?
      (t = redis.get(delay_key)) && t.to_i > now
    end

    def set_delay!
      redis.set(delay_key, now + delay)
    end

    def increment_execution_attempts!
      redis.incr(execution_attempts_key)
    end

    def attempts_limit_reached?
      (limit = redis.get(execution_attempts_key)) && limit.to_i >= attempts_limit
    end

    def increment_exception_count!
      redis.incr(exceptions_key)
    end

    def exceptions_limit_reached?
      (limit = redis.get(exceptions_key)) && limit.to_i >= exceptions_limit
    end

    def key_exists?
      new_message = redis.setnx(status_key, "incomplete")
      unless new_message
        logger.debug "received duplicate message: #{status_key} on queue: #{@queue}"
      end
      !new_message
    end

    def aquire_mutex!
      if mutex = redis.setnx(mutex_key, now)
        logger.debug "aquired mutex: #{msg_id}"
      else
        redis.del(mutex_key)
        logger.debug "deleted mutex: #{msg_id}"
      end
      mutex
    end

    def self.redis
      @redis ||= Redis.new
    end

    def self.redis=redis
      @redis = redis
    end

    def process(block)
      logger.debug "Processing message #{msg_id}"
      begin
        process_internal(block)
      rescue Exception => e
        logger.warn "Exception '#{e}' during invocation of message handler for #{msg_id}"
        logger.warn "Backtrace: #{e.backtrace.join("\n")}"
        raise
      end
    end

    def status_key
      keys[:status] ||= "#{msg_id}:status"
    end

    def ack_count_key
      keys[:ack_count] ||= "#{msg_id}:ack_count"
    end

    def timeout_key
      keys[:timeout] ||= "#{msg_id}:timeout"
    end

    def delay_key
      keys[:delay] ||= "#{msg_id}:delay"
    end

    def execution_attempts_key
      keys[:attempts] ||= "#{msg_id}:attempts"
    end

    def mutex_key
      keys[:mutex] ||= "#{msg_id}:mutex"
    end

    def exceptions_key
      keys[:exceptions] ||= "#{msg_id}:exceptions"
    end

    def all_keys
      [status_key, ack_count_key, timeout_key, delay_key, execution_attempts_key, exceptions_key, mutex_key]
    end

    def keys
      @keys ||= {}
    end

    private

    def process_internal(block)
      if expired?
        logger.warn "Ignored expired message (#{msg_id})!"
        ack!
        return
      end

      if !key_exists?
        set_timeout!
        run_handler!(block)
      elsif completed?
        ack!
      elsif delayed?
        logger.warn "Ignored delayed message (#{msg_id})!"
      elsif !timed_out?
        raise HandlerNotYetTimedOut
      elsif attempts_limit_reached?
        ack!
        raise AttemptsLimitReached, "Reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
      elsif exceptions_limit_reached?
        ack!
        raise ExceptionsLimitReached, "Reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
      else
        set_timeout!
        run_handler!(block) if aquire_mutex!
      end
    end

    def run_handler!(block)
      begin
        increment_execution_attempts!
        block.call(self)
      rescue Exception => e
        increment_exception_count!
        if attempts_limit_reached?
          ack!
          raise AttemptsLimitReached, "Reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
        elsif exceptions_limit_reached?
          ack!
          raise ExceptionsLimitReached, "Reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
        else
          timed_out!
          set_delay!
          raise HandlerCrash.new(e)
        end
      end
      completed!
      ack!
    end

    def redis
      self.class.redis
    end

    def logger
      self.class.logger
    end

    def self.logger
      Beetle.config.logger
    end

    def ack!
      logger.debug "ack! for message #{msg_id}"
      header.ack
      if !redundant? || redis.incr(ack_count_key) == 2
        redis.del(all_keys)
      end
    end
  end
end
