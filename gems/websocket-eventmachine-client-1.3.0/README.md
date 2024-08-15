# WebSocket Client for Ruby

WebSocket-EventMachine-Client is Ruby WebSocket client based on EventMachine.

- [Autobahn tests](http://imanel.github.com/websocket-ruby/autobahn/client)
- [Docs](http://rdoc.info/github/imanel/websocket-eventmachine-client/master/frames)

## Installation

``` bash
gem install websocket-eventmachine-client
```

or in Gemfile

``` ruby
gem 'websocket-eventmachine-client'
```

## Simple client example

```ruby
EM.run do

  ws = WebSocket::EventMachine::Client.connect(:uri => 'ws://localhost:8080')

  ws.onopen do
    puts "Connected"
  end

  ws.onmessage do |msg, type|
    puts "Received message: #{msg}"
  end

  ws.onclose do |code, reason|
    puts "Disconnected with status code: #{code}"
  end

  EventMachine.next_tick do
    ws.send "Hello Server!"
  end

end
```

### UNIX Domain client

You can connect to a local UNIX domain socket instead of a remote `TCP` socket using `connect_unix_domain`:

```ruby
EM.run do
  ws = WebSocket::EventMachine::Client.connect_unix_domain('/var/run/wss.sock')
  # . . .
end
```

You can optionally specify the `:version`, `:headers`, and `:ssl` options to the method.

## Options

Following options can be passed to WebSocket::EventMachine::Client initializer:

- `[String] :host` - IP or host of server to connect
- `[Integer] :port` - Port of server to connect
- `[String] :uri` - Full URI for server(optional - use instead of host/port combination)
- `[Integer] :version` - Version of WebSocket to use. Default: 13
- `[Hash] :headers` - HTTP headers to use in the handshake. Example: `{'Cookie' => 'COOKIENAME=Value'}`
- `[Boolean] :ssl` - Force SSL/TLS regardless of URI scheme or port

## Methods

Following methods are available for WebSocket::EventMachine::Client object:

### onopen

Called after successfully connecting.

Example:

```ruby
ws.onopen do
  puts "Client connected"
end
```

### onclose

Called after closing connection.

Parameters:

- `[Integer] code` - status code
- `[String] reason` - optional reason for closure

Example:

```ruby
ws.onclose do |code, reason|
  puts "Client disconnected with status code: #{code} and reason: #{reason}"
end
```

### onmessage

Called when client receive message.

Parameters:

- `[String] message` - content of message
- `[Symbol] type` - type is type of message(:text or :binary)

Example:

```ruby
ws.onmessage do |msg, type|
  puts "Received message: #{msg} or type: #{type}"
end
```

### onerror

Called when client discovers error.

Parameters:

- `[String] error` - error reason.

Example:

```ruby
ws.onerror do |error|
  puts "Error occured: #{error}"
end
```

### onping

Called when client receive ping request. Pong request is sent automatically.

Parameters:

- `[String] message` - message for ping request.

Example:

```ruby
ws.onping do |message|
  puts "Ping received: #{message}"
end
```

### onpong

Called when client receive pong response.

Parameters:

- `[String] message` - message for pong response.

Example:

```ruby
ws.onpong do |message|
  puts "Pong received: #{message}"
end
```

### send

Sends message to server.

Parameters:

- `[String] message` - message that should be sent to server
- `[Hash] params` - params for message(optional)
  - `[Symbol] :type` - type of message. Valid values are :text, :binary(default is :text)

Example:

```ruby
ws.send "Hello Server!"
ws.send "binary data", :type => :binary
```

### close

Closes connection and optionally send close frame to server.

Parameters:

- `[Integer] code` - code of closing, according to WebSocket specification(optional)
- `[String] data` - data to send in closing frame(optional)

Example:

```ruby
ws.close
```

### ping

Sends ping request.

Parameters:

- `[String] data` - data to send in ping request(optional)

Example:

```ruby
ws.ping 'Hi'
```

### pong

Sends pong request. Usually there should be no need to send this request, as pong responses are sent automatically by client.

Parameters:

- `[String] data` - data to send in pong request(optional)

Example:

``` ruby
ws.pong 'Hello'
```

## License

The MIT License - Copyright (c) 2012 Bernard Potocki
