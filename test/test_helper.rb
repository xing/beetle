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

Beetle.config.logger = Logger.new(File.dirname(__FILE__) + '/../test.log')

def header_with_params(opts = {})
  beetle_headers = Beetle::Message.publishing_options(opts)
  header = mock("header")
  header.stubs(:properties).returns(beetle_headers)
  header
end

def redis_stub(name, opts = {})
  opts = {'host' => "foo", 'port' => 123, 'server' => "foo:1234"}.update(opts)
  stub(name, opts)
end

def stub_configurator_class
  Beetle::Configurator.active_master = nil
  dumb_client = Beetle::Client.new
  dumb_client.stubs(:publish)
  dumb_client.stubs(:subscribe)
  Beetle::Configurator.client = dumb_client
  Beetle::Configurator.client.deduplication_store.redis_instances = []
end