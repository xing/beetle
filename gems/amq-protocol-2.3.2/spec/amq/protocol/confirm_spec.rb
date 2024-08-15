# encoding: binary

module AMQ
  module Protocol
    class Confirm
      RSpec.describe Select do
        describe '.decode' do
          subject do
            Select.decode("\x01")
          end

          its(:nowait) { should be_truthy }
        end

        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            nowait = true
            method_frame = Select.encode(channel, nowait)
            expect(method_frame.payload).to eq("\x00U\x00\n\x01")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      RSpec.describe SelectOk do
        # describe '.decode' do
        # end

        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            method_frame = SelectOk.encode(channel)
            expect(method_frame.payload).to eq("\000U\000\v")
            expect(method_frame.channel).to eq(1)
          end
        end
      end
    end
  end
end
