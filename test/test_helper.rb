require 'rubygems'
require 'test/unit'
require File.expand_path(File.dirname(__FILE__) + '/../lib/beetle')
require 'mocha'
require 'active_support/testing/declarative'

begin
  require 'redgreen' unless ENV['TM_FILENAME']
rescue LoadError => e
end

# we can remove this hack which is needed only for testing
begin
  require 'qrack/errors'
rescue LoadError
  module Qrack
    class BufferOverflowError < StandardError; end
    class InvalidTypeError < StandardError; end
  end
end


class Test::Unit::TestCase
  extend ActiveSupport::Testing::Declarative
end


Beetle.config.logger = Logger.new(File.dirname(__FILE__) + '/../test.log')
Beetle.config.redis_server = "localhost:6379"

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
