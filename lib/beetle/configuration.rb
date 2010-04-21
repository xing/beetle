module Beetle
  class Configuration
    # default logger (defaults to <tt>Logger.new(STDOUT)</tt>)
    attr_accessor :logger
    # number of seconds after which keys are removed form the message deduplication store (defaults to <tt>3.days</tt>)
    attr_accessor :gc_threshold
    # the machines where the deduplication store lives (defaults to <tt>"localhost:6379"</tt>)
    attr_accessor :redis_hosts
    # redis database number to use for the message deduplication store (defaults to <tt>4</tt>)
    attr_accessor :redis_db
    # how often should the redis watcher try to reach the master before nominating a new one 
    attr_accessor :redis_watcher_retries
    # how long should the redis watcher wait between retries
    attr_accessor :redis_watcher_retry_timeout
    # list of amqp servers to use (defaults to <tt>"localhost:5672"</tt>)
    attr_accessor :servers
    # the virtual host to use on the AMQP servers
    attr_accessor :vhost
    # the AMQP user to use when connecting to the AMQP servers
    attr_accessor :user
    # the password to use when connectiong to the AMQP servers
    attr_accessor :password

    def initialize #:nodoc:
      self.logger = Logger.new(STDOUT)
      self.gc_threshold = 3.days
      self.redis_hosts = "localhost:6379"
      self.redis_db = 4
      self.redis_watcher_retry_timeout = 30.seconds
      self.redis_watcher_retries = 3
      self.servers = "localhost:5672"
      self.vhost = "/"
      self.user = "guest"
      self.password = "guest"
    end
  end
end
