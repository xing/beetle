#!/usr/bin/env ruby
# encoding: utf-8

require "bundler"
Bundler.setup

$:.unshift(File.expand_path("../../../lib", __FILE__))

require "amqp"

EventMachine.run do
  AMQP.connect do |connection|
    channel1  = AMQP::Channel.new(connection)
    channel2  = AMQP::Channel.new(connection)
    exchange = channel1.direct("amqpgem.examples.exchanges.direct", :auto_delete => true)

    q1 = channel1.queue("amqpgem.examples.queues.shared", :auto_delete => true).bind(exchange, :routing_key => "shared.key")
    q1.subscribe do |payload|
      puts "Queue #{q1.name} on channel 1 received #{payload}"
    end

    # since the queue is shared, binding here is redundant but we will leave it in for completeness.
    q2 = channel2.queue("amqpgem.examples.queues.shared", :auto_delete => true).bind(exchange, :routing_key => "shared.key")
    q2.subscribe do |payload|
      puts "Queue #{q2.name} on channel 2 received #{payload}"
    end

    # Publish some test data in a bit, after all queues are declared & bound
    EventMachine.add_timer(1.2) do
      5.times { |i| exchange.publish("Hello #{i}, direct exchanges world!", :routing_key => "shared.key") }
    end


    show_stopper = Proc.new { connection.close { EventMachine.stop } }

    Signal.trap "TERM", show_stopper
    EM.add_timer(3, show_stopper)
  end
end
