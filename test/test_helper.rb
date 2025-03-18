require 'rubygems'
require 'simplecov'
SimpleCov.start do
  add_filter "/test/"
  add_filter "/lib/beetle/redis_ext.rb"
end

require 'minitest/autorun'
require 'minitest/unit'
require 'mocha/minitest'

require 'minitest/reporters'
if ENV['MINITEST_REPORTER']
  Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new(:color => true)]
else
  Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(:color => true)]
end

require File.expand_path(File.dirname(__FILE__) + '/../lib/beetle')
require 'eventmachine'

class Minitest::Test
  require "active_support/testing/declarative"
  extend ActiveSupport::Testing::Declarative
  require "webmock"
  WebMock.enable!
  include WebMock::API
  def assert_nothing_raised(*)
    yield
  end
end

I18n.enforce_available_locales = false

ENV['BEETLE_LOG_LEVEL'] = 'debug'
Beetle.config.log_file = File.dirname(__FILE__) + '/../test.log'
Beetle.config.servers = ENV["RABBITMQ_SERVERS"] || "localhost:5672"

if system('docker -v >/dev/null') && `docker inspect beetle-redis-master -f '{{.State.Status}}'`.chomp == "running"
  Beetle.config.redis_server = ENV["REDIS_SERVER"] || "localhost:6370"
  Beetle.config.redis_servers = ENV["REDIS_SERVERS"] || "localhost:6370,localhost:6380"
else
  Beetle.config.redis_server = ENV["REDIS_SERVER"] || "localhost:6379"
  Beetle.config.redis_servers = ENV["REDIS_SERVERS"] || "localhost:6379,localhost:6380"
end

def header_with_params(opts = {})
  beetle_headers = Beetle::Message.publishing_options(opts)
  header = mock("header")
  header.stubs(:attributes).returns(beetle_headers)
  header.stubs(:redelivered?).returns(false)
  header
end

def redis_stub(name, opts = {})
  default_port = opts['port'] || "1234"
  default_host = opts['host'] || "foo"
  opts = {'host' => default_host, 'port' => default_port, 'server' => "#{default_host}:#{default_port}"}.update(opts)
  stub(name, opts)
end

if system('docker -v >/dev/null') && `docker inspect beetle-mysql -f '{{.State.Status}}'`.chomp == "running"
  ENV['MYSQL_PORT'] = '6612'
end
