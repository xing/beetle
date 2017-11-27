require 'rubygems'
require 'simplecov'
SimpleCov.start do
  add_filter "/test/"
  add_filter "/lib/beetle/redis_ext.rb"
end

require 'minitest/autorun'
require 'minitest/unit'
require 'minitest/pride' if ENV['RAINBOW_COLORED_TESTS'] == "1" && $stdout.tty?
require 'minitest/stub_const'
require 'mocha/setup'

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
