$:.unshift(File.expand_path('..', __FILE__))
require 'bunny'

begin
  require 'redis/connection/hiredis' # require *before* redis as specified in the redis-rb gem docs
  require 'redis'
rescue LoadError
  require 'redis'
  require 'hiredis-client'
end
require 'active_support/all'
require 'set'
require 'socket'
require 'beetle/version'

module Beetle
  require 'timeout'
  Timer = Timeout

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
  # raised when no message could be sent by the publisher
  class NoMessageSent < Error; end

  class PublisherConnectError < Error
    attr_reader :server, :cause

    def initialize(server, cause = nil)
      @server = server
      @cause = cause
      super("Publisher failed to connect to server #{server}#{": #{cause.message}" if cause}")
    end
  end

  class PublisherShutdownError < Error
    attr_reader :errors, :server

    def initialize(server, errors = [])
      @errors = errors
      @server = server
      super("Publisher failed to shutdown bunny for server #{server}: #{errors.join(', ')}")
    end
  end

  # logged when an RPC call timed outdated
  class RPCTimedOut < Error; end

  # AMQP options for exchange creation
  EXCHANGE_CREATION_KEYS  = [:auto_delete, :durable, :internal, :nowait, :passive]
  # AMQP options for queue creation
  QUEUE_CREATION_KEYS     = [:passive, :durable, :exclusive, :auto_delete, :no_wait, :arguments]
  # AMQP options for queue bindings
  QUEUE_BINDING_KEYS      = [:key, :no_wait]
  # AMQP options for message publishing
  PUBLISHING_KEYS         = [:key, :mandatory, :immediate, :persistent, :reply_to, :headers, :priority]
  # AMQP options for subscribing to queues
  SUBSCRIPTION_KEYS       = [:ack, :key]

  # determine the fully qualified domainname of the host we're running on
  def self.hostname
    name = Socket.gethostname
    host = name.split('.').first
    Addrinfo.getaddrinfo(host, nil, nil, :STREAM, nil, Socket::AI_CANONNAME).first.canonname rescue name
  end

  # use ruby's autoload mechanism for loading beetle classes
  lib_dir = File.expand_path(File.dirname(__FILE__) + '/beetle/')
  Dir["#{lib_dir}/*.rb"].each do |libfile|
    autoload File.basename(libfile)[/^(.*)\.rb$/, 1].camelize, libfile
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
    #:nocov:
    def self.reraise_expectation_errors! #:nodoc:
    end
    #:nocov:
  end
end
