module Beetle
  class Configuration
    attr_accessor :logger, :gc_threshold, :redis_host, :redis_db, :servers
    def initialize
      self.logger = Logger.new(STDOUT)
      self.gc_threshold = 3.days
      self.redis_host = "localhost"
      self.redis_db = 4
      self.servers = "localhost:5672"
    end
  end
end
