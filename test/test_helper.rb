require 'rubygems'
require 'simplecov'
SimpleCov.start do
  add_filter "/test/"
  add_filter "/lib/beetle/redis_ext.rb"
end

require 'minitest/autorun'
require 'minitest/unit'
require 'minitest/pride' if ENV['RAINBOW_COLORED_TESTS'] == "1" && $stdout.tty?
require 'mocha/setup'

require File.expand_path(File.dirname(__FILE__) + '/../lib/beetle')
require 'eventmachine'

class MiniTest::Unit::TestCase
  require "active_support/testing/declarative"
  extend ActiveSupport::Testing::Declarative
  require "webmock"
  include WebMock::API
  def assert_nothing_raised(*)
    yield
  end
end

I18n.enforce_available_locales = false

Beetle.config.logger = Logger.new(File.dirname(__FILE__) + '/../test.log')
Beetle.config.redis_server = "localhost:6379"
Beetle.config.redis_servers = "localhost:6379,localhost:6380"
Beetle.config.servers = "127.0.0.1:5672"

def header_with_params(opts = {})
  beetle_headers = Beetle::Message.publishing_options(opts)
  header = mock("header")
  header.stubs(:attributes).returns(beetle_headers)
  header
end


def redis_stub(name, opts = {})
  default_port = opts['port'] || "1234"
  default_host = opts['host'] || "foo"
  opts = {'host' => default_host, 'port' => default_port, 'server' => "#{default_host}:#{default_port}"}.update(opts)
  stub(name, opts)
end
