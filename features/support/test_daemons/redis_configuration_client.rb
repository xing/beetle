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
         :start_command => "ruby bin/beetle configuration_client start -- -v --redis-master-file #{redis_master_file} --id #{@name} --pid-dir #{tmp_path} --amqp-servers 127.0.0.1:5672",
         :ping_command  => lambda{ true },
         :pid_file      => pid_file,
         :log_file      => log_file,
         :start_timeout => 5
      )
    end

    def redis_master_file
      "#{tmp_path}/redis-master-#{@name}"
    end

    def pid_file
      "#{tmp_path}/redis_configuration_client#{@daemon_id}.pid"
    end

    def log_file
      "#{tmp_path}/redis_configuration_client.output"
    end

    def tmp_path
      File.expand_path(File.dirname(__FILE__) + "/../../../tmp")
    end

  end
end
