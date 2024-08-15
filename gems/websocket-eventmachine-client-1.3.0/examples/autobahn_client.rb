require File.expand_path('../../lib/websocket-eventmachine-client', __FILE__)

require 'cgi'

EM.epoll
EM.run do

  host   = 'ws://localhost:9001'
  agent  = "WebSocket-EventMachine-Client (1.0.1)"
  cases  = 0
  skip   = []

  ws = WebSocket::EventMachine::Client.connect(:uri => "#{host}/getCaseCount")

  ws.onmessage do |msg, type|
    puts "$ Total cases to run: #{msg}"
    cases = msg.to_i
  end

  ws.onclose do

    run_case = lambda do |n|

      if n > cases
        puts "$ Requesting report"
        ws = WebSocket::EventMachine::Client.connect(:uri => "#{host}/updateReports?agent=#{CGI.escape agent}")
        ws.onclose do
          EM.stop
        end

      elsif skip.include?(n)
        EM.next_tick { run_case.call(n+1) }

      else
        ws = WebSocket::EventMachine::Client.connect(:uri => "#{host}/runCase?case=#{n}&agent=#{CGI.escape agent}")

        ws.onmessage do |msg, type|
          ws.send(msg, :type => type)
        end

        ws.onclose do |msg|
          EM.add_timer(0.1) { run_case.call(n + 1) }
        end
      end
    end

    run_case.call(1)
  end

end
