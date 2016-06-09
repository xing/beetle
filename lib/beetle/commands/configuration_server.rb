require 'optparse'
require 'daemons'
require 'beetle'

module Beetle
  module Commands
    # Command to start a RedisConfigurationServer daemon.
    #
    #   Usage: beetle configuration_server  [options] -- [server options]
    #
    #   server options:
    #           --redis-servers LIST         Required for start command (e.g. 192.168.0.1:6379,192.168.0.2:6379)
    #           --client-ids LIST            Clients that have to acknowledge on master switch (e.g. client-id1,client-id2)
    #           --redis-master-file FILE     Write redis master server string to FILE
    #           --redis-retry-interval SEC   Number of seconds to wait between master checks
    #           --amqp-servers LIST          AMQP server list (e.g. 192.168.0.1:5672,192.168.0.2:5672)
    #           --config-file PATH           Path to an external yaml config file
    #           --pid-dir DIR                Write pid and log to DIR
    #           --force                      Force start (delete stale pid file if necessary)
    #       -v, --verbose
    #       -h, --help                       Show this message
    #
    class ConfigurationServer
      # parses command line options and starts Beetle::RedisConfigurationServer as a daemon
      def self.execute
        command, controller_options, app_options = Daemons::Controller.split_argv(ARGV)

        opts = OptionParser.new
        opts.banner = "Usage: beetle configuration_server #{command} [options] -- [server options]"
        opts.separator ""
        opts.separator "server options:"

        opts.on("--redis-servers LIST", Array, "Required for start command (e.g. 192.168.0.1:6379,192.168.0.2:6379)") do |val|
          Beetle.config.redis_servers = val.join(",")
        end

        opts.on("--client-ids LIST", "Clients that have to acknowledge on master switch (e.g. client-id1,client-id2)") do |val|
          Beetle.config.redis_configuration_client_ids = val
        end

        opts.on("--redis-master-file FILE", String, "Write redis master server string to FILE") do |val|
          Beetle.config.redis_server = val
        end

        opts.on("--redis-retry-interval SEC", Integer, "Number of seconds to wait between master checks") do |val|
          Beetle.config.redis_configuration_master_retry_interval = val
        end

        opts.on("--amqp-servers LIST", String, "AMQP server list (e.g. 192.168.0.1:5672,192.168.0.2:5672)") do |val|
          Beetle.config.servers = val
        end

        opts.on("--config-file PATH", String, "Path to an external yaml config file") do |val|
          Beetle.config.config_file = val
        end

        dir_mode = nil
        dir = nil
        opts.on("--pid-dir DIR", String, "Write pid and output to DIR") do |val|
          dir_mode = :normal
          dir = val
        end

        force = false
        opts.on("--force", "Force start (delete stale pid file if necessary)") do |val|
          force = true
        end

        opts.on("-v", "--verbose") do |val|
          Beetle.config.logger.level = Logger::DEBUG
        end

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        opts.parse!(app_options)

        if command =~ /start|run/ && Beetle.config.redis_servers.blank?
          puts opts
          exit
        end

        daemon_options = {
          :log_output => true,
          :dir_mode   => dir_mode,
          :dir        => dir,
          :force      => force
        }

        Daemons.run_proc("redis_configuration_server", daemon_options) do
          config_server =  Beetle::RedisConfigurationServer.new
          Beetle::RedisConfigurationHttpServer.config_server = config_server
          http_server_port = RUBY_PLATFORM =~ /darwin/ ? 9080 : 8080
          EM.run do
            config_server.start
            EM.start_server '0.0.0.0', http_server_port, Beetle::RedisConfigurationHttpServer
          end
        end
      end
    end
  end
end
