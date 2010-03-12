module Beetle
  class Configuration
    # default logger (defaults to <tt>Logger.new(STDOUT)</tt>)
    attr_accessor :logger
    # number of seconds after which keys are removed form the message deduplification store (defaults to <tt>3.days</tt>)
    attr_accessor :gc_threshold
    # the machine where the deduplification store lives (defaults to <tt>"localhost"</tt>)
    attr_accessor :redis_host
    # redis database number to use for the message deduplification store (defaults to <tt>4</tt>)
    attr_accessor :redis_db
    # list of amqp servers to use (defaults to <tt>"localhost:5672"</tt>)
    attr_accessor :servers

    def initialize #:nodoc:
      self.logger = Logger.new(STDOUT)
      self.gc_threshold = 3.days
      self.redis_host = "localhost"
      self.redis_db = 4
      self.servers = "localhost:5672"
    end
  end
end
