require "timeout"

module Beetle
  class Message
    FORMAT_VERSION = 2
    FLAG_REDUNDANT = 1
    DEFAULT_TTL = 1.day
    DEFAULT_HANDLER_TIMEOUT = 300.seconds
    DEFAULT_HANDLER_EXECUTION_ATTEMPTS = 1
    DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY = 10.seconds
    DEFAULT_EXCEPTION_LIMIT = 1

    attr_reader :server, :queue, :header, :body, :uuid, :data, :format_version, :flags, :expires_at, :starts_at
    attr_reader :timeout, :delay, :attempts_limit, :exceptions_limit, :exception

    def initialize(queue, header, body, opts = {})
      @keys   = {}
      @queue  = queue
      @header = header
      @body   = body
      setup(opts)
      decode
    end

    def setup(opts)
      @server           = opts[:server]
      @timeout          = opts[:timeout]    || DEFAULT_HANDLER_TIMEOUT
      @attempts_limit   = opts[:attempts]   || DEFAULT_HANDLER_EXECUTION_ATTEMPTS
      @delay            = opts[:delay]      || DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY
      @exceptions_limit = opts[:exceptions] || DEFAULT_EXCEPTION_LIMIT
    end

    def decode
      case @body.unpack("n").first
      when 1
        @format_version, @flags, @expires_at, @uuid, @data = @body.unpack("nnNA36A*")
      when 2
        @format_version, @flags, @starts_at, @expires_at, @uuid, @data = @body.unpack("nnNNA36A*")
      end
    end

    def self.encode(data, opts = {})
      now = now()
      expires_at = now + (opts[:ttl] || DEFAULT_TTL).to_i
      starts_at = now + (opts[:delay] || 0).to_i
      flags = 0
      flags |= FLAG_REDUNDANT if opts[:redundant]
      [FORMAT_VERSION, flags, starts_at, expires_at, generate_uuid.to_s, data.to_s].pack("nnNNA36A*")
    end

    # encode format version 1
    def self.encode1(data, opts = {})
      expires_at = now + (opts[:ttl] || DEFAULT_TTL).to_i
      flags = 0
      flags |= FLAG_REDUNDANT if opts[:redundant]
      [1, flags, expires_at, generate_uuid.to_s, data.to_s].pack("nnNA36A*")
    end

    def msg_id
      @msg_id ||= "msgid:#{queue}:#{uuid}"
    end

    def now
      Time.now.to_i
    end

    def self.now
      Time.now.to_i
    end

    def expired?
      @expires_at < now
    end

    def started?
      @starts_at <= now
    end

    def self.generate_uuid
      UUID4R::uuid(1)
    end

    def redundant?
      @flags & FLAG_REDUNDANT == FLAG_REDUNDANT
    end

    def set_timeout!
      redis.set(key(:timeout), now + timeout)
    end

    def timed_out?
      (t = redis.get(key(:timeout))) && t.to_i < now
    end

    def timed_out!
      redis.set(key(:timeout), 0)
    end

    def completed?
      redis.get(key(:status)) == "completed"
    end

    def completed!
      redis.set(key(:status), "completed")
      timed_out!
    end

    def delayed?
      (t = redis.get(key(:delay))) && t.to_i > now
    end

    def set_delay!
      redis.set(key(:delay), now + delay)
    end

    def increment_execution_attempts!
      redis.incr(key(:attempts))
    end

    def attempts_limit_reached?
      (limit = redis.get(key(:attempts))) && limit.to_i >= attempts_limit
    end

    def increment_exception_count!
      redis.incr(key(:exceptions))
    end

    def exceptions_limit_reached?
      redis.get(key(:exceptions)).to_i >= exceptions_limit
    end

    def key_exists?
      old_message = 0 == redis.msetnx(key(:status) =>"incomplete", key(:expires) => @expires_at)
      if old_message
        logger.debug "Beetle: received duplicate message: #{key(:status)} on queue: #{@queue}"
      end
      old_message
    end

    def aquire_mutex!
      if mutex = redis.setnx(key(:mutex), now)
        logger.debug "Beetle: aquired mutex: #{msg_id}"
      else
        redis.del(key(:mutex))
        logger.debug "Beetle: deleted mutex: #{msg_id}"
      end
      mutex
    end

    def self.redis
      @redis ||= Redis.new(:host => Beetle.config.redis_host, :db => Beetle.config.redis_db)
    end

    KEY_SUFFIXES = [:status, :ack_count, :timeout, :delay, :attempts, :exceptions, :mutex, :expires]

    def key(suffix)
      @keys[suffix] ||= self.class.key(msg_id, suffix)
    end

    def keys
      self.class.keys(msg_id)
    end

    def self.key(msg_id, suffix)
      "#{msg_id}:#{suffix}"
    end

    def self.keys(msg_id)
      KEY_SUFFIXES.map{|suffix| key(msg_id, suffix)}
    end

    def self.msg_id(key)
      key =~ /^(msgid:[^:]*:[-0-9a-f]*):.*$/ && $1
    end

    def self.garbage_collect_keys
      keys = redis.keys("msgid:*:expires")
      threshold = now + Beetle.config.gc_threshold
      keys.each do |key|
        expires_at = redis.get key
        if expires_at && expires_at.to_i < threshold
          msg_id = msg_id(key)
          redis.del(keys(msg_id))
        end
      end
    end

    def process(handler)
      logger.debug "Beetle: processing message #{msg_id}"
      result = nil
      begin
        result = process_internal(handler)
        handler.process_exception(@exception) if @exception
        handler.process_failure(result) if result.failure?
      rescue Exception => e
        Beetle::reraise_expectation_errors!
        logger.warn "Beetle: exception '#{e}' during processing of message #{msg_id}"
        logger.warn "Beetle: backtrace: #{e.backtrace.join("\n")}"
        result = RC::InternalError
      end
      result
    end

    private

    def process_internal(handler)
      if expired?
        logger.warn "Beetle: ignored expired message (#{msg_id})!"
        ack!
        RC::Ancient
      elsif !started?
        logger.warn "Beetle: message handler should not be started yet!"
        RC::Delayed
      elsif !key_exists?
        set_timeout!
        run_handler!(handler)
      elsif completed?
        ack!
        RC::OK
      elsif delayed?
        logger.warn "Beetle: ignored delayed message (#{msg_id})!"
        RC::Delayed
      elsif !timed_out?
        RC::HandlerNotYetTimedOut
      elsif attempts_limit_reached?
        ack!
        logger.warn "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
        RC::AttemptsLimitReached
      elsif exceptions_limit_reached?
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

    def run_handler!(handler)
      increment_execution_attempts!
      begin
        Timeout::timeout(@timeout) { handler.call(self) }
      rescue Exception => @exception
        Beetle::reraise_expectation_errors!
        increment_exception_count!
        if attempts_limit_reached?
          ack!
          logger.warn "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
          return RC::AttemptsLimitReached
        elsif exceptions_limit_reached?
          ack!
          logger.warn "Beetle: reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
          return RC::ExceptionsLimitReached
        else
          timed_out!
          set_delay!
          logger.warn "Beetle: message handler crashed on #{msg_id}"
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
      logger.debug "Beetle: ack! for message #{msg_id}"
      header.ack
      if !redundant? || redis.incr(key(:ack_count)) == 2
        redis.del(keys)
      end
    end
  end
end
