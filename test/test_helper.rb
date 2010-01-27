require 'rubygems'
require 'active_support'
require 'active_support/testing/declarative'
require 'test/unit'
require 'mocha'
require File.expand_path(File.dirname(__FILE__) + '/../lib/bandersnatch')

RAILS_ENV = 'test'

class Test::Unit::TestCase
  extend ActiveSupport::Testing::Declarative
end

Bandersnatch::Base.configuration do |config|
  config.config_file = File.expand_path(File.dirname(__FILE__) + '/bandersnatch.yml')
  config.logger = Logger.new(File.dirname(__FILE__) + '/../test.log')
end
