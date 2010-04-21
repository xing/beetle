require 'timeout'
module Beetle
  class Configurator < Beetle::Handler

    @@active_master  = nil
    @@client         = Beetle::Client.new
    @@alive_signals  = {}
    cattr_accessor :client
    cattr_accessor :active_master
    cattr_accessor :alive_signals

    class << self
      def find_active_master
        return if active_master && reachable?(active_master)
        self.active_master = nil
        client.deduplication_store.redis_instances.each do |redis|
          if reachable?(redis)
            self.active_master = redis
          end
        end
      end

      def give_master(payload)
        # stores our list of servers and their ping times
        # alive_signals[server_name] = Time.now
        active_master
      end

      def promise(payload)

      end

      def reconfigured(payload)

      end

      def going_offline(payload)

      end

      private

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

    def process
      json = ActiveSupport::JSON.decode(message.data)
      self.class.send(json.delete("op").to_sym, json)
    end

  end
end

# EM.add_periodic_timer(0.5) {
#   Beetle::Configurator.find_active_master
# }