module Beetle
  class NoDeduplicationStore < DeduplicationStore
    include Logging

    def initialize(config = Beetle.config)
      super(config)
      @data = {}
    end

    def redis
      raise NotImplementedError
    end

    def set(msg_id, suffix, value)
      @data[key(msg_id, suffix)] = value
    end

    def setnx(msg_id, suffix, value)
      @data[key(msg_id, suffix)] ||= value
    end

    def setnx_completed!(_msg_id)
      true
    end

    def mset(msg_id, values)
      values.each do |k, v|
        set(msg_id, k, v)
      end
    end

    def msetnx(msg_id, values)
      values.map { |k, _v| key(msg_id, k) }

      return unless values.keys.intersection(@data.keys).empty?
      mset(msg_id, values)
    end

    def incr(msg_id, suffix)
      @data[key(msg_id, suffix)] ||= 0
      @data[key(msg_id, suffix)] += 1
    end

    def get(msg_id, suffix)
      @data[key(msg_id, suffix)]
    end

    def del(msg_id, suffix)
      @data[key(msg_id, suffix)] = nil
    end

    def del_keys(msg_id)
      keys(msg_id).each do |key|
        @data[key] = nil
      end
    end

    def flushdb
      @data = {}
    end

    def with_failover; end
  end
end
