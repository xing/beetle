require 'yaml'
require 'erb'
require 'amqp'
require 'mq'
require 'bunny'
require 'uuid4r'
require 'active_support'
require 'redis'

RAILS_ENV = ENV['RAILS_ENV'] || 'development' unless defined?(RAILS_ENV)

module Bandersnatch
  lib_dir = File.dirname(__FILE__) + '/bandersnatch/'
  autoload "Base", lib_dir + 'base'
  autoload "Configuration", lib_dir + 'configuration'
  autoload "Message", lib_dir + 'message'
  autoload "Client", lib_dir + 'client'
  autoload "Publisher", lib_dir + 'publisher'
  autoload "Subscriber", lib_dir + 'subscriber'

  def self.configuration
    yield config
  end

  protected

    def self.config
      @config ||= begin
        conf = Configuration.new
        conf.logger = Logger.new(STDOUT)
        conf.config_file = File.expand_path(File.dirname(__FILE__) + '/../config/bandersnatch.yml')
        conf
      end
    end

end
