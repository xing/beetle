Given /^a redis server "([^\"]*)" exists as master$/ do |redis_name|
  redis_server = RedisTestServer.find_or_initialize_by_name(redis_name)
  # redis_server.master!
  redis_server.start
end

Given /^a redis server "([^\"]*)" exists as slave of "([^\"]*)"$/ do |redis_name, redis_master|
  redis_server = RedisTestServer.find_or_initialize_by_name(redis_name)
  # redis_server.slave_of!(TestRedisServer.find_by_name(redis_master)) 
  redis_server.start
end

Given /^a redis configuration server process "([^\"]*)" exists$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

Given /^a redis configuration client process "([^\"]*)" exists$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

Given /^redis server "([^\"]*)" is down$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

Given /^the retry timeout for the redis master check is reached$/ do
  pending # express the regexp above with the code you wish you had
end

Then /^the role of "([^\"]*)" should be "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
end

Then /^the redis master of "([^\"]*)" should be "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
end

Given /^redis server "([^\"]*)" is down for less seconds than the retry timeout for the redis master check$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

Then /^the role of "([^\"]*)" should still be "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
end

Then /^the redis master of "([^\"]*)" should still be "([^\"]*)"$/ do |arg1, arg2|
  pending # express the regexp above with the code you wish you had
end

Given /^a reconfiguration round is in progress$/ do
  pending # express the regexp above with the code you wish you had
end

Then /^the redis master of "([^\"]*)" should be nil$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end

Given /^the retry timeout for the redis master determination is reached$/ do
  pending # express the regexp above with the code you wish you had
end

Given /^the redis configuration client process "([^\"]*)" is disconnected from the system queue$/ do |arg1|
  pending # express the regexp above with the code you wish you had
end