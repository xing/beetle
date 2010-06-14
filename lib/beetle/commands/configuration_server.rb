require 'optparse'
require 'daemons'
require 'beetle'

module Beetle
  module Commands
    class ConfigurationServer
      def self.execute
        Daemons.run_proc("redis_configuration_server", :log_output => true) do
          opts = OptionParser.new 
          redis_server_strings = []
          opts.on("-r", "--redis-servers host1:port1,host2:port2,...", String) do |val|
            redis_server_strings = val.split(",")
          end
          opts.on("-c", "--client-ids client-id1,client-id2,...", String) do |val|
            Beetle.config.redis_configuration_client_ids = val
          end
          opts.on("-t", "--redis-retry-timeout seconds", Integer) do |val|
            Beetle.config.redis_configuration_master_retry_timeout = val
          end
          opts.parse!(ARGV - ["start", "--"])

          Beetle.config.servers = "localhost:5672, localhost:5673" # rabbitmq

          # set Beetle log level to info, less noisy than debug
          Beetle.config.logger.level = Logger::INFO

          Beetle::RedisConfigurationServer.new(redis_server_strings).start
        end
      end
    end
  end
end