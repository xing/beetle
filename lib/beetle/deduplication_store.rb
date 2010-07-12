module Beetle
  # The deduplication store is used internally by Beetle::Client to store information on
  # the status of message processing. This includes:
  # * how often a message has already been seen by some consumer
  # * whether a message has been processed successfully
  # * how many attempts have been made to execute a message handler for a given message
  # * how long we should wait before trying to execute the message handler after a failure
  # * how many exceptions have been raised during previous execution attempts
  # * how long we should wait before trying to perform the next execution attempt
  # * whether some other process is already trying to execute the message handler
  #
  # It also provides a method to garbage collect keys for expired messages.
  class DeduplicationStore
    include Logging

    def initialize(config = Beetle.config)
      @config = config
      @current_master = nil
      @last_time_master_file_changed = nil
    end

    # get the Redis instance
    def redis
      redis_master_source = @config.redis_server =~ /^\S+\:\d+$/ ? "server_string" : "master_file"
      _eigenclass_.class_eval <<-EVALS, __FILE__, __LINE__
        def redis
          redis_master_from_#{redis_master_source}
        end
      EVALS
      redis
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
      threshold = now + @config.gc_threshold
      keys.each do |key|
        expires_at = redis.get key
        if expires_at && expires_at.to_i < threshold
          msg_id = msg_id(key)
          redis.del(keys(msg_id))
        end
      end
    end

    # unconditionally store a (key,value) pair with given <tt>suffix</tt> for given <tt>msg_id</tt>.
    def set(msg_id, suffix, value)
      with_failover { redis.set(key(msg_id, suffix), value) }
    end

    # store a (key,value) pair with given <tt>suffix</tt> for given <tt>msg_id</tt> if it doesn't exists yet.
    def setnx(msg_id, suffix, value)
      with_failover { redis.setnx(key(msg_id, suffix), value) }
    end

    # store some key/value pairs if none of the given keys exist.
    def msetnx(msg_id, values)
      values = values.inject([]){|a,(k,v)| a.concat([key(msg_id, k), v])}
      with_failover { redis.msetnx(*values) }
    end

    # increment counter for key with given <tt>suffix</tt> for given <tt>msg_id</tt>. returns an integer.
    def incr(msg_id, suffix)
      with_failover { redis.incr(key(msg_id, suffix)) }
    end

    # retrieve the value with given <tt>suffix</tt> for given <tt>msg_id</tt>. returns a string.
    def get(msg_id, suffix)
      with_failover { redis.get(key(msg_id, suffix)) }
    end

    # delete key with given <tt>suffix</tt> for given <tt>msg_id</tt>.
    def del(msg_id, suffix)
      with_failover { redis.del(key(msg_id, suffix)) }
    end

    # delete all keys associated with the given <tt>msg_id</tt>.
    def del_keys(msg_id)
      with_failover { redis.del(*keys(msg_id)) }
    end

    # check whether key with given suffix exists for a given <tt>msg_id</tt>.
    def exists(msg_id, suffix)
      with_failover { redis.exists(key(msg_id, suffix)) }
    end

    # flush the configured redis database. useful for testing.
    def flushdb
      with_failover { redis.flushdb }
    end

    # performs redis operations by yielding a passed in block, waiting for a new master to
    # show up on the network if the operation throws an exception. if a new master doesn't
    # appear after the configured timeout interval, we raise an exception.
    def with_failover #:nodoc:
      end_time = Time.now.to_i + @config.redis_failover_timeout.to_i
      begin
        yield
      rescue Exception => e
        Beetle::reraise_expectation_errors!
        logger.error "Beetle: redis connection error #{e} #{@config.redis_server} (#{e.backtrace[0]})"
        if Time.now.to_i < end_time
          sleep 1
          logger.info "Beetle: retrying redis operation"
          retry
        else
          raise NoRedisMaster.new(e.to_s)
        end
      end
    end

    # set current redis master instance (as specified in the Beetle::Configuration)
    def redis_master_from_server_string
      @current_master ||= Redis.from_server_string(@config.redis_server, :db => @config.redis_db)
    end

    # set current redis master from master file
    def redis_master_from_master_file
      set_current_redis_master_from_master_file if redis_master_file_changed?
      @current_master
    rescue Errno::ENOENT
      nil
    end

    # redis master file changed outside the running process?
    def redis_master_file_changed?
      @last_time_master_file_changed != File.mtime(@config.redis_server)
    end

    # set current redis master from server:port string contained in the redis master file
    def set_current_redis_master_from_master_file
      @last_time_master_file_changed = File.mtime(@config.redis_server)
      server_string = read_master_file
      @current_master = !server_string.blank? ? Redis.from_server_string(server_string, :db => @config.redis_db) : nil
    end

    # server:port string from the redis master file
    def read_master_file
      File.read(@config.redis_server).chomp
    end

    def _eigenclass_ #:nodoc:
      class << self; self; end
    end
  end
end
