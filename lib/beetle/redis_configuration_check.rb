module Beetle
  module RedisConfigurationCheck #:nodoc:
    def check_redis_configuration
      raise ConfigurationError.new("Redis failover needs two or more redis servers") if config.redis_server_list.size < 2
    end
  end
end
