module Beetle
  class DeduplicationStore
    def initialize(hosts = "localhost:6379", db = 4)
      @hosts = hosts
      @db = db
    end

    # get the Redis instance
    def redis
      @redis ||= find_redis_master
    end

    # list of key suffixes to use for storing values in Redis.
    KEY_SUFFIXES = [:status, :ack_count, :timeout, :delay, :attempts, :exceptions, :mutex, :expires]

    # build a Redis key out of a message id and a given suffix
    def key(msg_id, suffix)
      "#{msg_id}:#{suffix}"
    end

    # list of keys which potentially exist in Redis for the given message id
    def keys(msg_id)
      KEY_SUFFIXES.map{|suffix| key(msg_id, suffix)}
    end

    # extract message id from a given Redis key
    def msg_id(key)
      key =~ /^(msgid:[^:]*:[-0-9a-f]*):.*$/ && $1
    end

    # garbage collect keys in Redis (always assume the worst!)
    def garbage_collect_keys(now = Time.now.to_i)
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

    def set(msg_id, suffix, value)
      with_failover { redis.set(key(msg_id, suffix), value) }
    end

    def setnx(msg_id, suffix, value)
      with_failover { redis.setnx(key(msg_id, suffix), value) }
    end

    def msetnx(msg_id, values)
      values = values.inject({}){|h,(k,v)| h[key(msg_id, k)] = v; h}
      with_failover { redis.msetnx(values) }
    end

    def incr(msg_id, suffix)
      with_failover { redis.incr(key(msg_id, suffix)) }
    end

    def get(msg_id, suffix)
      with_failover { redis.get(key(msg_id, suffix)) }
    end

    def del(msg_id, suffix)
      with_failover { redis.del(key(msg_id, suffix)) }
    end

    def del_keys(msg_id)
      with_failover { redis.del(keys(msg_id)) }
    end

    def exists(msg_id, suffix)
      with_failover { redis.exists(key(msg_id, suffix)) }
    end

    def flushdb
      with_failover { redis.flushdb }
    end

    def with_failover #:yields:
      tries = 0
      begin
        yield
      rescue Exception => e
        Beetle::reraise_expectation_errors!
        logger.error "Beetle: redis connection error '#{e}'"
        if (tries+=1) < 120
          @redis = nil
          sleep 1
          logger.info "Beetle: retrying redis operation"
          retry
        else
          raise NoRedisMaster.new(e.to_s)
        end
      end
    end

    # find the master redis instance
    def find_redis_master
      masters = []
      redis_instances.each do |redis|
        begin
          masters << redis if redis.info[:role] == "master"
        rescue Exception => e
          logger.error "Beetle: could not determine status of redis instance #{redis.server}"
        end
      end
      raise NoRedisMaster.new("unable to determine a new master redis instance") if masters.empty?
      raise TwoRedisMasters.new("more than one redis master instances") if masters.size > 1
      logger.info "Beetle: configured new redis master #{masters.first.server}"
      masters.first
    end

    def redis_instances
      @redis_instances ||= @hosts.split(/ *, */).map{|s| s.split(':')}.map do |host, port|
         Redis.new(:host => host, :port => port, :db => @db)
      end
    end

    def logger
      Beetle.config.logger
    end

  end
end
