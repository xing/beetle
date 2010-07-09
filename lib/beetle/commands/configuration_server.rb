require 'optparse'
require 'daemons'
require 'beetle'

module Beetle
  module Commands
    # Command to start a RedisConfigurationServer daemon.
    # Use via <tt>beetle configuration_server</tt>.
    class ConfigurationServer
      def self.execute
        command, controller_options, app_options = Daemons::Controller.split_argv(ARGV)

        opts = OptionParser.new
        opts.banner = "Usage: beetle configuration_server #{command} [options] -- [server options]"
        opts.separator ""
        opts.separator "server options:"

        opts.on("--redis-servers LIST", Array, "Required for start command (e.g. 192.168.0.1:6379,192.168.0.2:6379)") do |val|
          Beetle.config.redis_server_list = val
        end

        opts.on("--client-ids LIST", "Clients that have to acknowledge on master switch (e.g. client-id1,client-id2)") do |val|
          Beetle.config.redis_configuration_client_ids = val
        end

        opts.on("--redis-master-file FILE", String, "Write redis master server string to FILE") do |val|
          Beetle.config.redis_server = val
        end

        opts.on("--redis-retry-timeout SEC", Integer, "Number of seconds to wait between master checks") do |val|
          Beetle.config.redis_configuration_master_retry_timeout = val
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

        opts.on("-v", "--verbose") do |val|
          Beetle.config.logger.level = Logger::DEBUG
        end

        opts.parse!(app_options)

        if command =~ /start|run/ && Beetle.config.redis_server_list.empty?
          puts opts
          exit
        end

        Daemons.run_proc("redis_configuration_server", :log_output => true, :dir_mode => dir_mode, :dir => dir) do
          Beetle::RedisConfigurationServer.new.start
        end
      end
    end
  end
end
