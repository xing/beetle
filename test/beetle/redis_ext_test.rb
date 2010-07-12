require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class NonExistentRedisTest < Test::Unit::TestCase
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
  end

  class AddedRedisMethodsTest < Test::Unit::TestCase
    def setup
      @r = Redis.new(:host => "localhost", :port => 6390)
    end

    test "should return the host, port and server string" do
      assert_equal "localhost", @r.host
      assert_equal 6390, @r.port
      assert_equal "localhost:6390", @r.server
    end

    test "should stop slavery" do
      if Redis::VERSION < "2.0.0"
        @r.expects(:slaveof).with("no one")
      else
        @r.expects(:slaveof).with("no", "one")
      end
      @r.master!
    end

    test "should support slavery" do
      if Redis::VERSION < "2.0.0"
        @r.expects(:slaveof).with("localhost 6379")
      else
        @r.expects(:slaveof).with("localhost", 6379)
      end
      @r.slave_of!("localhost", 6379)
    end
  end

  class RedisTimeoutTest < Test::Unit::TestCase
    test "should use Redis::Timer if timeout is greater 0" do
      r = Redis.new(:host => "localhost", :port => 6390, :timeout => 1)
      Redis::Timer.expects(:timeout).with(1).raises(Timeout::Error)
      assert_equal({}, r.info_with_rescue)
    end

    test "should not use Redis::Timer if timeout 0" do
      r = Redis.new(:host => "localhost", :port => 6390, :timeout => 0)
      Redis::Timer.expects(:timeout).never
      assert_equal({}, r.info_with_rescue)
    end
  end
end
