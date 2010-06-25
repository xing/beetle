require 'optparse'
require 'daemons'
require 'beetle'

module Beetle
  module Commands
    class ConfigurationClient
      def self.execute
        opts = OptionParser.new
        redis_server_strings = []
        opts.on("-r", "--redis-servers host1:port1,host2:port2,...", String) do |val|
          redis_server_strings = val.split(",")
        end

        opts.on("-f", "--redis-master-file path", String) do |val|
          Beetle.config.redis_server = val
        end

        client_id = nil
        opts.on("-i", "--id client-id", String) do |val|
          client_id = val
        end

        dir_mode = nil
        dir = nil
        opts.on("-p", "--pid-dir path", String) do |val|
          dir_mode = :normal
          dir = val
        end

        opts.on("-v", "--verbose") do |val|
          Beetle.config.logger.level = Logger::DEBUG
        end

        opts.parse!(ARGV - ["start", "--"])

        Beetle.config.servers = "localhost:5672, localhost:5673" # rabbitmq

        Daemons.run_proc("redis_configuration_client", :multiple => true, :log_output => true, :dir_mode => dir_mode, :dir => dir) do
          client = Beetle::RedisConfigurationClient.new(redis_server_strings)
          client.id = client_id if client_id
          client.start
        end
      end
    end
  end
end