require 'timeout'
module Beetle
  class RedisConfigurationClient < Beetle::Handler

    @@active_master         = nil
    @@client                = Beetle::Client.new
    cattr_accessor :active_master
    cattr_accessor :client

    class << self
      def find_active_server(master, slave)
        client.config.redis_configuration_master_retries.times do
          sleep client.config.redis_configuration_master_retry_timeout.to_i
          # 
        end
      end

      def is_valid_master(redis)
        redis.info[:]
      end

      def is_valid_slave(redis)
        redis.info[:]
      end

      # DUP
      def reachable?(redis)
        begin
          Timeout::timeout(5) {
            !!redis.info
          }
        rescue Timeout::Error => e
          false
        end
      end

    end
  end
end
