require 'yaml'
require 'erb'
require 'amqp'
require 'mq'
require 'bunny'
require 'uuid4r'
require 'active_support'
require 'redis'

module Bandersnatch
  lib_dir = File.dirname(__FILE__) + '/bandersnatch/'
  autoload "Base", lib_dir + 'base'
  autoload "Configuration", lib_dir + 'configuration'
  autoload "Message", lib_dir + 'message'

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
