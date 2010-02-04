module Bandersnatch
  class Message
    FORMAT_VERSION = 1
    FLAG_REDUNDANT = 2
    DEFAULT_TTL = 1.days
    EXPIRE_AFTER = 1.day

    attr_reader :queue, :header, :body, :uuid, :data, :format_version, :flags, :expires_at
    attr_accessor :retriable, :timeout, :server

    def initialize(queue, header, body)
      @queue = queue
      @header = header
      @body   = body
      decode
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

    def retriable?
      !!retriable
    end

    def set_timeout!
      redis.set(timeout_key, Time.now.to_i + timeout)
    end

    def timed_out?
      redis.get(timeout_key).to_i < Time.now.to_i
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

    def key_exists?
      new_message = redis.setnx(status_key, "incomplete")
      unless new_message
        logger.debug "received duplicate message: #{status_key} on queue: #{@queue}"
      end
      !new_message
    end

    def self.redis
      @redis ||= Redis.new
    end

    def self.redis=redis
      @redis = redis
    end

    def process(block)
      begin
        process_internal(block)
      rescue Exception => e
        logger.warn "Exception '#{e}' during invocation of message handler for #{self}"
        logger.warn "Backtrace: #{e.backtrace.join("\n")}"
        raise
      end
    end

    def status_key
      keys[:status] ||= "msgid:#{queue}:#{uuid}:status"
    end

    def ack_count_key
      keys[:ack_count] ||= "msgid:#{queue}:#{uuid}:ack_count"
    end

    def timeout_key
      keys[:timeout] ||= "msgid:#{queue}:#{uuid}:timeout"
    end

    def keys
      @keys ||= {}
    end

    private

    def process_internal(block)
      if expired?
        logger.warn "Ignored expired message!"
        ack!
        return
      end

      if redundant?
        process_redundant_message(block)
      else
        process_non_redundant_message(block)
      end
    end

    def run_handler_safely!(block)
      set_timeout!
      begin
        block.call(self)
      rescue Exception => e
        timed_out!
        raise HandlerCrash.new(e)
      end
      completed!
      ack!
    end

    def process_non_redundant_message(block)
      if retriable?
        block.call(self)
        ack!
      else
        ack!
        block.call(self)
      end
    end

    def process_redundant_message(block)
      if retriable?
        process_retriable_redundant_message(block)
      else
        process_non_retriable_redundant_message(block)
      end
    end

    def process_non_retriable_redundant_message(block)
      if key_exists?
        ack!
      else
        ack!
        block.call(self)
      end
    end

    def process_retriable_redundant_message(block)
      if !key_exists?
        run_handler_safely!(block)
      elsif completed?
        ack!
      elsif !timed_out?
        raise HandlerTimeout
      else
        run_handler_safely!(block)
      end
    end

    def redis
      self.class.redis
    end

    def logger
      self.class.logger
    end

    def self.logger
      Bandersnatch.config.logger
    end

    def ack!
      header.ack
      if redundant? && redis.incr(ack_count_key) == 2
        redis.del(*keys.values)
      end
    end
  end
end
