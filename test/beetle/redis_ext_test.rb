require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class NonExistentRedisTest < Minitest::Test
    def setup
      @r = Redis.new(:host => "localhost", :port => 6390)
    end

    test "should return an empty hash for the info_with_rescue call" do
      assert_equal({}, @r.info_with_rescue)
    end

    test "should have a role of unknown" do
      assert_equal "unknown", @r.role
    end

    test "should not be available" do
      assert !@r.available?
    end

    test "should not be a master" do
      assert !@r.master?
    end

    test "should not be a slave" do
      assert !@r.slave?
      assert !@r.slave_of?("localhost", 6379)
    end

    test "should not try toconnect to the redis server on inspect" do
      assert_nothing_raised { @r.inspect }
    end
  end

  class AddedRedisMethodsTest < Minitest::Test
    def setup
      @r = Redis.new(:host => "localhost", :port => 6390)
    end

    test "should return the host, port and server string" do
      assert_equal "localhost", @r.host
      assert_equal 6390, @r.port
      assert_equal "localhost:6390", @r.server
    end

    test "should stop slavery" do
      @r.expects(:slaveof).with("no", "one")
      @r.master!
    end

    test "should support slavery" do
      @r.expects(:slaveof).with("localhost", 6379)
      @r.slave_of!("localhost", 6379)
    end
  end

  class HiredisLoadedTest < Minitest::Test
    test "should be using hiredis instead of the redis ruby backend" do
      if Redis::VERSION < "5.0"
        assert defined?(Hiredis)
      else
        assert_equal RedisClient.default_driver, RedisClient::HiredisConnection
      end
    end
  end

  class RedisShutdownTest < Minitest::Test
    def setup
      @r = Redis.new(:host => "localhost", :port => 6390)
    end

    if Redis::VERSION < "3.0"

      test "orginal redis shutdown implementation is broken" do
        @r.client.expects(:call_without_reply).with([:shutdown]).once
        @r.client.expects(:disconnect).never
        @r.broken_shutdown
      end

      test "patched redis shutdown implementation should call :shutdown and rescue Errno::ECONNREFUSED" do
        @r.client.expects(:call).with([:shutdown]).once.raises(Errno::ECONNREFUSED)
        @r.client.expects(:disconnect).once
        @r.shutdown
      end

    elsif Redis::VERSION < "4.0"

      test "redis shutdown implementation should call :shutdown and return nil" do
        @r.client.expects(:call).with([:shutdown]).once.raises(Redis::ConnectionError)
        assert_nil @r.shutdown
      end

    else

      test "patched redis shutdown implementation should not raise connection refused but return nil" do
        # note that we do not have redis running on port 6390
        assert_nil @r.shutdown
      end

    end
  end

end
