require 'daemon_controller'

module TestDaemons
  class RedisConfigurationClient
    cattr_reader :instances
    @@next_daemon_id = 0
    @@instances = {}

    def initialize(name)
      @name = name
      @daemon_id = @@next_daemon_id

      @@next_daemon_id += 1
      @@instances[name] = self
    end

    class << self
      def find_or_initialize_by_name(name)
        @@instances[name] ||= new(name)
      end
      alias_method :[], :find_or_initialize_by_name

      def stop_all
        @@instances.values.each{|i| i.stop}
      end
    end

    def start
      daemon_controller.start
    end

    def stop
      daemon_controller.stop
    end

    def daemon_controller
      @daemon_controller ||= DaemonController.new(
         :identifier    => "Redis configuration test client #{@name}",
         :start_command => "./beetle configuration_client -v -d --redis-master-file #{redis_master_file} --id #{@name} --pid-file #{pid_file} --log-file #{log_file} --client-proxy-port #{client_proxy_port}",
         :ping_command  => lambda{ true },
         :pid_file      => pid_file,
         :log_file      => log_file,
         :start_timeout => 10,
         :stop_timeout => 10,
      )
    end

    def client_proxy_port
      9700 + @daemon_id
    end

    def redis_master_file
      "#{tmp_path}/redis-master-#{@name}"
    end

    def pid_file
      "#{tmp_path}/redis_configuration_client_num#{@daemon_id}.pid"
    end

    def log_file
      "#{tmp_path}/redis_configuration_client_num#{@daemon_id}.output"
    end

    def tmp_path
      File.expand_path(File.dirname(__FILE__) + "/../../../tmp")
    end

  end
end
