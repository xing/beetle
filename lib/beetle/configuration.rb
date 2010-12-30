require 'erb'

module Beetle
  class Configuration
    # system name (used for redis cluster partitioning) (defaults to <tt>system</tt>)
    attr_accessor :system_name
    # default logger (defaults to <tt>Logger.new(log_file)</tt>)
    attr_accessor :logger
    # defaults to <tt>STDOUT</tt>
    attr_accessor :log_file
    # number of seconds after which keys are removed form the message deduplication store (defaults to <tt>3.days</tt>)
    attr_accessor :gc_threshold
    # the redis server to use for deduplication
    # either a string like <tt>"localhost:6379"</tt> (default) or a file that contains the string.
    # use a file if you are using a beetle configuration_client process to update it for automatic redis failover.
    attr_accessor :redis_server
    # comma separated list of redis servers available for master/slave switching
    # e.g. "192.168.1.2:6379,192.168.1.3:6379"
    attr_accessor :redis_servers
    # redis database number to use for the message deduplication store (defaults to <tt>4</tt>)
    attr_accessor :redis_db

    # how long we should repeatedly retry a redis operation before giving up, with a one
    # second sleep between retries (defaults to <tt>180.seconds</tt>). this value needs to be
    # somewehere between the maximum time it takes to auto-switch redis and the smallest
    # handler timeout.
    attr_accessor :redis_failover_timeout

    ## redis configuration server options
    # how often should the redis configuration server try to reach the redis master before nominating a new one (defaults to <tt>3</tt>)
    attr_accessor :redis_configuration_master_retries
    # number of seconds to wait between retries (defaults to <tt>10</tt>)
    attr_accessor :redis_configuration_master_retry_interval
    # number of seconds the redis configuration server waits for answers from clients (defaults to <tt>5</tt>)
    attr_accessor :redis_configuration_client_timeout
    # the redis configuration client ids living on the worker machines taking part in the redis failover, separated by comma (defaults to <tt>""</tt>)
    attr_accessor :redis_configuration_client_ids

    # list of amqp servers to use (defaults to <tt>"localhost:5672"</tt>)
    attr_accessor :servers
    # list of additional amqp servers to use for subscribers (defaults to <tt>""</tt>)
    attr_accessor :additional_subscription_servers
    # the virtual host to use on the AMQP servers (defaults to <tt>"/"</tt>)
    attr_accessor :vhost
    # the AMQP user to use when connecting to the AMQP servers (defaults to <tt>"guest"</tt>)
    attr_accessor :user
    # the password to use when connectiong to the AMQP servers (defaults to <tt>"guest"</tt>)
    attr_accessor :password

    # the socket timeout in seconds for message publishing (defaults to <tt>0</tt>).
    # consider this a highly experimental feature for now.
    attr_accessor :publishing_timeout

    # external config file (defaults to <tt>no file</tt>)
    attr_reader :config_file

    def initialize #:nodoc:
      self.system_name = "system"

      self.gc_threshold = 1.hour.to_i
      self.redis_server = "localhost:6379"
      self.redis_servers = ""
      self.redis_db = 4
      self.redis_failover_timeout = 180.seconds

      self.redis_configuration_master_retries = 3
      self.redis_configuration_master_retry_interval = 10.seconds
      self.redis_configuration_client_timeout = 5.seconds
      self.redis_configuration_client_ids = ""

      self.servers = "localhost:5672"
      self.additional_subscription_servers = ""
      self.vhost = "/"
      self.user = "guest"
      self.password = "guest"

      self.publishing_timeout = 0

      self.log_file = STDOUT
    end

    # setting the external config file will load it on assignment
    def config_file=(file_name) #:nodoc:
      @config_file = file_name
      load_config
    end

    def logger
      @logger ||=
        begin
          l = Logger.new(log_file)
          l.formatter = Logger::Formatter.new
          l.level = Logger::INFO
          l.datetime_format = "%Y-%m-%d %H:%M:%S"
          l
        end
    end

    private
    def load_config
      hash = YAML::load(ERB.new(IO.read(config_file)).result)
      hash.each do |key, value|
        send("#{key}=", value)
      end
    rescue Exception
      Beetle::reraise_expectation_errors!
      logger.error "Error loading beetle config file '#{config_file}': #{$!}"
      raise
    end
  end
end
