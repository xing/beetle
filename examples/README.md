### Examples

Beetle ships with a number of [example scripts](http://github.com/xing/beetle/tree/master/examples/)

The top level Rakefile comes with targets to start several RabbitMQ and redis instances
locally. Make sure the corresponding binaries are in your search path. Open four new shell
windows and execute the following commands:

    rake rabbit:start1
    rake rabbit:start2
    rake redis:start:master
    rake redis:start:slave
