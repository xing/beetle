require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class RedisAssumptionsTest < Test::Unit::TestCase
    def setup
      @r = DeduplicationStore.new.redis
      @r.flushdb
    end

    test "trying to delete a non existent key doesn't throw an error" do
      assert !@r.del("hahahaha")
      assert !@r.exists("hahahaha")
    end

    test "msetnx returns 0 or 1" do
      assert_equal 1, @r.msetnx("a", 1, "b", 2)
      assert_equal "1", @r.get("a")
      assert_equal "2", @r.get("b")
      assert_equal 0, @r.msetnx("a", 3, "b", 4)
      assert_equal "1", @r.get("a")
      assert_equal "2", @r.get("b")
    end
  end

  class RedisFailoverTest < Test::Unit::TestCase
    def setup
      @store = DeduplicationStore.new("localhost:1, localhost:2")
    end

    test "redis instances should be created for all servers" do
      instances = @store.redis_instances
      assert_equal ["localhost:1", "localhost:2" ], instances.map(&:server)
    end

    test "searching a redis master should find one if there is one" do
      instances = @store.redis_instances
      instances.first.expects(:info).returns("role" => "slave")
      instances.second.expects(:info).returns("role" => "master")
      assert_equal instances.second, @store.redis
    end

    test "searching a redis master should find one even if one cannot be accessed" do
      instances = @store.redis_instances
      instances.first.expects(:info).raises("murks")
      instances.second.expects(:info).returns("role" => "master")
      assert_equal instances.second, @store.redis
    end

    test "searching a redis master should raise an exception if there is none" do
      instances = @store.redis_instances
      instances.first.expects(:info).returns("role" => "slave")
      instances.second.expects(:info).returns("role" => "slave")
      assert_raises(NoRedisMaster) { @store.find_redis_master }
    end

    test "searching a redis master should raise an exception if there is more than one" do
      instances = @store.redis_instances
      instances.first.expects(:info).returns("role" => "master")
      instances.second.expects(:info).returns("role" => "master")
      assert_raises(TwoRedisMasters) { @store.find_redis_master }
    end

    test "a redis operation protected with a redis failover block should succeed if it can find a new master" do
      instances = @store.redis_instances
      s = sequence("redis accesses")
      instances.first.expects(:info).returns("role" => "master").in_sequence(s)
      instances.second.expects(:info).returns("role" => "slave").in_sequence(s)
      assert_equal instances.first, @store.redis
      instances.first.expects(:get).with("foo:x").raises("disconnected").in_sequence(s)
      instances.first.expects(:info).raises("disconnected").in_sequence(s)
      instances.second.expects(:info).returns("role" => "master").in_sequence(s)
      instances.second.expects(:get).with("foo:x").returns("42").in_sequence(s)
      assert_equal("42", @store.get("foo", "x"))
    end

    test "a redis operation protected with a redis failover block should fail if it cannot find a new master" do
      instances = @store.redis_instances
      instances.first.expects(:info).returns("role" => "master")
      instances.second.expects(:info).returns("role" => "slave")
      assert_equal instances.first, @store.redis
      instances.first.stubs(:get).with("foo:x").raises("disconnected")
      instances.first.stubs(:info).raises("disconnected")
      instances.second.stubs(:info).returns("role" => "slave")
      @store.expects(:sleep).times(119)
      assert_raises(NoRedisMaster) { @store.get("foo", "x") }
    end
  end

end
