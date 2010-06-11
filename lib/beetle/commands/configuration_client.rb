require 'optparse'
require 'daemons'
require 'beetle'

module Beetle
  module Commands
    class ConfigurationClient
      def self.execute
        Daemons.run_proc("redis_configuration_client", :multiple => true, :log_output => true) do
          opts = OptionParser.new 

          opts.on("-r", "--redis-servers host1:port1,host2:port2,...", String) do |val|
            Beetle.config.redis_hosts = val || "localhost:6379, localhost:6380"
          end

          opts.on("-f", "--redis-master-file path", String) do |val|
            Beetle.config.redis_master_file_path = val
          end

          client_id = nil
          opts.on("-i", "--id client-id", String) do |val|
            client_id = val
          end

          opts.parse!(ARGV - ["start", "--"])

          Beetle.config.servers = "localhost:5672, localhost:5673" # rabbitmq

          # set Beetle log level to info, less noisy than debug
          Beetle.config.logger.level = Logger::INFO

          client = Beetle::RedisConfigurationClient.new
          client.id = client_id if client_id
          client.start
        end
      end
    end
  end
end