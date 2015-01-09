require 'spec_helper'

describe ESReindex do
  let(:src)     { 'http://foo/bar_index' }
  let(:dst)     { 'http://biz/baz_index' }
  let(:options) { {update: true} }

  let(:reindexer) { ESReindex.new src, dst, options }

  it "can be freshly initialized with options" do
    expect(reindexer.options).to eq remove: false, update: true, frame: 1000, from_cli: false
  end

  it "starts with 0 indexes done" do
    expect(reindexer.done).to eq 0
  end

  describe "#go!" do
    after { reindexer.go! }

    context "when run as a PORO" do

      it "doesn't use #exit" do
        reindexer.stub :copy_mappings
        reindexer.stub :copy_docs
        expect(reindexer).not_to receive :exit
      end
    end

    context "when run from the CLI bin" do
      let(:options) { {from_cli: true} }

      it "exits 1 on failure" do
        expect(reindexer).to receive(:copy_mappings).and_return false
        expect(reindexer).to receive(:exit).with 1
      end

      it "exits 0 on success" do
        expect(reindexer).to receive(:copy_mappings).and_return true
        expect(reindexer).to receive(:copy_docs).and_return true
        expect(reindexer).to receive(:exit).with 0
      end
    end
  end

  skip "it can actually do stuff"
end
