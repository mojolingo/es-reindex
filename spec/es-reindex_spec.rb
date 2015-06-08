require 'spec_helper'

describe ESReindex do
  let(:src)     { 'http://foo/bar_index' }
  let(:dst)     { 'http://biz/baz_index' }
  let(:options) { {update: true} }

  let(:reindexer) { ESReindex.new src, dst, options }

  it "can be freshly initialized with options" do
    expect(reindexer.options).to eq remove: false, update: true, frame: 1000, from_cli: false, copy_mappings: true, :scroll=>"10m", :query=>{:query=>{:match_all=>{}}}
  end

  context "with invalid callback options" do
    let(:options) { {if: :not_a_proc} }

    it "fails" do
      expect{
        reindexer
      }.to raise_error ArgumentError, "if must be a callable object"
    end
  end

  it "starts with 0 indexes done" do
    expect(reindexer.done).to eq 0
  end

  describe "#copy!" do
    after { reindexer.copy! }

    before do
      %w{
        confirm clear_destination create_destination copy_docs check_docs
      }.each { |meth| reindexer.stub(meth).and_return true }
    end

    context "when run as a PORO" do
      it "doesn't use #exit" do
        expect(reindexer).to receive(:clear_destination).and_return false
        expect(reindexer).not_to receive :exit
      end
    end

    context "when run from the CLI bin" do
      let(:options) { {from_cli: true} }

      it "exits 1 on failure" do
        expect(reindexer).to receive(:clear_destination).and_return false
        expect(reindexer).to receive(:exit).with 1
      end

      it "exits 0 on success" do
        expect(reindexer).to receive(:exit).with 0
      end
    end
  end

  skip "it can actually do stuff"
end
