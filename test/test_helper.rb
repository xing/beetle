require 'rubygems'
require 'active_support'
require 'active_support/testing/declarative'
require 'test/unit'
begin
  require 'redgreen' unless ENV['TM_FILENAME'] 
rescue MissingSourceFile
end
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
  default_port = opts['port'] || "1234"
  default_host = opts['host'] || "foo"
  opts = {'host' => default_host, 'port' => default_port, 'server' => "#{default_host}:#{default_port}"}.update(opts)
  stub(name, opts)
end

def stub_watcher_class
  Beetle::RedisWatcher.active_master = nil
  dumb_client = Beetle::Client.new
  dumb_client.stubs(:publish)
  dumb_client.stubs(:subscribe)
  Beetle::RedisWatcher.client = dumb_client
  Beetle::RedisWatcher.client.deduplication_store.redis_instances = []
end

def add_alive_server(server)
  Beetle::RedisWatcher.give_master({'server_name' => server})
end