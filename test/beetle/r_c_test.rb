require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

module Beetle
  class ReturnCodesTest < Minitest::Test
    test "inspecting a return code should display the name of the returncode" do
      assert_equal "Beetle::RC::OK", Beetle::RC::OK.inspect
    end
  end
end
