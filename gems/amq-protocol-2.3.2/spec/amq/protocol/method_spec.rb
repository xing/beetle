module AMQ
  module Protocol
    RSpec.describe Method do
      describe '.split_headers' do
        it 'splits user defined headers into properties and headers' do
          input = {:delivery_mode => 2, :content_type => 'application/octet-stream', :foo => 'bar'}
          properties, headers = Method.split_headers(input)
          expect(properties).to eq({:delivery_mode => 2, :content_type => 'application/octet-stream'})
          expect(headers).to eq({:foo => 'bar'})
        end
      end

      describe '.encode_body' do
        context 'when the body fits in a single frame' do
          it 'encodes a body into a BodyFrame' do
            body_frames = Method.encode_body('Hello world', 1, 131072)
            expect(body_frames.first.payload).to eq('Hello world')
            expect(body_frames.first.channel).to eq(1)
            expect(body_frames.size).to eq(1)
          end
        end

        context 'when the body is too big to fit in a single frame' do
          it 'encodes a body into a list of BodyFrames that each fit within the frame size' do
            lipsum = 'Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.'
            frame_size = 100
            expected_payload_size = 92
            body_frames = Method.encode_body(lipsum, 1, frame_size)
            expect(body_frames.map(&:payload)).to eq(lipsum.split('').each_slice(expected_payload_size).map(&:join))
          end
        end

        context 'when the body fits perfectly in a single frame' do
          it 'encodes a body into a single BodyFrame' do
            body_frames = Method.encode_body('*' * 131064, 1, 131072)
            expect(body_frames.first.payload).to eq('*' * 131064)
            expect(body_frames.size).to eq(1)
          end
        end
      end
    end
  end
end
