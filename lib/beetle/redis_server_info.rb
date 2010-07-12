module Beetle
  # class used by the RedisConfigurationServer to hold information about the current state of the configured redis servers
  class RedisServerInfo
    include Logging

    def initialize(config, options) #:nodoc:
      @config = config
      @options = options
      reset
    end

    # all configured redis servers
    def instances
      @instances ||= @config.redis_servers.split(/ *, */).map{|s| Redis.from_server_string(s, @options)}
    end

    # fetches the server from the insatnces whith the given <tt>server</tt> string
    def find(server)
      instances.find{|r| r.server == server}
    end

    # refresh connectivity/role information
    def refresh
      logger.debug "Updating redis server info"
      reset
      instances.each {|r| @server_info[r.role] << r}
    end

    # subset of instances which are masters
    def masters
      @server_info["master"]
    end

    # subset of instances which are slaves
    def slaves
      @server_info["slave"]
    end

    # subset of instances which are not reachable
    def unknowns
      @server_info["unknown"]
    end

    # subset of instances which are set up as slaves of the given <tt>master</tt>
    def slaves_of(master)
      slaves.select{|r| r.slave_of?(master.host, master.port)}
    end

    # determine a master if we have one master and all other servers are slaves
    def auto_detect_master
      return nil unless master_and_slaves_reachable?
      masters.first
    end

    private

    def master_and_slaves_reachable?
      masters.size == 1 && slaves.size == instances.size - 1
    end

    def reset
      @server_info = Hash.new {|h,k| h[k]= []}
    end
  end
end
