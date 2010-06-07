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
    # how often should the redis configuration server try to reach the redis master before nominating a new one 
    attr_accessor :redis_configuration_master_retries
    # how long should the redis configuration server wait between retries
    attr_accessor :redis_configuration_master_retry_timeout
    # number of seconds after which the redis configuration server checks for reconfigured answers
    attr_accessor :redis_configuration_reconfiguration_timeout
    # file where the redis configuration client stores the current redis master to be used by the workers
    attr_accessor :redis_master_file_path
    # the redis configuration clients living on the worker machines, taking part in the redis failover
    attr_accessor :redis_configuration_client_ids
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
      self.redis_configuration_master_retries = 3
      self.redis_configuration_master_retry_timeout = 30.seconds
      self.redis_configuration_reconfiguration_timeout = 10.seconds
      self.redis_master_file_path = "/var/beetle/redis-master"
      self.redis_configuration_client_ids = ""
      self.servers = "localhost:5672"
      self.vhost = "/"
      self.user = "guest"
      self.password = "guest"
    end
  end
end
