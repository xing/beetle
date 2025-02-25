require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class ChannelsTest < Minitest::Test
    test "allows to set new channel with key" do
      @channels = Beetle::Channels.new
      o = Object.new

      @channels["key"] = o
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
  end
end
