# encoding: binary

module AMQ
  module Protocol
    class Channel
      RSpec.describe Open do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            out_of_band = ''
            method_frame = Open.encode(channel, out_of_band)
            expect(method_frame.payload).to eq("\x00\x14\x00\n\x00")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe OpenOk do
        describe '.decode' do
          subject do
            OpenOk.decode("\x00\x00\x00\x03foo")
          end

          its(:channel_id) { should eq('foo') }
        end
      end

      RSpec.describe Flow do
        describe '.decode' do
          subject do
            Flow.decode("\x01")
          end

          its(:active) { should be_truthy }
        end

        describe '.encode' do
          it 'encodes the parameters as a MethodFrame' do
            channel = 1
            active = true
            method_frame = Flow.encode(channel, active)
            expect(method_frame.payload).to eq("\x00\x14\x00\x14\x01")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe FlowOk do
        describe '.decode' do
          subject do
            FlowOk.decode("\x00")
          end

          its(:active) { should be_falsey }
        end

        describe '.encode' do
          it 'encodes the parameters as a MethodFrame' do
            channel = 1
            active = true
            method_frame = FlowOk.encode(channel, active)
            expect(method_frame.payload).to eq("\x00\x14\x00\x15\x01")
            expect(method_frame.channel).to eq(1)
          end
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


          context 'with code 404 and reply_text length > 127 characters' do
            subject do
              raw = "\x01\x94\x80NOT_FOUND - no binding 123456789012345678901234567890123 between exchange 'amq.topic' in vhost '/' and queue 'test' in vhost '/'\x002\x002"
              Close.decode(raw)
            end

            its(:reply_code) { should eq(404) }
            its(:reply_text) { should eq(%q{NOT_FOUND - no binding 123456789012345678901234567890123 between exchange 'amq.topic' in vhost '/' and queue 'test' in vhost '/'}) }
            its(:class_id) { should eq(50) }
            its(:method_id) { should eq(50) }
          end

          context 'with an error code' do
            it 'returns frame and lets calling code handle the issue' do
              Close.decode("\x01\x38\x08NO_ROUTE\x00\x00")
            end
          end
        end

        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            reply_code = 540
            reply_text = 'NOT_IMPLEMENTED'
            class_id = 0
            method_id = 0
            method_frame = Close.encode(channel, reply_code, reply_text, class_id, method_id)
            expect(method_frame.payload).to eq("\x00\x14\x00(\x02\x1c\x0fNOT_IMPLEMENTED\x00\x00\x00\x00")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe CloseOk do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            method_frame = CloseOk.encode(channel)
            expect(method_frame.payload).to eq("\x00\x14\x00\x29")
            expect(method_frame.channel).to eq(channel)
          end
        end
      end
    end
  end
end
