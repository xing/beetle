# WebSocket Ruby Native Extension

- Travis CI build: [![](http://travis-ci.org/imanel/websocket-ruby-native.png)](http://travis-ci.org/imanel/websocket-ruby-native)
- Autobahn tests: [server](http://imanel.github.com/websocket-ruby/autobahn/server/), client

This gem adds native C and Java extensions for [WebSocket gem](http://github.com/imanel/websocket-ruby). Difference between using it and staying with pure Ruby implementation is about 25%(more accurate data are available in autobahn test results)

## Installation

WebSocket Ruby Extensionhas has no external dependencies, so it can be installed from source or directly from rubygems:

```
gem install "websocket-native"
```

or via Gemfile:

```
gem "websocket-native"
```

## Usage

You don't need to do anything - WebSocket gem will autoload native extension whenever it is available. It's good idea to add it to Gemfile or gemspec to install it automatically with other gems.

## License

(The MIT License)

Copyright © 2012 Bernard Potocki

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the ‘Software’), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED ‘AS IS’, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
