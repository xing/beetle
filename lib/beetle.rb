$:.unshift(File.expand_path('..', __FILE__))
require 'bunny'
require 'uuid4r'
require 'redis/connection/hiredis' # require *before* redis as specified in the redis-rb gem docs
require 'redis'
require 'active_support'
require 'active_support/core_ext'
require 'set'
require 'socket'
require 'beetle/version'

module Beetle
  Timer = if RUBY_VERSION < "1.9"
            begin
              require 'system_timer'
              SystemTimer
            rescue Exception => e
              warn "WARNING: It's highly recommended to install the SystemTimer gem: `gem install SystemTimer -v '=1.2.1'` See: http://ph7spot.com/musings/system-timer" if RUBY_VERSION < "1.9"
              require 'timeout'
              Timeout
            end
          else
            require 'timeout'
            Timeout
          end

  # abstract superclass for Beetle specific exceptions
  class Error < StandardError; end
  # raised when Beetle detects configuration errors
  class ConfigurationError < Error; end
  # raised when trying to access an unknown message
  class UnknownMessage < Error; end
  # raised when trying to access an unknown queue
  class UnknownQueue < Error; end
  # raised when no redis master server can be found
  class NoRedisMaster < Error; end
  # raise when no message could be sent by the publisher
  class NoMessageSent < Error; end

  # AMQP options for exchange creation
  EXCHANGE_CREATION_KEYS  = [:auto_delete, :durable, :internal, :nowait, :passive]
  # AMQP options for queue creation
  QUEUE_CREATION_KEYS     = [:passive, :durable, :exclusive, :auto_delete, :no_wait]
  # AMQP options for queue bindings
  QUEUE_BINDING_KEYS      = [:key, :no_wait]
  # AMQP options for message publishing
  PUBLISHING_KEYS         = [:key, :mandatory, :immediate, :persistent, :reply_to]
  # AMQP options for subscribing to queues
  SUBSCRIPTION_KEYS       = [:ack, :key]

  # determine the fully qualified domainname of the host we're running on
  def self.hostname
    name = Socket.gethostname
    parts = name.split('.')
    parts.size > 1 ? name : Socket.gethostbyname(parts.first).first
  end

  # use ruby's autoload mechanism for loading beetle classes
  lib_dir = File.expand_path(File.dirname(__FILE__) + '/beetle/')
  Dir["#{lib_dir}/*.rb"].each do |libfile|
    autoload File.basename(libfile)[/^(.*)\.rb$/, 1].classify, libfile
  end

  require "#{lib_dir}/redis_ext"

  # returns the default configuration object and yields it if a block is given
  def self.config
    #:yields: config
    @config ||= Configuration.new
    block_given? ? yield(@config) : @config
  end

  # FIXME: there should be a better way to test
  if defined?(Mocha)
    def self.reraise_expectation_errors! #:nodoc:
      raise if $!.is_a?(Mocha::ExpectationError)
    end
  else
    def self.reraise_expectation_errors! #:nodoc:
    end
  end
end
