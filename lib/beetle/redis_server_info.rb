module Beetle
  class RedisServerInfo
    include Logging

    def initialize(config, options)
      @config = config
      @options = options
      reset
    end

    def instances
      @instances ||= @config.redis_servers.split(/ *, */).map{|s| Redis.from_server_string(s, @options)}
    end

    def find(server)
      instances.find{|r| r.server == server}
    end

    def refresh
      logger.debug "Updating redis server info"
      reset
      instances.each {|r| @server_info[r.role] << r}
    end

    def masters
      @server_info["master"]
    end

    def slaves
      @server_info["slave"]
    end

    def unknowns
      @server_info["unknown"]
    end

    def slaves_of(master)
      slaves.select{|r| r.slave_of?(master.host, master.port)}
    end

    private

    def reset
      @server_info = Hash.new {|h,k| h[k]= []}
    end
  end
end
