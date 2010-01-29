module Bandersnatch
  class Message
    FORMAT_VERSION = 1
    FLAG_UUID = 1
    DEFAULT_TTL = 1.days
    EXPIRE_AFTER = 1.day

    attr_reader :server, :header, :body, :uuid, :data, :format_version, :flags, :expires_at

    def initialize(server, header, body)
      @server = server
      @header = header
      @body   = body
      decode
    end

    def decode
      @format_version, @flags, @expires_at, @data = @body.unpack("nnNA*")
      if (@flags & FLAG_UUID == FLAG_UUID)
        @uuid, @data = @data.unpack("A36A*")
      else
        @uuid = nil
      end
    end

    def expired?(expiration_time = Time.now.to_i)
      @expires_at < expiration_time
    end

    def self.encode(data, opts = {})
      expires_at = ttl_to_expiration_time(opts[:ttl] || DEFAULT_TTL)
      if opts[:with_uuid]
        [FORMAT_VERSION, FLAG_UUID, expires_at, generate_uuid.to_s, data.to_s].pack("nnNA36A*")
      else
        [FORMAT_VERSION, 0, expires_at, data.to_s].pack("nnNA*")
      end
    end

    def self.ttl_to_expiration_time(ttl)
      Time.now.to_i + ttl.to_i
    end

    def self.generate_uuid
      UUID4R::uuid(1)
    end

    def has_uuid?
      !!@uuid
    end

    def insert_id(queue)
      return uuid.blank? || new_in_queue?(queue)
    end

    def self.redis
      @redis ||= Redis.new(:host => "rofl")
    end

    def self.redis=redis
      @redis = redis
    end

    private

    def redis
      self.class.redis
    end

    def new_in_queue?(queue)
      message_id = "msgid:#{queue}:#{uuid}"
      new_message = redis.setnx(message_id, Time.now.to_s(:db))
      unless new_message
        logger.debug "received duplicate message: #{message_id} on queue: #{queue} (identifier: #{message_id})"
      end
      new_message
    end

    def logger
      self.class.logger
    end

    def self.logger
      Bandersnatch.config.logger
    end
  end
end
