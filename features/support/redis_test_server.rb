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
      # processes = `ps aux | grep redis-server | grep -v grep | grep test-server | cut -d' ' -f2`.split("\n").reject(&:blank?)
      # `kill -9 #{processes.join(' ')} 1>/dev/null 2>&1` if processes.any?
      @@instances.values.each{|i| i.stop}
    end
  end

  def start
    raise "zombie redis #{name} exists. giving up" if running?
    create_dir
    create_config
    `redis-server #{config_filename}`
    tries = 0
    begin
      available?
    rescue
      sleep 1
      retry if (tries +=1) > 5
      raise "could not start redis #{name}"
    end
  end

  def restart(delay=1)
    redis.shutdown rescue Errno::ECONNREFUSED
    sleep delay
    `redis-server #{config_filename}`
  end

  # TODO: some of this needs to moved into our code
  def stop
    return unless running?
    10.times do
      break if (redis.info["bgsave_in_progress"]) == 0 rescue false
      sleep 1
    end
    # puts redis.info.inspect
    redis.shutdown rescue Errno::ECONNREFUSED
    begin
      5.times do
        return unless running?
        sleep 1
      end
      puts "forcing kill -9 of redis server #{name}"
      5.times do
        Process.kill("KILL", pid)
        return unless running?
        sleep 1
      end
      puts "could not stop redis #{name} #{$!}" if running?
    end
  ensure
    cleanup
  end

  def cleanup
    remove_dir
    remove_config
    remove_pidfile
  end

  # TODO: the retry logic must be moved into the actual code
  def master
    tries = 0
    redis.master!
  rescue Errno::ECONNREFUSED, Errno::EAGAIN
    puts "master role setting for #{name} failed: #{$!}"
    sleep 1
    retry if (tries+=1) > 5
    raise "could not setup master #{name} #{$!}"
  end

  def running?
    cmd = "ps aux | grep 'redis-server #{config_filename}' | grep -v grep"
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

  # TODO: the retry logic must be moved into the actual code
  def slave_of(master_port)
    tries = 0
    begin
      redis.slave_of!("127.0.0.1", master_port)
    rescue Errno::ECONNREFUSED, Errno::EAGAIN
      puts "slave role setting for #{name} failed: #{$!}"
      sleep 1
      retry if (tries+=1) > 5
      raise "could not setup slave #{name}: #{$!}"
    end
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
