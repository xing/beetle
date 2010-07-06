require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle

  class RedisAssumptionsTest < Test::Unit::TestCase
    def setup
      @r = DeduplicationStore.new(Client.new).redis
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

  class RedisServerStringTest < Test::Unit::TestCase
    def setup
      @original_redis_server = Beetle.config.redis_server
      @store = DeduplicationStore.new(Client.new)
      @server_string = "my_test_host_from_file:9999"
      Beetle.config.redis_server = @server_string
    end

    def teardown
      Beetle.config.redis_server = @original_redis_server
    end

    test "redis should match the redis server string" do
      assert_equal @server_string, @store.redis.server
    end
  end

  class RedisServerFileTest < Test::Unit::TestCase
    def setup
      @original_redis_server = Beetle.config.redis_server
      @store = DeduplicationStore.new(Client.new)
      @server_string = "my_test_host_from_file:6379"
      Beetle.config.redis_server = redis_test_master_file(@server_string)
    end

    def teardown
      Beetle.config.redis_server = @original_redis_server
    end

    test "redis should match the redis master file" do
      assert_equal @server_string, @store.redis.server
    end

    test "redis should be nil if the redis master file is blank" do
      redis_test_master_file("")
      assert_nil @store.redis
    end

    test "should keep using the current redis if the redis master file hasn't changed since the last request" do
      @store.expects(:read_master_file).once.returns("localhost:1")
      2.times { @store.redis }
    end

    def redis_test_master_file(server_string)
      path = File.expand_path("../../../tmp/redis-master-for-unit-tests", __FILE__)
      File.open(path, "w"){|f| f.puts server_string}
      path
    end
  end

  class RedisFailoverTest < Test::Unit::TestCase
    def setup
      @store = DeduplicationStore.new(Client.new)
    end

    test "a redis operation protected with a redis failover block should succeed if it can find a new master" do
      redis1 = stub()
      redis2 = stub()
      s = sequence("redis accesses")
      @store.expects(:redis).returns(redis1).in_sequence(s)
      redis1.expects(:get).with("foo:x").raises("disconnected").in_sequence(s)
      @store.expects(:redis).returns(redis1).in_sequence(s)
      redis1.expects(:server).returns("goofy").in_sequence(s)
      @store.expects(:redis).returns(redis2).in_sequence(s)
      redis2.expects(:get).with("foo:x").returns("42").in_sequence(s)
      assert_equal("42", @store.get("foo", "x"))
    end

    test "a redis operation protected with a redis failover block should fail if it cannot find a new master" do
      redis1 = stub()
      @store.stubs(:redis).returns(redis1)
      redis1.stubs(:get).with("foo:x").raises("disconnected")
      @store.expects(:sleep).times(Beetle.config.redis_operation_retries-1)
      assert_raises(NoRedisMaster) { @store.get("foo", "x") }
    end
  end

end
