require 'daemon_controller'

module TestDaemons
  class RedisConfigurationClient

    @@next_daemon_id = 0
    @@instances = {}

    def initialize(name, redis_servers)
      @name = name
      @redis_servers = redis_servers
      @daemon_id = @@next_daemon_id

      @@next_daemon_id += 1
      @@instances[name] = self
    end
    
    def self.find_or_initialize_by_name(name, redis_servers)
      @@instances[name] ||= new(name, redis_servers)
    end

    def self.stop_all
      @@instances.values.each{|i| i.stop}
    end

    def start
      daemon_controller.start
    end

    def stop
      daemon_controller.stop
    end

    def daemon_controller
      @daemon_controller ||= DaemonController.new(
         :identifier    => "Redis configuration test client",
         :start_command => "ruby bin/beetle configuration_client start -- -v --redis-servers=#{@redis_servers.join(',')} --redis-master-file=#{redis_master_file} --id #{@name}",
         :ping_command  => lambda{ true },
         :pid_file      => pid_file,
         :log_file      => log_file,
         :start_timeout => 5
      )
    end
    
    private
    
    def redis_master_file
      "#{tmp_path}/redis-master-#{@name}"
    end
    
    def pid_file
      "redis_configuration_client#{@daemon_id}.pid"
    end
    
    def log_file
      "redis_configuration_client.output"
    end
    
    def tmp_path
      File.expand_path(File.dirname(__FILE__) + "/../../../tmp")
    end

  end
end