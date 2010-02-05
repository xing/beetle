require 'rubygems'
require 'active_support'
require 'active_support/testing/declarative'
require 'test/unit'
require 'redgreen' unless ENV['TM_FILENAME'] rescue nil
require 'mocha'
require File.expand_path(File.dirname(__FILE__) + '/../lib/beetle')

class Test::Unit::TestCase
  extend ActiveSupport::Testing::Declarative
end

Beetle.configuration do |config|
  config.environment = "test"
  config.config_file = File.expand_path(File.dirname(__FILE__) + '/beetle.yml')
  config.logger = Logger.new(File.dirname(__FILE__) + '/../test.log')
end
