require 'amqp'
require 'mq'
require 'bunny'
require 'uuid4r'
require 'active_support'
require 'redis'

module Beetle

  # abstract superclass for Beetle specific exceptions
  class Error < StandardError; end
  # raised when Beetle detects configuration errors
  class ConfigurationError < Error; end
  # raised when trying to publish an unknown message
  class UnknownMessage < Error; end

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

  # use ruby's autoload mechanism for loading beetle classes
  lib_dir = File.expand_path(File.dirname(__FILE__) + '/beetle/')
  Dir["#{lib_dir}/*.rb"].each do |libfile|
    autoload File.basename(libfile)[/(.*)\.rb/, 1].classify, libfile
  end

  # returns the configuration object
  def self.config
    @config ||= Configuration.new
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
