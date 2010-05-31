require 'fileutils'
require 'erb'
require 'redis'

# Creates and manages named redis server instances for testing with ease
class RedisTestServer

  @@instances = {}
  @@next_available_port = 6381

  attr_reader :name, :port

  def initialize(name)
    @name = name
    @port = @@next_available_port
    @@next_available_port = @@next_available_port + 1
    @@instances[name] = self
  end

  class << self
    def find_or_initialize_by_name(name)
      @@instances[name] ||= new(name)
    end
    alias_method :[], :find_or_initialize_by_name

    def stop_all
      processes = `ps aux | grep redis-server | grep -v grep | grep test-server | cut -d' ' -f2`.split("\n").reject(&:blank?)
      `kill -9 #{processes.join(' ')} 1>/dev/null 2>&1`
      @@instances.values.each{|i| i.cleanup}
    end
  end

  def start
    create_dir
    create_config
    `redis-server #{config_filename}`
    begin
      available?
    rescue
      retry
    end
  end

  def restart(delay=1)
    redis.shutdown rescue Errno::ECONNREFUSED
    sleep delay
    `redis-server #{config_filename}`
  end

  def stop
    Process.kill("KILL", pid)
  ensure
    cleanup
  end
  
  def cleanup
    remove_dir
    remove_config
    remove_pidfile
  end

  def master
    redis.master!
  rescue Errno::ECONNREFUSED, Errno::EAGAIN
    sleep 0.5
    retry
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

  def slave_of(master_port)
    redis.slave_of!("127.0.0.1", master_port)
  rescue Errno::ECONNREFUSED, Errno::EAGAIN
    sleep 0.5
    retry
  end

  def ip_with_port
    "127.0.0.1:#{port}"
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

  def remove_pidfile
    FileUtils.rm(pidfile) if File.exists?(pidfile)
  end

  def tmp_path
    File.expand_path(File.dirname(__FILE__) + "/../../tmp")
  end

  def config_filename
    tmp_path + "/redis-test-server-#{name}.conf"
  end

  def config_content
    template = ERB.new(File.read(config_template_filename))
    template.result(binding)
  end

  def config_template_filename
    File.dirname(__FILE__) + "/redis.conf.erb"
  end

  def pidfile
    tmp_path + "/redis-test-server-#{name}.pid"
  end

  def pid
    File.read(pidfile).chomp.to_i
  end

  def logfile
    tmp_path + "/redis-test-server-#{name}.log"
  end

  def dir
    tmp_path + "/redis-test-server-#{name}/"
  end

  def redis
    @redis ||= Redis.new(:host => "127.0.0.1", :port => port)
  end

end
