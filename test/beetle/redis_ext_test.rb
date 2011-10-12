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

    test "should not try toconnect to the redis server on inspect" do
      assert_nothing_raised { @r.inspect }
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
      @r.expects(:slaveof).with("no", "one")
      @r.master!
    end

    test "should support slavery" do
      @r.expects(:slaveof).with("localhost", 6379)
      @r.slave_of!("localhost", 6379)
    end
  end

  class HiredisLoadedTest < Test::Unit::TestCase
    test 'should be using hiredis instead of the redis ruby backend' do
      assert defined?(Hiredis)
    end
  end
end
