module Beetle
  class RedisConfigurationAutoDetection #:nodoc:
    def initialize(redis_instances)
      @redis_instances = redis_instances
    end

    # auto detect redis master - will return nil if no valid master detected
    def master
      return nil unless single_master_reachable? || master_and_slaves_reachable?
      @redis_instances.find{|r| r.master? }
    end

    private

    # whether we have a master slave configuration
    def single_master_reachable?
      @redis_instances.select{|r| r.master? }.size == 1
    end

    # can we access both master and slaves
    def master_and_slaves_reachable?
      single_master_reachable? && @redis_instances.select{|r| r.slave? }.size == @redis_instances.size - 1
    end
  end
end
