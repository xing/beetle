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

    test "find redis master should find the externally configured server" do
      @store.expects(:read_master_file).returns("localhost:1")
      assert_equal "localhost:1", @store.find_redis_master.server
    end

    test "find redis master should find none if the externally configured server is not in the list of instances" do
      @store.expects(:read_master_file).returns("")
      assert_nil @store.find_redis_master
    end

    test "autoconfigure should find the master if both master and slave are reachable" do
      instances = @store.redis_instances
      instances.first.stubs(:role).returns("slave")
      instances.second.stubs(:role).returns("master")
      assert_equal instances.second, @store.auto_configure
    end

    test "a redis operation protected with a redis failover block should succeed if it can find a new master" do
      instances = @store.redis_instances
      s = sequence("redis accesses")
      @store.expects(:read_master_file).returns("localhost:1").in_sequence(s)
      assert_equal instances.first, @store.redis
      @store.expects(:read_master_file).returns("localhost:1").in_sequence(s)
      instances.first.expects(:get).with("foo:x").raises("disconnected").in_sequence(s)
      @store.expects(:read_master_file).returns("localhost:2").in_sequence(s)
      instances.second.expects(:get).with("foo:x").returns("42").in_sequence(s)
      assert_equal("42", @store.get("foo", "x"))
    end

    test "a redis operation protected with a redis failover block should fail if it cannot find a new master" do
      instances = @store.redis_instances
      @store.stubs(:read_master_file).returns("localhost:1")
      assert_equal instances.first, @store.redis
      instances.first.stubs(:get).with("foo:x").raises("disconnected")
      @store.expects(:sleep).times(119)
      assert_raises(NoRedisMaster) { @store.get("foo", "x") }
    end
  end

end
