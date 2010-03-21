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
      @queue  = queue
      @header = header
      @body   = body
      setup(opts)
      decode
    end

    def setup(opts) #:nodoc:
      @server           = opts[:server]
      @timeout          = opts[:timeout]    || DEFAULT_HANDLER_TIMEOUT
      @delay            = opts[:delay]      || DEFAULT_HANDLER_EXECUTION_ATTEMPTS_DELAY
      @attempts_limit   = opts[:attempts]   || DEFAULT_HANDLER_EXECUTION_ATTEMPTS
      @exceptions_limit = opts[:exceptions] || DEFAULT_EXCEPTION_LIMIT
      @attempts_limit   = @exceptions_limit + 1 if @attempts_limit <= @exceptions_limit
    end

    # extracts various values form the AMQP header properties
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

    # TODO: remove after next release
    def self.encode_v1(data, opts = {}) #:nodoc:
      expires_at = now + (opts[:ttl] || DEFAULT_TTL).to_i
      flags = 0
      flags |= FLAG_REDUNDANT if opts[:redundant]
      [1, flags, expires_at, generate_uuid.to_s, data.to_s].pack("nnNA36A*")
    end

    # unique message id. used to form various Redis keys.
    def msg_id
      @msg_id ||= "msgid:#{queue}:#{uuid}"
    end

    # current time (UNIX timestamp)
    def now #:nodoc:
      Time.now.to_i
    end

    # current time (UNIX timestamp)
    def self.now #:nodoc:
      Time.now.to_i
    end

    # a message has expired if the header expiration timestamp is msaller than the current time
    def expired?
      @expires_at < now
    end

    # generate uuid for publishing
    def self.generate_uuid
      UUID4R::uuid(1)
    end

    # whether the publisher has tried sending this message to two servers
    def redundant?
      @flags & FLAG_REDUNDANT == FLAG_REDUNDANT
    end

    # whether this is a message we can process without accessing redis
    def simple?
      !redundant? && attempts_limit == 1
    end

    # store handler timeout timestamp into Redis
    def set_timeout!
      with_redis_failover { redis.set(key(:timeout), now + timeout) }
    end

    # handler timed out?
    def timed_out?
      with_redis_failover { (t = redis.get(key(:timeout))) && t.to_i < now }
    end

    # reset handler timeout in Redis
    def timed_out!
      with_redis_failover { redis.set(key(:timeout), 0) }
    end

    # message handling completed?
    def completed?
      with_redis_failover { redis.get(key(:status)) == "completed" }
    end

    # mark message handling complete in Redis
    def completed!
      with_redis_failover { redis.set(key(:status), "completed") }
      timed_out!
    end

    # whether we should wait before running the handler
    def delayed?
      with_redis_failover { (t = redis.get(key(:delay))) && t.to_i > now }
    end

    # store delay value in REdis
    def set_delay!
      with_redis_failover { redis.set(key(:delay), now + delay) }
    end

    # how many times we already tried running the handler
    def attempts
      with_redis_failover { redis.get(key(:attempts)).to_i }
    end

    # record the fact that we are trying to run the handler
    def increment_execution_attempts!
      with_redis_failover { redis.incr(key(:attempts)) }
    end

    # whether we have already tried running the handler as often as specified when the handler was registered
    def attempts_limit_reached?
      with_redis_failover { (limit = redis.get(key(:attempts))) && limit.to_i >= attempts_limit }
    end

    # increment number of exception occurences in Redis
    def increment_exception_count!
      with_redis_failover { redis.incr(key(:exceptions)) }
    end

    # whether the number of exceptions has exceeded the limit set when the handler was registered
    def exceptions_limit_reached?
      with_redis_failover { redis.get(key(:exceptions)).to_i > exceptions_limit }
    end

    # have we already seen this message? if not, set the status to "incomplete" and store
    # the message exipration time in Redis.
    def key_exists?
      with_redis_failover do
        old_message = 0 == redis.msetnx(key(:status) =>"incomplete", key(:expires) => @expires_at)
        if old_message
          logger.debug "Beetle: received duplicate message: #{key(:status)} on queue: #{@queue}"
        end
        old_message
      end
    end

    # aquire execution mutex before we run the handler (and delete it if we can't aquire it).
    def aquire_mutex!
      with_redis_failover do
        if mutex = redis.setnx(key(:mutex), now)
          logger.debug "Beetle: aquired mutex: #{msg_id}"
        else
          delete_mutex!
        end
        mutex
      end
    end

    # delete execution mutex
    def delete_mutex!
      with_redis_failover do
        redis.del(key(:mutex))
        logger.debug "Beetle: deleted mutex: #{msg_id}"
      end
    end

    # get the Redis instance
    def self.redis
      @redis ||= find_redis_master
    end

    # set the redis instance
    def self.redis=(redis)
      @redis = redis
    end

    # find the master redis instance
    def self.find_redis_master
      masters = []
      redis_instances.each do |redis|
        begin
          masters << redis if redis.info[:role] == "master"
        rescue Exception => e
          logger.error "Beetle: could not determine status of instance #{redis.server}"
        end
      end
      raise "unable to determine a new master redis instance" if masters.empty?
      raise "more than one master" if masters.size > 1
      logger.debug "Beetle: configured new redis master #{masters.first.server}"
      masters.first
    end

    def self.switch_redis
      slave = redis_instances.find{|r| r.server != redis.server}
      redis.shutdown rescue nil
      logger.info "Beetle: shut down master #{redis.server}"
      self.redis = nil
      slave.slaveof("no one")
      logger.info "Beetle: enabled master mode on #{slave.server}"
    end

    def self.redis_instances
      @redis_instances ||= Beetle.config.redis_hosts.split(/ *, */).map{|s| s.split(':')}.map do |host, port|
         Redis.new(:host => host, :port => port, :db => Beetle.config.redis_db)
      end
    end

    def with_redis_failover #:yields:
      tries = 0
      begin
        yield
      rescue Exception => e
        logger.error "Beetle: redis connection error '#{e}'"
        if (tries+=1) < 120
          self.class.redis = nil
          sleep 1
          logger.info "Beetle: retrying redis operation"
          retry
        end
      end
    end

    # list of key suffixes to use for storing values in Redis.
    KEY_SUFFIXES = [:status, :ack_count, :timeout, :delay, :attempts, :exceptions, :mutex, :expires]

    # build a Redis key out of the message id of this message and a given suffix
    def key(suffix)
      self.class.key(msg_id, suffix)
    end

    # list of keys which potentially exist in Redis for this messsage
    def keys
      self.class.keys(msg_id)
    end

    # build a Redis key out of a message id and a given suffix
    def self.key(msg_id, suffix)
      "#{msg_id}:#{suffix}"
    end

    # list of keys which potentially exist in Redis for the given message id
    def self.keys(msg_id)
      KEY_SUFFIXES.map{|suffix| key(msg_id, suffix)}
    end

    # extract message id from a given Redis key
    def self.msg_id(key)
      key =~ /^(msgid:[^:]*:[-0-9a-f]*):.*$/ && $1
    end

    # garbage collect keys in Redis (always assume the worst!)
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

    # process this message and do not allow any exception to escape to the caller
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
      elsif simple?
        ack!
        run_handler(handler) == RC::HandlerCrash ? RC::AttemptsLimitReached : RC::OK
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

    def run_handler(handler)
      Timeout::timeout(@timeout) { @handler_result = handler.call(self) }
      RC::OK
    rescue Exception => @exception
      Beetle::reraise_expectation_errors!
      logger.debug "Beetle: message handler crashed on #{msg_id}"
      RC::HandlerCrash
    ensure
      ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord)
    end

    def run_handler!(handler)
      increment_execution_attempts!
      case result = run_handler(handler)
      when RC::OK
        completed!
        ack!
        result
      else
        handler_failed!(result)
      end
    end

    def handler_failed!(result)
      increment_exception_count!
      if attempts_limit_reached?
        ack!
        logger.debug "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
        RC::AttemptsLimitReached
      elsif exceptions_limit_reached?
        ack!
        logger.debug "Beetle: reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
        RC::ExceptionsLimitReached
      else
        delete_mutex!
        timed_out!
        set_delay!
        result
      end
    end

    def redis
      self.class.redis
    end

    def logger
      @logger ||= self.class.logger
    end

    def self.logger
      Beetle.config.logger
    end

    # ack the message for rabbit. delete all keys if we are sure this is the last message
    # with the given message id. if deleting the keys fails (network problem for example),
    # the keys will be deleted by the class method garbage_collect_keys.
    def ack!
      #:doc:
      logger.debug "Beetle: ack! for message #{msg_id}"
      header.ack
      return if simple?
      with_redis_failover do
        if !redundant? || redis.incr(key(:ack_count)) == 2
          redis.del(keys)
        end
      end
    end
  end
end
