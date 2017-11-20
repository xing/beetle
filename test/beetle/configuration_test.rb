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

    test "#redis_server default value" do
      Object.stub_const('ENV', ENV.to_hash.except('REDIS_HOST')) do
        config = Configuration.new
        assert_equal("localhost:6379", config.redis_server)
      end
    end

    test "#redis_server from ENV" do
      Object.stub_const('ENV', ENV.to_hash.merge('REDIS_HOST' => 'dear_catastrophe_waitress',
                                                 'REDIS_PORT' => 666)) do
        config = Configuration.new
        assert_equal("dear_catastrophe_waitress:666", config.redis_server)
      end
    end

    test "#redis_db default value" do
      Object.stub_const('ENV', ENV.to_hash.except('REDIS_PORT')) do
        config = Configuration.new
        assert_equal(4, config.redis_db)
      end
    end

    test "#redis_db from ENV" do
      Object.stub_const('ENV', ENV.to_hash.merge('REDIS_DB' => 7)) do
        config = Configuration.new
        assert_equal(7, config.redis_db)
      end
    end

    test "#brokers returns a hash of the configured brokers" do
      Object.stub_const('ENV', ENV.to_hash.except('RABBITMQ_HOST')) do
        config = Configuration.new
        assert_equal({"servers"=>"localhost:5672", "additional_subscription_servers"=>""}, config.brokers)
      end
    end

    test "#brokers returns a hash of the configured brokers from ENV" do
      Object.stub_const('ENV', ENV.to_hash.merge('RABBITMQ_HOST' => 'dear_catastrophe_waitress')) do
        config = Configuration.new
        assert_equal({"servers"=>"dear_catastrophe_waitress:5672", "additional_subscription_servers"=>""}, config.brokers)
      end
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
end
