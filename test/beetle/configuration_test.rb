require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class ConfigurationTest < MiniTest::Unit::TestCase
    test "should load it's settings from a config file if that file exists" do
      config    = Configuration.new
      old_value = config.gc_threshold
      new_value = old_value + 1
      config_file_content = "gc_threshold: #{new_value}\n"
      IO.expects(:read).returns(config_file_content)

      config.config_file = "some/path/to/a/file"
      assert_equal new_value, config.gc_threshold
    end

    test "should log an error if the specified file does not exist" do
      config    = Configuration.new
      config.logger.expects(:error)
      assert_raises(Errno::ENOENT){ config.config_file = "some/path/to/a/file" }
    end

    test "should log to STDOUT if no log_file given" do
      config = Configuration.new
      Logger.expects(:new).with(STDOUT).returns(stub_everything)
      config.logger
    end

    test "should log to file if log_file given" do
      file = '/path/to/file'
      config = Configuration.new
      config.log_file = file
      Logger.expects(:new).with(file).returns(stub_everything)
      config.logger
    end
  end
end
