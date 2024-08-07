require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class ConfigurationTest < Minitest::Test
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

    test "#brokers returns a hash of the configured brokers" do
      config = Configuration.new
      assert_equal({"servers"=>"localhost:5672", "additional_subscription_servers"=>""}, config.brokers)
    end

    test "#config_file can be a JSON file" do
      file = '/path/to/file.json'
      config = Configuration.new
      IO.expects(:read).with(file).returns(
        {
          servers: 'localhost:5772',
          additional_subscription_servers: '10.0.0.1:3001'
        }.to_json)

      config.config_file = file

      assert_equal "localhost:5772", config.servers
      assert_equal "10.0.0.1:3001", config.additional_subscription_servers
    end

    test "#config_file can be a YAML file" do
      file = '/path/to/file.yml'
      config = Configuration.new
      IO.expects(:read).with(file).returns(
        {
          servers: 'localhost:5772',
          additional_subscription_servers: '10.0.0.1:3001'
        }.to_yaml)

      config.config_file = file

      assert_equal "localhost:5772", config.servers
      assert_equal "10.0.0.1:3001", config.additional_subscription_servers
    end
  end

  class ConnectionOptionsForServerTest < Minitest::Test
    test "returns the options for the server provided" do
      config = Configuration.new
      config.servers = 'localhost:5672'
      config.server_connection_options["localhost:5672"] = {host:  'localhost', port: 5672, user: "john", pass: "doe", vhost: "test", ssl: "0"}

      config.connection_options_for_server("localhost:5672").tap do |options|
        assert_equal "localhost", options[:host]
        assert_equal 5672, options[:port]
        assert_equal "john", options[:user]
        assert_equal "doe", options[:pass]
        assert_equal "test", options[:vhost]
        assert_equal "0", options[:ssl]
      end
    end

    test "returns default options if no options are set for the server" do
      config = Configuration.new
      config.servers = 'localhost:5672'

      config.connection_options_for_server("localhost:5672").tap do |options|
        assert_equal "localhost", options[:host]
        assert_equal 5672, options[:port]
        assert_equal "guest", options[:user]
        assert_equal "guest", options[:pass]
        assert_equal "/", options[:vhost]
        assert_nil options[:ssl]
      end
    end

    test "allows to set specific options while retaining defaults for the rest" do
      config = Configuration.new
      config.servers = 'localhost:5672'
      config.server_connection_options["localhost:5672"] = { pass: "another_pass", ssl: "1" }

      config.connection_options_for_server("localhost:5672").tap do |options|
        assert_equal "localhost", options[:host]
        assert_equal 5672, options[:port]
        assert_equal "guest", options[:user]
        assert_equal "another_pass", options[:pass]
        assert_equal "/", options[:vhost]
        assert_equal "1", options[:ssl]
      end
    end
  end
end
