require 'optparse'
require 'beetle'

module Beetle
  module Commands
    # Command to garbage collect the deduplication store
    #
    #   Usage: beetle garbage_collect_deduplication_store [options]
    #
    #   options:
    #       --redis-servers LIST         Required (e.g. 192.168.0.1:6379,192.168.0.2:6379)
    #       --config-file PATH           Path to an external yaml config file
    #       -v, --verbose
    #       -h, --help                   Show this message
    #
    class GarbageCollectDeduplicationStore
      # parses command line options and starts Beetle::RedisConfigurationServer as a daemon
      def self.execute
        opts = OptionParser.new
        opts.banner = "Usage: beetle garbage_collect_deduplication_store [options]"
        opts.separator ""

        opts.on("--config-file PATH", String, "Path to an external yaml config file") do |val|
          Beetle.config.config_file = val
          Beetle.config.log_file = STDOUT
        end

        opts.on("--redis-servers LIST", Array, "Comma separted list of redis server:port specs used for GC") do |val|
          Beetle.config.redis_servers = val.join(",")
        end

        opts.on("--redis-db N", Integer, "Redis database used for GC") do |val|
          Beetle.config.redis_db = val.to_i
        end

        opts.on("-v", "--verbose") do |val|
          Beetle.config.log_file = STDOUT
          Beetle.config.logger.level = Logger::DEBUG
        end

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        opts.parse!(ARGV)

        DeduplicationStore.new.garbage_collect_keys_using_master_and_slave
      end
    end
  end
end
