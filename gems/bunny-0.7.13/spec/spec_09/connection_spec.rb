# encoding: utf-8

# connection_spec.rb

require_relative "../spec_helper"

describe Bunny do

  it "should raise an error if the wrong user name or password is used" do
    b = Bunny.new(:spec => '0.9', :user => 'wrong')
    lambda { b.start}.should raise_error(Bunny::ProtocolError)
  end

  it "should merge custom settings from AMQP URL with default settings" do
    b = Bunny.new("amqp://tagadab", :spec => "0.9")
    b.host.should eql("tagadab")
  end

  it "should be able to open a TCPSocket with a timeout" do
    b = Bunny.new(:spec => "0.9")
    connect_timeout = 5
    lambda {
      Bunny::Timer::timeout(connect_timeout, Qrack::ConnectionTimeout) do
        TCPSocket.new(b.host, b.port)
      end
    }.should_not raise_error(Exception)
  end

end
