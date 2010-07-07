require File.expand_path(File.dirname(__FILE__) + '/../test_helper')
require 'tempfile'

module Beetle
  class ConfigurationTest < Test::Unit::TestCase
    test "should load it's settings from a config file if that file exists" do
      config    = Configuration.new
      old_value = config.gc_threshold
      new_value = old_value + 1
      config_file_content = "gc_threshold: #{new_value}\n"
      IO.expects(:read).returns(config_file_content)

      config.config_file = "some/path/to/a/file"
      assert_equal new_value, config.gc_threshold
    end
  end
end