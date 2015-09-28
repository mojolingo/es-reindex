require 'spec_helper'

describe ESReindex::ArgsParser do

  let(:parsed_args)  { described_class.parse args }
  let(:parsed_src)   { parsed_args[0] }
  let(:parsed_dst)   { parsed_args[1] }
  let(:parsed_opts)  { parsed_args[2] }

  context "with no src or dst" do
    let(:args) { ["-r", "-u"] }

    it "src is nil" do
      expect(parsed_src).to be_nil
    end

    it "dst is nil" do
      expect(parsed_dst).to be_nil
    end
  end

  context "with a src" do
    let(:args) { ["-r", "-u", "http://foo/index"] }

    it "src is set" do
      expect(parsed_src).to eq 'http://foo/index'
    end

    it "dst is nil" do
      expect(parsed_dst).to be_nil
    end
  end

  context "with a src and dst" do
    let(:args) { ["-r", "-u", "http://foo/index", "bar/index"] }

    it "src is set" do
      expect(parsed_src).to eq 'http://foo/index'
    end

    it "dst is set" do
      expect(parsed_dst).to eq 'bar/index'
    end
  end

  context "without -f" do
    let(:args) { ["-u"] }

    it "sets the frame to the default (1000)" do
      expect(parsed_opts[:frame]).to eq 1000
    end
  end

  context "with -f" do
    let(:args) { ["-f", "1500"] }

    it "sets the frame" do
      expect(parsed_opts[:frame]).to eq 1500
    end
  end

  context "without -u" do
    let(:args) { ["-f", '1000', 'foosrc/index'] }

    it "sets update to false" do
      expect(parsed_opts[:update]).to be false
    end
  end

  context "with -u" do
    let(:args) { ["-u"] }

    it "sets the frame" do
      expect(parsed_opts[:update]).to be true
    end
  end

  context "without -nm" do
    let(:args) { ["-u"] }

    it "sets copy_mappings to true" do
      expect(parsed_opts[:copy_mappings]).to be true
    end
  end

  context "with -nm" do
    let(:args) { ["-u", "-nm"] }

    it "sets copy_mappings to false" do
      expect(parsed_opts[:copy_mappings]).to be false
    end
  end
end
