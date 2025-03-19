require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class ChannelsTest < Minitest::Test
    test "allows to set new channel with key" do
      @channels = Beetle::Channels.new
      o = Object.new
      o2 = Object.new

      @channels["key"] = o
      assert_equal @channels["key"].object_id, o.object_id

      @channels["key"] ||= o2
      assert_equal @channels["key"].object_id, o.object_id
    end

    test "multiple instances have their own state" do
      @channels = Beetle::Channels.new
      @channels2 = Beetle::Channels.new
      o = Object.new
      o2 = Object.new

      @channels["key"] = o
      assert_nil @channels2["key"]

      @channels2["key"] = o2
      refute_equal @channels["key"].object_id, @channels2["key"].object_id
    end

    test "different threads get their own state" do
      @channels = Beetle::Channels.new
      saw_key = nil

      th1 = Thread.new do
        @channels["key"] = Object.new
        sleep 1
      end

      th2 = Thread.new do
        saw_key = @channels["key"]
      end

      [th1, th2].each(&:join)

      assert_nil @channels["key"]
      refute saw_key
    end

    test "different threads with different instances get their own state" do
      @channels = Beetle::Channels.new
      @channels2 = Beetle::Channels.new
      o = Object.new
      saw_o = nil
      o2 = Object.new
      saw_o2 = nil

      Thread.new do
        @channels["key"] = o
        @channels2["key"] = o2
        saw_o = @channels["key"]
        saw_o2 = @channels2["key"]
      end.join

      assert saw_o
      assert saw_o2
      refute_equal saw_o.object_id, saw_o2.object_id
    end
  end
end
