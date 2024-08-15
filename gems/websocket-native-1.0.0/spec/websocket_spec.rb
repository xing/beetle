require 'spec_helper'

describe 'WebSocket::Frame::Data' do

  subject { WebSocket::Frame::Data.new }

  it "should have mask_native defined" do
    subject.respond_to?(:mask_native).should be_true
  end

  it "should mask basic frame" do
    bytes = [1, 2, 3, 4]
    mask = [5, 6, 7, 8]
    result = [4, 4, 4, 12]
    subject.mask_native(bytes, mask).should eql(result)
  end

  it "should bask more advanced frame" do
    bytes = [72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33]
    mask  = [23, 142, 94, 24]
    result = [95, 235, 50, 116, 120, 162, 126, 111, 120, 252, 50, 124, 54]
    subject.mask_native(bytes, mask).should eql(result)
  end

end
