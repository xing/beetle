require 'optparse'
require 'daemons'
require 'beetle'

module Beetle
  module Commands
    # Command to start a RedisConfigurationClient daemon.
    #
    #   Usage: beetle configuration_client  [options] -- [client options]
    #
    #   client options:
    #           --redis-master-file FILE     Write redis master server string to FILE
    #           --id, --client-id ID         Set unique client id (default is minastirith.local)
    #           --amqp-servers LIST          AMQP server list (e.g. 192.168.0.1:5672,192.168.0.2:5672)
    #           --config-file PATH           Path to an external yaml config file
    #           --pid-dir DIR                Write pid and log to DIR
    #           --multiple                   Allow multiple clients started in parallel (for testing only)
    #           --force                      Force start (delete stale pid file if necessary)
    #       -v, --verbose                    Set log level to DEBUG
    #       -h, --help                       Show this message
    #
    class ConfigurationClient
      # parses command line options and starts Beetle::RedisConfigurationClient as a daemon
      def self.execute
        command, controller_options, app_options = Daemons::Controller.split_argv(ARGV)

        opts = OptionParser.new
        opts.banner = "Usage: beetle configuration_client #{command} [options] -- [client options]"
        opts.separator ""
        opts.separator "client options:"

        opts.on("--redis-master-file FILE", String, "Write redis master server string to FILE") do |val|
          Beetle.config.redis_server = val
        end

        client_id = nil
        opts.on("--id ID", "--client-id ID", String, "Set unique client id (default is #{RedisConfigurationClient.new.id})") do |val|
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
        opts.on("--pid-dir DIR", String, "Write pid and output to DIR") do |val|
          dir_mode = :normal
          dir = val
        end

        multiple = false
        opts.on("--multiple", "Allow multiple clients") do |val|
          multiple = true
        end

        force = false
        opts.on("--force", "Force start (delete stale pid file if necessary)") do |val|
          force = true
        end

        opts.on("-v", "--verbose", "Set log level to DEBUG") do |val|
          Beetle.config.logger.level = Logger::DEBUG
        end

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        opts.parse!(app_options)

        daemon_options = {
          :multiple   => multiple,
          :log_output => true,
          :dir_mode   => dir_mode,
          :dir        => dir,
          :force      => force
        }

        Daemons.run_proc("redis_configuration_client", daemon_options) do
          client = Beetle::RedisConfigurationClient.new
          client.id = client_id if client_id
          client.start
        end
      end
    end
  end
end
