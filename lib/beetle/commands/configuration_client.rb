require 'optparse'
require 'daemons'
require 'beetle'

module Beetle
  module Commands
    # Command to start a RedisConfigurationClient daemon.
    # Use via <tt>beetle configuration_client</tt>
    class ConfigurationClient
      def self.execute
        command, controller_options, app_options = Daemons::Controller.split_argv(ARGV)

        opts = OptionParser.new
        opts.banner = "Usage: beetle configuration_client #{command} [options] -- [client options]"
        opts.separator ""
        opts.separator "client options:"

        redis_server_strings = []
        opts.on("--redis-servers LIST", Array, "Required for start command (e.g. 192.168.0.1:6379,192.168.0.2:6379)") do |val|
          redis_server_strings = val
        end

        opts.on("--redis-master-file FILE", String, "Write redis master server string to FILE") do |val|
          Beetle.config.redis_server = val
        end

        client_id = nil
        opts.on("--id ID", "--client-id ID", String, "Set custom unique client id (default is #{RedisConfigurationClient.new.id})") do |val|
          client_id = val
        end

        opts.on("--amqp-servers LIST", String, "AMQP server list (e.g. 192.168.0.1:5672,192.168.0.2:5672)") do |val|
          Beetle.config.servers = val
        end

        opts.on("--config-file PATH", String, "Path to an external yaml config file") do |val|
          Beetle.config.config_file = val
        end

        dir_mode = nil
        dir = nil
        opts.on("--pid-dir DIR", String, "Write pid and log to DIR") do |val|
          dir_mode = :normal
          dir = val
        end

        opts.on("-v", "--verbose", "Set log level to DEBUG") do |val|
          Beetle.config.logger.level = Logger::DEBUG
        end

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        opts.parse!(app_options)

        if command =~ /start|run/ && redis_server_strings.empty?
          puts opts
          exit
        end

        Daemons.run_proc("redis_configuration_client", :multiple => true, :log_output => true, :dir_mode => dir_mode, :dir => dir) do
          client = Beetle::RedisConfigurationClient.new(redis_server_strings)
          client.id = client_id if client_id
          client.start
        end
      end
    end
  end
end