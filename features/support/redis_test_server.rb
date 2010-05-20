require 'fileutils'
require 'erb'
require 'redis'

# Creates and manages named redis server instances for testing with ease
class RedisTestServer

  @@instances = []
  
  attr_reader :name
  
  def initialize(name)
    @name = name
    @@instances << self
  end

  class << self
    def find_or_initialize_by_name(name)
      @@instances.find(lambda{ new(name) }) {|i| i.name == name }
    end
    alias_method :[], :find_or_initialize_by_name
  
    def stop_all
      @@instances.each{|i| i.stop }
    end
  end
  
  def start
    create_dir
    create_config
    `redis-server #{config_filename}`
  end
  
  def stop
    redis.shutdown
  rescue Errno::ECONNREFUSED
    # Seems to be always raised in older redis-rb
  ensure
    remove_dir
    remove_config
    remove_pidfile
  end
  
  def master
    redis.slaveof("no one")
  end

  def slave_of(master_port)
    redis.slaveof("127.0.0.1 #{master_port}")
  end
  
  def port
    6381 + @@instances.index(self)
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
      File.read(pidfile)
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
