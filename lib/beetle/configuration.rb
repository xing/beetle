module Beetle
  class Configuration
    # default logger (defaults to <tt>Logger.new(STDOUT)</tt>)
    attr_accessor :logger
    # number of seconds after which keys are removed form the message deduplication store (defaults to <tt>3.days</tt>)
    attr_accessor :gc_threshold
    # file that contains the redis server for deduplication, like <tt>localhost:6379</tt> (defaults to <tt>"/var/beetle/redis-master"</tt>)
    attr_accessor :redis_master_file
    # redis database number to use for the message deduplication store (defaults to <tt>4</tt>)
    attr_accessor :redis_db

    ## redis configuration server options
    # how often should the redis configuration server try to reach the redis master before nominating a new one (defaults to <tt>3</tt>)
    attr_accessor :redis_configuration_master_retries
    # number of seconds to wait between retries (defaults to <tt>10</tt>)
    attr_accessor :redis_configuration_master_retry_timeout
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
      self.logger = Logger.new(STDOUT)
      self.gc_threshold = 3.days
      self.redis_master_file = "/var/beetle/redis-master"
      self.redis_db = 4

      self.redis_configuration_master_retries = 3
      self.redis_configuration_master_retry_timeout = 10.seconds
      self.redis_configuration_client_ids = ""

      self.servers = "localhost:5672"
      self.vhost = "/"
      self.user = "guest"
      self.password = "guest"
    end
  end
end
