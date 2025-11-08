# require_relative '../../lib/utils'

RSpec.describe 'Unit test' do
  describe '.resample' do
    let(:samples) { [0, 1, 2, 3, 4] }

    context 'test samples' do
      it 'samples count' do
        expect(samples.length).to eq(5)
      end
    end
  end
end
