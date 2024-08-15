# encoding: binary

module AMQ
  module Protocol
    RSpec.describe AMQ::Protocol::Basic do
      describe '.encode_timestamp' do
        it 'encodes the timestamp as a 64 byte big endian integer' do
          expect(Basic.encode_timestamp(12345).last).to eq("\x00\x00\x00\x00\x00\x0009")
        end
      end

      # describe '.decode_timestamp' do
      #   it 'decodes the timestamp from a 64 byte big endian integer and returns a Time object' do
      #     expect(Basic.decode_timestamp("\x00\x00\x00\x00\x00\x0009")).to eq(Time.at(12345))
      #   end
      # end

      describe '.encode_headers' do
        it 'encodes the headers as a table' do
          expect(Basic.encode_headers(:hello => 'world').last).to eq("\x00\x00\x00\x10\x05helloS\x00\x00\x00\x05world")
        end
      end

      # describe '.decode_headers' do
      #   it 'decodes the headers from a table' do
      #     expect(Basic.decode_headers("\x00\x00\x00\x10\x05helloS\x00\x00\x00\x05world")).to eq({'hello' => 'world'})
      #   end
      # end

      describe '.encode_properties' do
        it 'packs the parameters into a byte array using the other encode_* methods' do
          result = Basic.encode_properties(10, {:priority => 0, :delivery_mode => 2, :content_type => 'application/octet-stream'})
          expect(result).to eq("\x00<\x00\x00\x00\x00\x00\x00\x00\x00\x00\x0a\x98\x00\x18application/octet-stream\x02\x00")
        end
      end

      describe '.decode_properties' do
        it 'unpacks the properties from a byte array using the decode_* methods' do
          result = Basic.decode_properties("\x98@\x18application/octet-stream\x02\x00\x00\x00\x00\x00\x00\x00\x00{")
          expect(result).to eq({:priority => 0, :delivery_mode => 2, :content_type => 'application/octet-stream', :timestamp => Time.at(123)})
        end

        it 'unpacks the properties from a byte array using the decode_* methods, including a table' do
          result = Basic.decode_properties("\xB8@\x18application/octet-stream\x00\x00\x00\x10\x05helloS\x00\x00\x00\x05world\x02\x00\x00\x00\x00\x00\x00\x00\x00{")
          expect(result).to eq({:priority => 0, :delivery_mode => 2, :content_type => 'application/octet-stream', :timestamp => Time.at(123), :headers => {'hello' => 'world'}})
        end
      end

      %w(content_type content_encoding correlation_id reply_to expiration message_id type user_id app_id cluster_id).each do |method|
        describe ".encode_#{method}" do
          it 'encodes the parameter as a Pascal string' do
            expect(Basic.send("encode_#{method}", 'hello world').last).to eq("\x0bhello world")
          end
        end

        # describe ".decode_#{method}" do
        #   it 'returns the string' do
        #     # the length has been stripped in .decode_properties
        #     expect(Basic.send("decode_#{method}", 'hello world')).to eq('hello world')
        #   end
        # end
      end

      %w(delivery_mode priority).each do |method|
        describe ".encode_#{method}" do
          it 'encodes the parameter as a char' do
            expect(Basic.send("encode_#{method}", 10).last).to eq("\x0a")
          end
        end

        # describe ".decode_#{method}" do
        #   it 'decodes the value from a char' do
        #     expect(Basic.send("decode_#{method}", "\x10")).to eq(16)
        #   end
        # end
      end
    end

    class Basic
      RSpec.describe Qos do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            prefetch_size = 3
            prefetch_count = 5
            global = false
            method_frame = Qos.encode(channel, prefetch_size, prefetch_count, global)
            expect(method_frame.payload).to eq("\x00<\x00\n\x00\x00\x00\x03\x00\x05\x00")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      # RSpec.describe QosOk do
      #   describe '.decode' do
      #   end
      # end

      RSpec.describe Consume do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            queue = 'foo'
            consumer_tag = 'me'
            no_local = false
            no_ack = false
            exclusive = true
            nowait = false
            arguments = nil
            method_frame = Consume.encode(channel, queue, consumer_tag, no_local, no_ack, exclusive, nowait, arguments)
            expect(method_frame.payload).to eq("\x00<\x00\x14\x00\x00\x03foo\x02me\x04\x00\x00\x00\x00")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe ConsumeOk do
        describe '.decode' do
          subject do
            ConsumeOk.decode("\x03foo")
          end

          its(:consumer_tag) { should eq('foo') }
        end
      end

      RSpec.describe Cancel do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            consumer_tag = 'foo'
            nowait = true
            method_frame = Cancel.encode(channel, consumer_tag, nowait)
            expect(method_frame.payload).to eq("\x00<\x00\x1E\x03foo\x01")
            expect(method_frame.channel).to eq(1)
          end
        end

        describe '.decode' do
          subject do
            CancelOk.decode("\x03foo\x01")
          end

          its(:consumer_tag) { should eq('foo') }
        end
      end

      RSpec.describe CancelOk do
        describe '.decode' do
          subject do
            CancelOk.decode("\x03foo")
          end

          its(:consumer_tag) { should eq('foo') }
        end
      end

      RSpec.describe Publish do
        describe '.encode' do
          it 'encodes the parameters into a list of MethodFrames' do
            channel = 1
            payload = 'Hello World!'
            user_headers = {:priority => 0, :content_type => 'application/octet-stream'}
            exchange = 'foo'
            routing_key = 'xyz'
            mandatory = false
            immediate = true
            frame_size = 512
            method_frames = Publish.encode(channel, payload, user_headers, exchange, routing_key, mandatory, immediate, frame_size)
            expect(method_frames[0].payload).to eq("\x00<\x00(\x00\x00\x03foo\x03xyz\x02")
            expect(method_frames[1].payload).to eq("\x00<\x00\x00\x00\x00\x00\x00\x00\x00\x00\f\x88\x00\x18application/octet-stream\x00")
            expect(method_frames[2].payload).to eq("Hello World!")
            expect(method_frames[0].channel).to eq(1)
            expect(method_frames[1].channel).to eq(1)
            expect(method_frames[2].channel).to eq(1)
            expect(method_frames.size).to eq(3)
          end
        end
      end

      RSpec.describe Return do
        describe '.decode' do
          subject do
            Return.decode("\x019\fNO_CONSUMERS\namq.fanout\x00")
          end

          its(:reply_code) { should eq(313) }
          its(:reply_text) { should eq('NO_CONSUMERS') }
          its(:exchange) { should eq('amq.fanout') }
          its(:routing_key) { should eq('') }
        end
      end

      RSpec.describe Deliver do
        describe '.decode' do
          subject do
            Deliver.decode("\e-1300560114000-445586772970\x00\x00\x00\x00\x00\x00\x00c\x00\namq.fanout\x00")
          end

          its(:consumer_tag) { should eq('-1300560114000-445586772970') }
          its(:delivery_tag) { should eq(99) }
          its(:redelivered) { should eq(false) }
          its(:exchange) { should eq('amq.fanout') }
          its(:routing_key) { should eq('') }
        end
      end

      RSpec.describe Get do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            queue = 'foo'
            no_ack = true
            method_frame = Get.encode(channel, queue, no_ack)
            expect(method_frame.payload).to eq("\x00\x3c\x00\x46\x00\x00\x03foo\x01")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe GetOk do
        describe '.decode' do
          subject do
            GetOk.decode("\x00\x00\x00\x00\x00\x00\x00\x06\x00\namq.fanout\x00\x00\x00\x00^")
          end

          its(:delivery_tag) { should eq(6) }
          its(:redelivered) { should eq(false) }
          its(:exchange) { should eq('amq.fanout') }
          its(:routing_key) { should eq('') }
          its(:message_count) { should eq(94) }
        end
      end

      RSpec.describe GetEmpty do
        describe '.decode' do
          subject do
            GetEmpty.decode("\x03foo")
          end

          its(:cluster_id) { should eq('foo') }
        end
      end

      RSpec.describe Ack do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            delivery_tag = 6
            multiple = false
            method_frame = Ack.encode(channel, delivery_tag, multiple)
            expect(method_frame.payload).to eq("\x00<\x00P\x00\x00\x00\x00\x00\x00\x00\x06\x00")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe Reject do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            delivery_tag = 8
            requeue = true
            method_frame = Reject.encode(channel, delivery_tag, requeue)
            expect(method_frame.payload).to eq("\x00<\x00Z\x00\x00\x00\x00\x00\x00\x00\x08\x01")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe RecoverAsync do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            requeue = true
            method_frame = RecoverAsync.encode(channel, requeue)
            expect(method_frame.payload).to eq("\x00<\x00d\x01")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe Recover do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            requeue = true
            method_frame = Recover.encode(channel, requeue)
            expect(method_frame.payload).to eq("\x00<\x00n\x01")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      # RSpec.describe RecoverOk do
      #   describe '.decode' do
      #   end
      # end

      RSpec.describe Nack do
        describe '.decode' do
          subject do
            Nack.decode("\x00\x00\x00\x00\x00\x00\x00\x09\x03")
          end

          its(:delivery_tag) { should eq(9) }
          its(:multiple) { should eq(true) }
          its(:requeue) { should eq(true) }
        end

        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            delivery_tag = 10
            multiple = false
            requeue = true
            method_frame = Nack.encode(channel, delivery_tag, multiple, requeue)
            expect(method_frame.payload).to eq("\x00<\x00x\x00\x00\x00\x00\x00\x00\x00\x0a\x02")
            expect(method_frame.channel).to eq(1)
          end
        end
      end
    end
  end
end
