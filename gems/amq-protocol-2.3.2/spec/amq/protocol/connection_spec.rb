# encoding: binary

module AMQ
  module Protocol
    class Connection
      RSpec.describe Start do
        describe '.decode' do
          subject do
            Start.decode("\x00\t\x00\x00\x00\xFB\tcopyrightS\x00\x00\x00gCopyright (C) 2007-2010 LShift Ltd., Cohesive Financial Technologies LLC., and Rabbit Technologies Ltd.\vinformationS\x00\x00\x005Licensed under the MPL.  See http://www.rabbitmq.com/\bplatformS\x00\x00\x00\nErlang/OTP\aproductS\x00\x00\x00\bRabbitMQ\aversionS\x00\x00\x00\x052.2.0\x00\x00\x00\x0EPLAIN AMQPLAIN\x00\x00\x00\x05en_US")
          end

          its(:version_major) { should == 0 }
          its(:version_minor) { should == 9 }
          its(:server_properties) { should == {'copyright' => 'Copyright (C) 2007-2010 LShift Ltd., Cohesive Financial Technologies LLC., and Rabbit Technologies Ltd.', 'information' => 'Licensed under the MPL.  See http://www.rabbitmq.com/', 'platform' => 'Erlang/OTP', 'product' => 'RabbitMQ', 'version' => '2.2.0'} }
          its(:mechanisms) { should == 'PLAIN AMQPLAIN' }
          its(:locales) { should == 'en_US' }
        end
      end

      RSpec.describe StartOk do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            client_properties = {:platform => 'Ruby 1.9.2', :product => 'AMQ Client', :information => 'http://github.com/ruby-amqp/amq-client', :version => '0.2.0'}
            mechanism = 'PLAIN'
            response = "\x00guest\x00guest"
            locale = 'en_GB'
            method_frame = StartOk.encode(client_properties, mechanism, response, locale)
            # the order of the table parts isn't deterministic in Ruby 1.8
            expect(method_frame.payload[0, 8]).to eq("\x00\n\x00\v\x00\x00\x00x")
            expect(method_frame.payload).to include("\bplatformS\x00\x00\x00\nRuby 1.9.2")
            expect(method_frame.payload).to include("\aproductS\x00\x00\x00\nAMQ Client")
            expect(method_frame.payload).to include("\vinformationS\x00\x00\x00&http://github.com/ruby-amqp/amq-client")
            expect(method_frame.payload).to include("\aversionS\x00\x00\x00\x050.2.0")
            expect(method_frame.payload[-28, 28]).to eq("\x05PLAIN\x00\x00\x00\f\x00guest\x00guest\x05en_GB")
            expect(method_frame.payload.length).to eq(156)
          end
        end
      end

      RSpec.describe Secure do
        describe '.decode' do
          subject do
            Secure.decode("\x00\x00\x00\x03foo")
          end

          its(:challenge) { should eq('foo') }
        end
      end

      RSpec.describe SecureOk do
        describe '.encode' do
          it 'encodes the parameters as a MethodFrame' do
            response = 'bar'
            method_frame = SecureOk.encode(response)
            expect(method_frame.payload).to eq("\x00\x0a\x00\x15\x00\x00\x00\x03bar")
          end
        end
      end

      RSpec.describe Tune do
        describe '.decode' do
          subject do
            Tune.decode("\x00\x00\x00\x02\x00\x00\x00\x00")
          end

          its(:channel_max) { should eq(0) }
          its(:frame_max) { should eq(131072) }
          its(:heartbeat) { should eq(0) }
        end
      end

      RSpec.describe TuneOk do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel_max = 0
            frame_max = 65536
            heartbeat = 1
            method_frame = TuneOk.encode(channel_max, frame_max, heartbeat)
            expect(method_frame.payload).to eq("\x00\n\x00\x1F\x00\x00\x00\x01\x00\x00\x00\x01")
          end
        end
      end

      RSpec.describe Open do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            vhost = '/test'
            method_frame = Open.encode(vhost)
            expect(method_frame.payload).to eq("\x00\n\x00(\x05/test\x00\x00")
          end
        end
      end

      RSpec.describe OpenOk do
        describe '.decode' do
          subject do
            OpenOk.decode("\x00")
          end

          its(:known_hosts) { should eq('') }
        end
      end

      RSpec.describe Close do
        describe '.decode' do
          context 'with code 200' do
            subject do
              Close.decode("\x00\xc8\x07KTHXBAI\x00\x05\x00\x06")
            end

            its(:reply_code) { should eq(200) }
            its(:reply_text) { should eq('KTHXBAI') }
            its(:class_id) { should eq(5) }
            its(:method_id) { should eq(6) }
          end

          context 'with an error code' do
            it 'returns method frame and lets calling code handle the issue' do
              Close.decode("\x01\x38\x08NO_ROUTE\x00\x00")
            end
          end
        end

        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            reply_code = 540
            reply_text = 'NOT_IMPLEMENTED'
            class_id = 0
            method_id = 0
            method_frame = Close.encode(reply_code, reply_text, class_id, method_id)
            expect(method_frame.payload).to eq("\x00\x0a\x002\x02\x1c\x0fNOT_IMPLEMENTED\x00\x00\x00\x00")
          end
        end
      end

      RSpec.describe CloseOk do
        describe '.encode' do
          it 'encodes a MethodFrame' do
            method_frame = CloseOk.encode
            expect(method_frame.payload).to eq("\x00\n\x003")
          end
        end
      end
    end
  end
end
