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
