require 'yaml'
require 'erb'
require 'amqp'
require 'mq'
require 'bunny'
require 'uuid4r'
require 'active_support'
require 'redis'

module Beetle

  class Error < StandardError; end
  class HandlerCrash < Error; end
  class HandlerNotYetTimedOut < Error; end
  class AttemptsLimitReached < Error; end
  class ExceptionsLimitReached < Error; end
  class ConfigurationError < Error; end

  EXCHANGE_CREATION_KEYS  = [:auto_delete, :durable, :internal, :nowait, :passive]
  QUEUE_CREATION_KEYS     = [:passive, :durable, :exclusive, :auto_delete, :no_wait]
  QUEUE_BINDING_KEYS      = [:key, :no_wait]
  PUBLISHING_KEYS         = [:key, :mandatory, :immediate, :persistent]

  lib_dir = File.expand_path(File.dirname(__FILE__) + '/beetle/')
  Dir["#{lib_dir}/*.rb"].each do |libfile|
    autoload File.basename(libfile)[/(.*)\.rb/, 1].capitalize, libfile
  end

  def self.configuration
    yield config
  end

  protected

  def self.config
    @config ||= Configuration.new
  end

end
