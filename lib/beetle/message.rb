require "timeout"

module Beetle
  # Instance of class Message are created when a scubscription callback fires. It is
  # responsible for message deduplification and determining if it should retry executing
  # the message handler after a handler has crashed. This is where the beef is.
  class Message
    # current message format version
    FORMAT_VERSION = 2
    # flag for encoding redundant messages
    FLAG_REDUNDANT = 1
    # default lifetime of messages
    DEFAULT_TTL = 1.day
    # forcefully abort a running handler after this many seonds.
    # can be overriden when registering a handler.
    DEFAULT_HANDLER_TIMEOUT = 300.seconds
    # how many times we should try to run a handler before giving up
    DEFAULT_HANDLER_EXECUTION_ATTEMPTS = 1
    # how many seconds we should wait before retrying handler execution
    DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY = 10.seconds
    # how many exceptions should be tolerated before giving up
    DEFAULT_EXCEPTION_LIMIT = 0

    # server from which the message was received
    attr_reader :server
    # name of the queue on which the message was received
    attr_reader :queue
    # the AMQP header received with the message
    attr_reader :header
    # the encoded message boday
    attr_reader :body
    # the uuid of the message
    attr_reader :uuid
    # message payload
    attr_reader :data
    # the message format version of the message
    attr_reader :format_version
    # flags sent with the message
    attr_reader :flags
    # unix timestamp after which the message should be considered stale
    attr_reader :expires_at
    # how many seconds the handler is allowed to execute
    attr_reader :timeout
    # how long to wait before retrying the message handler
    attr_reader :delay
    # how many times we should try to run the handler
    attr_reader :attempts_limit
    # how many exceptions we should tolerate before giving up
    attr_reader :exceptions_limit
    # exception raised by handler execution
    attr_reader :exception
    # value returned by handler execution
    attr_reader :handler_result

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
      @delay            = opts[:delay]      || DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY
      @attempts_limit   = opts[:attempts]   || DEFAULT_HANDLER_EXECUTION_ATTEMPTS
      @exceptions_limit = opts[:exceptions] || DEFAULT_EXCEPTION_LIMIT
      @attempts_limit   = @exceptions_limit + 1 if @attempts_limit <= @exceptions_limit
    end

    def decode
      amqp_headers = header.properties
      if h = amqp_headers[:headers]
        @format_version, @flags, @expires_at = h.values_at(:format_version, :flags, :expires_at).map {|v| v.to_i}
        @uuid = amqp_headers[:message_id]
        @data = @body
      else
        @format_version, @flags, @expires_at, @uuid, @data = @body.unpack("nnNA36A*")
      end
    end

    def self.publishing_options(opts = {})
      flags = 0
      flags |= FLAG_REDUNDANT if opts[:redundant]
      expires_at = now + (opts[:ttl] || DEFAULT_TTL)
      opts = opts.slice(*PUBLISHING_KEYS)
      opts[:message_id] = generate_uuid.to_s
      opts[:headers] = {
        :format_version => FORMAT_VERSION.to_s,
        :flags => flags.to_s,
        :expires_at => expires_at.to_s
      }
      opts
    end

    def self.encode_v1(data, opts = {})
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

    def attempts
      redis.get(key(:attempts)).to_i
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
     redis.get(key(:exceptions)).to_i > exceptions_limit
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
        delete_mutex!
      end
      mutex
    end

    def delete_mutex!
      redis.del(key(:mutex))
      logger.debug "Beetle: deleted mutex: #{msg_id}"
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
        Timeout::timeout(@timeout) { @handler_result = handler.call(self) }
      rescue Exception => @exception
        Beetle::reraise_expectation_errors!
        increment_exception_count!
        if attempts_limit_reached?
          ack!
          logger.debug "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
          return RC::AttemptsLimitReached
        elsif exceptions_limit_reached?
          ack!
          logger.debug "Beetle: reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
          return RC::ExceptionsLimitReached
        else
          delete_mutex!
          timed_out!
          set_delay!
          logger.debug "Beetle: message handler crashed on #{msg_id}"
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
