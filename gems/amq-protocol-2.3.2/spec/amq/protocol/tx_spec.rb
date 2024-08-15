# encoding: binary

module AMQ
  module Protocol
    class Tx
      RSpec.describe Select do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            method_frame = Select.encode(channel)
            expect(method_frame.payload).to eq("\000Z\000\n")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      # RSpec.describe SelectOk do
      #   describe '.decode' do
      #   end
      # end

      RSpec.describe Commit do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            method_frame = Commit.encode(channel)
            expect(method_frame.payload).to eq("\000Z\000\024")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      # RSpec.describe CommitOk do
      #   describe '.decode' do
      #   end
      # end

      RSpec.describe Rollback do
        describe '.encode' do
          it 'encodes the parameters into a MethodFrame' do
            channel = 1
            method_frame = Rollback.encode(channel)
            expect(method_frame.payload).to eq("\000Z\000\036")
            expect(method_frame.channel).to eq(1)
          end
        end
      end

      # RSpec.describe RollbackOk do
      #   describe '.decode' do
      #   end
      # end
    end
  end
end
