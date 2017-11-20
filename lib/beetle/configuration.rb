require 'erb'
require 'yaml'

module Beetle
  class Configuration
    # system name (used for redis cluster partitioning) (defaults to <tt>system</tt>)
    attr_accessor :system_name
    # default logger (defaults to <tt>Logger.new(log_file)</tt>)
    attr_accessor :logger
    # defaults to <tt>STDOUT</tt>
    attr_accessor :log_file
    # number of seconds after which keys are removed from the message deduplication store (defaults to <tt>1.hour</tt>)
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

    # how often heartbeat messages are exchanged between failover
    # daemons. defaults to 10 seconds.
    attr_accessor :redis_failover_client_heartbeat_interval

    # how long to wait until a redis_failover client daemon can be considered
    # dead. defaults to 60 seconds.
    attr_accessor :redis_failover_client_dead_interval

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
    # the maximum permissible size of a frame (in bytes). Defaults to 128 KB
    attr_accessor :frame_max

    # In contrast to RabbitMQ 2.x, RabbitMQ 3.x preserves message order when requeing a message. This can lead to
    # throughput degradation (when rejected messages block the processing of other messages
    # at the head of the queue) in some cases.
    #
    # This setting enables the creation of dead letter queues that mimic the old beetle behaviour on RabbitMQ 3.x.
    # Instead of rejecting messages with "requeue => true", beetle will setup dead letter queues for all queues, will
    # reject messages with "requeue => false", where messages are temporarily moved to the side and are republished to
    # the end of the original queue when they expire in the dead letter queue.
    #
    # By default this is turned off and needs to be explicitly enabled.
    attr_accessor :dead_lettering_enabled
    alias_method :dead_lettering_enabled?, :dead_lettering_enabled

    # the time a message spends in the dead letter queue if dead lettering is enabled, before it is returned
    # to the original queue
    attr_accessor :dead_lettering_msg_ttl

    # Read timeout for http requests to create dead letter bindings
    attr_accessor :dead_lettering_read_timeout

    # Returns the port on which the Rabbit API is hosted
    attr_accessor :api_port

    # the socket timeout in seconds for message publishing (defaults to <tt>0</tt>).
    # consider this a highly experimental feature for now.
    attr_accessor :publishing_timeout

    # Prefetch count for subscribers (defaults to 1). Setting this higher
    # than 1 can potentially increase throughput, but comes at the cost of
    # decreased parallelism.
    attr_accessor :prefetch_count

    # directory to store large intermediate files (defaults '/tmp')
    attr_accessor :tmpdir

    # external config file (defaults to <tt>no file</tt>)
    attr_reader :config_file

    # returns the configured amqp brokers
    def brokers
      {
        'servers' => self.servers,
        'additional_subscription_servers' => self.additional_subscription_servers
      }
    end

    def initialize #:nodoc:
      self.system_name = "system"

      self.gc_threshold = 1.hour.to_i
      self.redis_server = "#{ENV['REDIS_HOST'] || 'localhost'}:#{ENV['REDIS_PORT'] || 6379}"
      self.redis_servers = ""
      self.redis_db = ENV['REDIS_DB'] || 4
      self.redis_failover_timeout = 180.seconds
      self.redis_failover_client_heartbeat_interval = 10.seconds
      self.redis_failover_client_dead_interval = 60.seconds

      self.redis_configuration_master_retries = 3
      self.redis_configuration_master_retry_interval = 10.seconds
      self.redis_configuration_client_timeout = 5.seconds
      self.redis_configuration_client_ids = ""

      self.servers = "#{ENV['RABBITMQ_HOST'] || 'localhost'}:#{ENV['RABBITMQ_PORT'] || 5672}"
      self.additional_subscription_servers = ""
      self.vhost = "/"
      self.user = "guest"
      self.password = "guest"
      self.api_port = ENV['RABBITMQ_API_PORT'] || 15672
      self.frame_max = 131072
      self.prefetch_count = 1

      self.dead_lettering_enabled = false
      self.dead_lettering_msg_ttl = 1000 #1 second
      self.dead_lettering_read_timeout = 3 #3 seconds

      self.publishing_timeout = 0
      self.tmpdir = "/tmp"

      self.log_file = STDOUT
    end

    # setting the external config file will load it on assignment
    def config_file=(file_name) #:nodoc:
      @config_file = file_name
      load_config
    end

    # reloads the configuration from the configuration file
    # if one is configured
    def reload
      load_config if @config_file
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
      raw = ERB.new(IO.read(config_file)).result
      hash = if config_file =~ /\.json$/
               JSON.parse(raw)
             else
               YAML.load(raw)
             end
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
