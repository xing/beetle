require "timeout"

module Beetle
  class Message
    FORMAT_VERSION = 1
    FLAG_REDUNDANT = 1
    DEFAULT_TTL = 1.day
    DEFAULT_HANDLER_TIMEOUT = 300.seconds
    DEFAULT_HANDLER_EXECUTION_ATTEMPTS = 1
    DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY = 10.seconds
    DEFAULT_EXCEPTION_LIMIT = 1

    attr_reader :server, :queue, :header, :body, :uuid, :data, :format_version, :flags, :expires_at
    attr_reader :timeout, :delay, :attempts_limit, :exceptions_limit, :exception

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
      redis.get(exceptions_key).to_i >= exceptions_limit
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

    def status_key
      @status_key ||= "#{msg_id}:status"
    end

    def ack_count_key
      @ack_count_key ||= "#{msg_id}:ack_count"
    end

    def timeout_key
      @timeout_key ||= "#{msg_id}:timeout"
    end

    def delay_key
      @delay_key ||= "#{msg_id}:delay"
    end

    def execution_attempts_key
      @attempts_key ||= "#{msg_id}:attempts"
    end

    def mutex_key
      @mutex_key ||= "#{msg_id}:mutex"
    end

    def exceptions_key
      @exceptions_key ||= "#{msg_id}:exceptions"
    end

    def keys
      [status_key, ack_count_key, timeout_key, delay_key, execution_attempts_key, exceptions_key, mutex_key]
    end

    def process(handler)
      logger.debug "Processing message #{msg_id}"
      result = nil
      begin
        result = process_internal(handler)
        handler.process_exception(@exception) if @exception
        handler.process_failure(result) if result.failure?
      rescue Exception => e
        logger.warn "Exception '#{e}' during processing of message #{msg_id}"
        logger.warn "Backtrace: #{e.backtrace.join("\n")}"
        result = RC::InternalError
      end
      result
    end

    private

    def process_internal(handler)
      if expired?
        logger.warn "Ignored expired message (#{msg_id})!"
        ack!
        RC::Ancient
      elsif !key_exists?
        set_timeout!
        run_handler!(handler)
      elsif completed?
        ack!
        RC::OK
      elsif delayed?
        logger.warn "Ignored delayed message (#{msg_id})!"
        RC::Delayed
      elsif !timed_out?
        RC::HandlerNotYetTimedOut
      elsif attempts_limit_reached?
        ack!
        logger.warn "Reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
        RC::AttemptsLimitReached
      elsif exceptions_limit_reached?
        ack!
        logger.warn "Reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
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

    def run_handler!(handler)
      increment_execution_attempts!
      begin
        Timeout::timeout(@timeout) { handler.call(self) }
      rescue Exception => @exception
        increment_exception_count!
        if attempts_limit_reached?
          ack!
          logger.warn "Reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
          return RC::AttemptsLimitReached
        elsif exceptions_limit_reached?
          ack!
          logger.warn "Reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
          return RC::ExceptionsLimitReached
        else
          timed_out!
          set_delay!
          logger.warn "Message handler crashed on #{msg_id}"
          return RC::HandlerCrash
        end
      ensure
        ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord)
      end
      completed!
      ack!
      RC::OK
    end

    def redis
      @redis ||= self.class.redis
    end

    def logger
      @logger ||= self.class.logger
    end

    def self.logger
      Beetle.config.logger
    end

    def ack!
      logger.debug "ack! for message #{msg_id}"
      header.ack
      if !redundant? || redis.incr(ack_count_key) == 2
        redis.del(keys)
      end
    end
  end
end
