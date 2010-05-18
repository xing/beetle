require File.expand_path(File.dirname(__FILE__) + '/../../lib/beetle')

After do
  RedisTestServer.stop_all
end
