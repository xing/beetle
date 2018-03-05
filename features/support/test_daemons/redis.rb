require 'rubygems'
require 'fileutils'
require 'erb'
require 'redis'
require File.expand_path('../../../../lib/beetle/redis_ext', __FILE__)
require 'daemon_controller'

module TestDaemons
  class Redis

    @@instances = {}
    @@next_available_port = 6381

    attr_reader :name, :port

    def initialize(name)
      @name = name
      @port = @@next_available_port

      @@next_available_port += 1
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
      create_dir
      create_config
      daemon_controller.start
    end

    def restart(delay = 0)
      create_dir
      create_config
      daemon_controller.stop if running?
      sleep delay
      tries = 3
      begin
        daemon_controller.start
      rescue DaemonController::StartError => e
        puts "?????????? redis-server failed to start: #{e}"
        retry if (tries -= 1) > 0
      rescue DaemonController::AlreadyStarted => e
        puts "?????????? redis-server already startes: #{e}"
      end
    end

    def stop
      return unless running?
      # TODO: Might need to be moved into RedisConfigurationServer
      10.times do
        rdb_bgsave_in_progress, aof_rewrite_in_progress = redis.info_with_rescue.values_at("rdb_bgsave_in_progress", "aof_rewrite_in_progress")
        break if rdb_bgsave_in_progress == "0" && aof_rewrite_in_progress == "0"
        puts "#{Time.now} redis #{name} is still saving to disk"
        sleep 1
      end
      daemon_controller.stop
      raise "FAILED TO STOP redis server on port #{port}" if running?
    ensure
      cleanup
    end

    def cleanup
      remove_dir
      remove_config
      remove_pid_file
    end

    # TODO: The retry logic must be moved into RedisConfigurationServer
    def master
      tries = 0
      begin
        redis.master!
      rescue Errno::ECONNREFUSED, Errno::EAGAIN
        puts "master role setting for #{name} failed: #{$!}"
        sleep 1
        retry if (tries+=1) > 5
        raise "could not setup master #{name} #{$!}"
      end
    end

    def running?
      cmd = "ps aux | fgrep 'redis-server \*:#{port}' | grep -v grep"
      res = `#{cmd}`
      x = res.chomp.split("\n")
      x.size == 1
    end

    def available?
      redis.available?
    end

    def master?
      redis.master?
    end

    def slave?
      redis.slave?
    end

    # TODO: Move to redis_ext
    def slave_of(master_port)
      tries = 0
      begin
        redis.slave_of!(host, master_port)
      rescue Errno::ECONNREFUSED, Errno::EAGAIN
        puts "slave role setting for #{name} failed: #{$!}"
        sleep 1
        retry if (tries+=1) > 5
        raise "could not setup slave #{name}: #{$!}"
      end
    end

    def ip_with_port
      "#{host}:#{port}"
    end

    def redis
      @redis ||= ::Redis.new(:host => host, :port => port)
    end

    def host
      '127.0.0.1'
    end

    private

    def create_dir
      FileUtils.mkdir(dir) unless File.exists?(dir)
    end

    def remove_dir
      FileUtils.rm_r(dir) if File.exists?(dir)
    end

    def create_config
      File.open(config_filename, "w") do |file|
        file.puts config_content
      end
    end

    def remove_config
      FileUtils.rm(config_filename) if File.exists?(config_filename)
    end

    def remove_pid_file
      FileUtils.rm(pid_file) if File.exists?(pid_file)
    end

    def tmp_path
      File.expand_path(File.dirname(__FILE__) + "/../../../tmp")
    end

    def config_filename
      tmp_path + "/redis-test-server-#{name}-#{port}.conf"
    end

    def config_content
      template = ERB.new(File.read(config_template_filename))
      template.result(binding)
    end

    def config_template_filename
      File.dirname(__FILE__) + "/redis.conf.erb"
    end

    def pid_file
      tmp_path + "/redis-test-server-#{name}.pid"
    end

    def pid
      File.read(pid_file).chomp.to_i
    end

    def log_file
      tmp_path + "/redis-test-server-#{name}.log"
    end

    def dir
      tmp_path + "/redis-test-server-#{name}/"
    end

    def daemon_controller
      @daemon_controller ||= DaemonController.new(
         :identifier    => "Redis test server #{name}",
         :start_command => "redis-server #{config_filename}",
         :stop_command  => "redis-cli -p #{port} shutdown nosave",
         :ping_command  => lambda { running? && available? },
         :pid_file      => pid_file,
         :log_file      => log_file,
         :start_timeout => 20,
         :stop_timeout  => 30,
      )
    end
  end
end
