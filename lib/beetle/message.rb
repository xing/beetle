require "timeout"

module Beetle
  # Instances of class Message are created when a subscription callback fires. Class
  # Message contains the code responsible for message deduplication and determining if it
  # should retry executing the message handler after a handler has crashed (or forcefully
  # aborted).
  class Message
    include Logging

    # current message format version
    FORMAT_VERSION = 1
    # flag for encoding redundant messages
    FLAG_REDUNDANT = 1
    # default lifetime of messages
    DEFAULT_TTL = 1.day
    # forcefully abort a running handler after this many seconds.
    # can be overriden when registering a handler.
    DEFAULT_HANDLER_TIMEOUT = 600.seconds
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
    # the uuid of the message
    attr_reader :uuid
    # unix timestamp when the message was published
    attr_reader :timestamp
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
    # maximum wait time for message handler retries (uses exponential backoff)
    attr_reader :max_delay
    # how many times we should try to run the handler
    attr_reader :attempts_limit
    # how many exceptions we should tolerate before giving up
    attr_reader :exceptions_limit
    # array of exceptions accepted to be rescued and retried
    attr_reader :on_exceptions
    # exception raised by handler execution
    attr_reader :exception
    # value returned by handler execution
    attr_reader :handler_result

    def initialize(queue, header, body, opts = {})
      @queue  = queue
      @header = header
      @data   = body
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
      @on_exceptions    = opts[:on_exceptions] || nil
      @store            = opts[:store]
      max_delay         = opts[:max_delay] || @delay
      @max_delay        = max_delay if max_delay >= 2*@delay
    end

    # extracts various values from the AMQP header properties
    def decode #:nodoc:
      # p header.attributes
      amqp_headers = header.attributes
      @uuid = amqp_headers[:message_id]
      @timestamp = amqp_headers[:timestamp]
      headers = amqp_headers[:headers].symbolize_keys
      @format_version = headers[:format_version].to_i
      @flags = headers[:flags].to_i
      @expires_at = headers[:expires_at].to_i
    rescue Exception => @exception
      Beetle::reraise_expectation_errors!
      logger.error "Could not decode message. #{self.inspect}"
    end

    # build hash with options for the publisher
    def self.publishing_options(opts = {}) #:nodoc:
      flags = 0
      flags |= FLAG_REDUNDANT if opts[:redundant]
      expires_at = now + (opts[:ttl] || DEFAULT_TTL)
      opts = opts.slice(*PUBLISHING_KEYS)
      opts[:message_id] = generate_uuid.to_s
      opts[:timestamp] = now
      headers = {}
      headers.merge!(opts[:headers]) if opts[:headers]
      headers.reject! {|k,v| v.nil? }
      headers.each {|k,v| headers[k] = v.to_s if v.is_a?(Symbol) }
      headers.merge!(
        :format_version => FORMAT_VERSION.to_s,
        :flags => flags.to_s,
        :expires_at => expires_at.to_s
      )
      opts[:headers] = headers
      opts
    end

    # the routing key
    def routing_key
      @routing_key ||= if x_death = header.attributes[:headers]["x-death"]
        x_death.last["routing-keys"].first
      else
        header.routing_key
      end
    end
    alias_method :key, :routing_key

    # unique message id. used to form various keys in the deduplication store.
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

    # a message has expired if the header expiration timestamp is smaller than the current time
    def expired?
      @expires_at < now
    end

    # generate uuid for publishing
    def self.generate_uuid
      UUID4R::uuid(4)
    end

    # whether the publisher has tried sending this message to two servers
    def redundant?
      @flags & FLAG_REDUNDANT == FLAG_REDUNDANT
    end

    # whether this is a message we can process without accessing the deduplication store
    def simple?
      !redundant? && attempts_limit == 1
    end

    # store handler timeout timestamp in the deduplication store
    def set_timeout!
      @store.set(msg_id, :timeout, now + timeout)
    end

    # handler timed out?
    def timed_out?
      (t = @store.get(msg_id, :timeout)) && t.to_i < now
    end

    # reset handler timeout in the deduplication store
    def timed_out!
      @store.set(msg_id, :timeout, 0)
    end

    # message handling completed?
    def completed?
      @store.get(msg_id, :status) == "completed"
    end

    # mark message handling complete in the deduplication store
    def completed!
      @store.mset(msg_id, :status => "completed", :timeout => 0)
    end

    # whether we should wait before running the handler
    def delayed?
      (t = @store.get(msg_id, :delay)) && t.to_i > now
    end

    # store delay value in the deduplication store
    def set_delay!
      @store.set(msg_id, :delay, now + next_delay(attempts))
    end

    # how many times we already tried running the handler
    def attempts
      @store.get(msg_id, :attempts).to_i
    end

    # record the fact that we are trying to run the handler
    def increment_execution_attempts!
      @store.incr(msg_id, :attempts)
    end

    # whether we have already tried running the handler as often as specified when the handler was registered
    def attempts_limit_reached?
      (limit = @store.get(msg_id, :attempts)) && limit.to_i >= attempts_limit
    end

    # increment number of exception occurences in the deduplication store
    def increment_exception_count!
      @store.incr(msg_id, :exceptions)
    end

    # whether the number of exceptions has exceeded the limit set when the handler was registered
    def exceptions_limit_reached?
      @store.get(msg_id, :exceptions).to_i > exceptions_limit
    end

    def exception_accepted?
      on_exceptions.nil? || on_exceptions.any?{ |klass| @exception.is_a? klass}
    end

    # have we already seen this message? if not, set the status to "incomplete" and store
    # the message exipration timestamp in the deduplication store.
    def key_exists?
      old_message = !@store.msetnx(msg_id, :status =>"incomplete", :expires => @expires_at, :timeout => now + timeout)
      if old_message
        logger.debug "Beetle: received duplicate message: #{msg_id} on queue: #{@queue}"
      end
      old_message
    end

    # aquire execution mutex before we run the handler (and delete it if we can't aquire it).
    def aquire_mutex!
      if mutex = @store.setnx(msg_id, :mutex, now)
        logger.debug "Beetle: aquired mutex: #{msg_id}"
      else
        delete_mutex!
      end
      mutex
    end

    # delete execution mutex
    def delete_mutex!
      @store.del(msg_id, :mutex)
      logger.debug "Beetle: deleted mutex: #{msg_id}"
    end

    def fetch_status_delay_timeout_attempts_exceptions
      @store.mget(msg_id, [:status, :delay, :timeout, :attempts, :exceptions])
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
      if @exception
        ack!
        RC::DecodingError
      elsif expired?
        logger.warn "Beetle: ignored expired message (#{msg_id})!"
        ack!
        RC::Ancient
      elsif simple?
        ack!
        run_handler(handler) == RC::HandlerCrash ? RC::AttemptsLimitReached : RC::OK
      elsif !key_exists?
        run_handler!(handler)
      else
        status, delay, timeout, attempts, exceptions = fetch_status_delay_timeout_attempts_exceptions
        if status == "completed"
          ack!
          RC::OK
        elsif delay && delay.to_i > now
          logger.warn "Beetle: ignored delayed message (#{msg_id})!"
          RC::Delayed
        elsif !(timeout && timeout.to_i < now)
          RC::HandlerNotYetTimedOut
        elsif attempts.to_i >= attempts_limit
          completed!
          ack!
          logger.warn "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
          RC::AttemptsLimitReached
        elsif exceptions.to_i > exceptions_limit
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

    def run_handler(handler)
      Timer.timeout(@timeout.to_f) { @handler_result = handler.call(self) }
      RC::OK
    rescue Exception => @exception
      ActiveRecord::Base.clear_all_connections! if defined?(ActiveRecord)
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
        completed!
        ack!
        logger.debug "Beetle: reached the handler execution attempts limit: #{attempts_limit} on #{msg_id}"
        RC::AttemptsLimitReached
      elsif exceptions_limit_reached?
        completed!
        ack!
        logger.debug "Beetle: reached the handler exceptions limit: #{exceptions_limit} on #{msg_id}"
        RC::ExceptionsLimitReached
      elsif !exception_accepted?
        completed!
        ack!
        logger.debug "Beetle: `#{@exception.class.name}` not accepted: `on_exceptions`=[#{on_exceptions.join(',')}] on #{msg_id}"
        RC::ExceptionNotAccepted
      else
        delete_mutex!
        timed_out!
        set_delay!
        result
      end
    end

    # ack the message for rabbit. deletes all keys associated with this message in the
    # deduplication store if we are sure this is the last message with the given msg_id.
    def ack!
      #:doc:
      logger.debug "Beetle: ack! for message #{msg_id}"
      header.ack
      return if simple? # simple messages don't use the deduplication store
      if !redundant? || @store.incr(msg_id, :ack_count) == 2
        @store.del_keys(msg_id)
      end
    end

    def next_delay(n)
      if max_delay
        [delay * (2**n), max_delay].min
      else
        delay
      end
    end
  end
end
