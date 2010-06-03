require 'daemon_controller'

module TestDaemons
  class RedisConfigurationServer

    # At the moment, we need only one, so we implement the methods
    # as class methods

    @@started = false

    def self.start(redis_servers)
      @@redis_servers = redis_servers
      daemon_controller.start
      @@started = true
    end

    def self.stop
      daemon_controller.stop if @@started
    end

    def self.daemon_controller
      @@daemon_controller ||= DaemonController.new(
         :identifier    => "Redis configuration test server",
         :start_command => "ruby bin/redis_configuration_server start -- --redis-servers=#{@@redis_servers.join(",")} --redis-retry-timeout 1",
         :ping_command  => lambda{ true },
         :pid_file      => pid_file,
         :log_file      => log_file,
         :timeout       => 5
      )
    end
    
    def self.pid_file
      "redis_configuration_server.pid"
    end
    
    def self.log_file
      "redis_configuration_server.output"
    end
    
    def self.tmp_path
      File.expand_path(File.dirname(__FILE__) + "/../../../tmp")
    end

  end
end