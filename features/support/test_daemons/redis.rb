require 'rubygems'
require 'fileutils'
require 'erb'
require 'redis'
require File.expand_path('../../../../lib/beetle/redis_ext', __FILE__)
require 'daemon_controller'

module TestDaemons
  class Redis

    def self.containerized?
      ENV['BEETLE_TEST_CONTAINER'] == '1'
    end

    def containerized?
      self.class.containerized?
    end

    @@instances = {}
    @@next_available_port = containerized? ? 6379 : 6381

    attr_reader :name, :port

    def initialize(name)
      @name = name
      @port = @@next_available_port
      @@next_available_port += 1 unless containerized?
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
      create_config
      daemon_controller.start
    end

    def restart(delay = 0)
      daemon_controller.stop if running?
      sleep delay
      start
    end

    def stop
      return unless running?
      # TODO: Might need to be moved into RedisConfigurationServer
      #     10.times do
      #       break if (redis.info["bgsave_in_progress"]) == 0 rescue false
      #       sleep 1
      #     end
      daemon_controller.stop
      raise "FAILED TO STOP redis server #{name} on port #{port}" if running?
    ensure
      cleanup
    end

    def cleanup
      remove_pid_file
      remove_config unless containerized?
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
      if containerized?
        cmd = "docker ps --filter 'name=#{name}' --format '{{.ID}}'"
        container_id == `#{cmd}`.chomp
      else
        cmd = "ps aux | egrep 'redis-server.*#{port}' | grep -v grep"
        res = `#{cmd}`
        x = res.chomp.split("\n")
        x.size == 1
      end
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
    def slave_of(master_host, master_port)
      tries = 0
      begin
        redis.slave_of!(master_host, master_port)
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

    def host
      containerized? ? name : "localhost"
    end

    def redis
      @redis ||= ::Redis.new(:host => host, :port => port)
    end

    private

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

    def dir
      File.join(tmp_path, name)
    end


    def config_filename
      tmp_path + "/redis-test-server-#{name}-#{port}.conf"
    end

    def config_template_filename
      File.dirname(__FILE__) + "/redis.conf.erb"
    end

    def config_content
      template = ERB.new(File.read(config_template_filename))
      template.result(binding)
    end

    def pid_file
      File.join(dir, "#{name}.pid")
    end

    def log_file
      File.join(dir, "#{name}.log")
    end

    def container_id
      @container_id ||=
        `docker ps -a --filter 'name=#{name}' --format='{{.ID}}'`.chomp.tap do |id|
          raise "did not find docker container" if id.blank?
        end
    end

    def start_command
      if containerized?
        "docker start #{container_id}"
      else
        "redis-server #{config_filename}"
      end
    end

    def stop_command
      if containerized?
        "redis-cli -h #{host} -p #{port} shutdown nosave && docker wait #{container_id}"
      else
        "redis-cli -h #{host} -p #{port} shutdown nosave"
      end
    end

    def daemon_controller
      @daemon_controller ||=
        begin
          # puts start_command, stop_command
          DaemonController.new(
            :identifier    => "Redis test server #{name}",
            :pid_file      => pid_file,
            :start_command => start_command,
            :stop_command  => stop_command,
            :ping_command  => lambda { running? && available? },
            :log_file      => log_file,
            :start_timeout => 20,
            :stop_timeout  => 20,
          )
        end
    end
  end
end
