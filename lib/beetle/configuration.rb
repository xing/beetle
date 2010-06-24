module Beetle
  class Configuration
    # default logger (defaults to <tt>Logger.new(STDOUT)</tt>)
    attr_accessor :logger
    # number of seconds after which keys are removed form the message deduplication store (defaults to <tt>3.days</tt>)
    attr_accessor :gc_threshold
    # the redis server to use for deduplication
    # either a string like <tt>"localhost:6379"</tt> (default) or a file that contains the string.
    # use a file if you are using a beetle configuration_client process to update it for automatic redis failover.
    attr_accessor :redis_server
    # redis database number to use for the message deduplication store (defaults to <tt>4</tt>)
    attr_accessor :redis_db

    ## redis configuration server options
    # how often should the redis configuration server try to reach the redis master before nominating a new one (defaults to <tt>3</tt>)
    attr_accessor :redis_configuration_master_retries
    # number of seconds to wait between retries (defaults to <tt>10</tt>)
    attr_accessor :redis_configuration_master_retry_timeout
    # number of seconds the redis configuration server waits until the invalidation times out (defaults to <tt>5</tt>)
    attr_accessor :redis_configuration_master_invalidation_timeout
    # the redis configuration clients living on the worker machines, taking part in the redis failover (defaults to <tt>""</tt>)
    attr_accessor :redis_configuration_client_ids

    # list of amqp servers to use (defaults to <tt>"localhost:5672"</tt>)
    attr_accessor :servers
    # the virtual host to use on the AMQP servers (defaults to <tt>"/"</tt>)
    attr_accessor :vhost
    # the AMQP user to use when connecting to the AMQP servers (defaults to <tt>"guest"</tt>)
    attr_accessor :user
    # the password to use when connectiong to the AMQP servers (defaults to <tt>"guest"</tt>)
    attr_accessor :password

    def initialize #:nodoc:
      self.logger = begin
        logger = Logger.new(STDOUT)
        logger.formatter = Logger::Formatter.new
        logger.level = Logger::DEBUG
        logger.datetime_format = "%Y-%m-%d %H:%M:%S"
        logger
      end
      
      self.gc_threshold = 3.days
      self.redis_server = "localhost:6379"
      self.redis_db = 4

      self.redis_configuration_master_retries = 3
      self.redis_configuration_master_retry_timeout = 10.seconds
      self.redis_configuration_master_invalidation_timeout = 5.seconds
      self.redis_configuration_client_ids = ""

      self.servers = "localhost:5672"
      self.vhost = "/"
      self.user = "guest"
      self.password = "guest"
    end
  end
end
