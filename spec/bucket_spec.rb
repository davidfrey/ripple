# Copyright 2010 Sean Cribbs, Sonian Inc., and Basho Technologies, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
require File.join(File.dirname(__FILE__), "spec_helper")

describe Riak::Bucket do
  before :each do
    @client = Riak::Client.new
    @bucket = Riak::Bucket.new(@client, "foo")
  end

  def do_load(overrides={})
    @bucket.load({
                   :body => '{"props":{"name":"foo","allow_mult":false,"big_vclock":50,"chash_keyfun":{"mod":"riak_util","fun":"chash_std_keyfun"},"linkfun":{"mod":"jiak_object","fun":"mapreduce_linkfun"},"n_val":3,"old_vclock":86400,"small_vclock":10,"young_vclock":20},"keys":["bar"]}',
                   :headers => {
                     "vary" => ["Accept-Encoding"],
                     "server" => ["MochiWeb/1.1 WebMachine/1.5.1 (hack the charles gibson)"],
                     "link" => ['</raw/foo/bar>; riaktag="contained"'],
                     "date" => ["Tue, 12 Jan 2010 15:30:43 GMT"],
                     "content-type" => ["application/json"],
                     "content-length" => ["257"]
                   }
                 }.merge(overrides))
  end


  describe "when initializing" do
    it "should require a client and a name" do
      lambda { Riak::Bucket.new }.should raise_error
      lambda { Riak::Bucket.new(@client) }.should raise_error
      lambda { Riak::Bucket.new("foo") }.should raise_error
      lambda { Riak::Bucket.new("foo", @client) }.should raise_error
      lambda { Riak::Bucket.new(@client, "foo") }.should_not raise_error
    end

    it "should set the client and name attributes" do
      bucket = Riak::Bucket.new(@client, "foo")
      bucket.client.should == @client
      bucket.name.should == "foo"
    end
  end

  describe "when loading data from an HTTP response" do
    it "should load the bucket properties from the response body" do
      do_load
      @bucket.props.should == {"name"=>"foo","allow_mult" => false,"big_vclock" => 50,"chash_keyfun" => {"mod" =>"riak_util","fun"=>"chash_std_keyfun"},"linkfun"=>{"mod"=>"jiak_object","fun"=>"mapreduce_linkfun"},"n_val"=>3,"old_vclock"=>86400,"small_vclock"=>10,"young_vclock"=>20}
    end

    it "should load the keys from the response body" do
      do_load
      @bucket.keys.should == ["bar"]
    end

    it "should raise an error for a response that is not JSON" do
      lambda do
        do_load(:headers => {"content-type" => ["text/plain"]})
      end.should raise_error(Riak::InvalidResponse)
    end

    it "should unescape key names" do
      do_load(:body => '{"keys":["foo", "bar%20baz"]}')
      @bucket.keys.should == ["foo", "bar baz"]
    end
  end

  describe "accessing keys" do
    before :each do
      @http = mock("HTTPBackend")
      @client.stub!(:http).and_return(@http)
    end

    it "should load the keys if not present" do
      @http.should_receive(:get).with(200, "foo", {:props => false}, {}).and_return({:headers => {"content-type" => ["application/json"]}, :body => '{"keys":["bar"]}'})
      @bucket.keys.should == ["bar"]
    end

    it "should allow reloading of the keys" do
      @http.should_receive(:get).with(200, "foo", {:props => false}, {}).and_return({:headers => {"content-type" => ["application/json"]}, :body => '{"keys":["bar"]}'})
      do_load # Ensures they're already loaded
      @bucket.keys(:reload => true).should == ["bar"]
    end

    it "should allow streaming keys through block" do
      # pending "Needs support in the raw_http_resource"
      @http.should_receive(:get).with(200, "foo", {:props => false}, {}).and_yield("{}").and_yield('{"keys":[]}').and_yield('{"keys":["bar"]}').and_yield('{"keys":["baz"]}')
      all_keys = []
      @bucket.keys do |list|
        all_keys.concat(list)
      end
      all_keys.should == ["bar", "baz"]
    end

    it "should unescape key names" do
      @http.should_receive(:get).with(200, "foo", {:props => false}, {}).and_return({:headers => {"content-type" => ["application/json"]}, :body => '{"keys":["bar%20baz"]}'})
      @bucket.keys.should == ["bar baz"]
    end
  end

  describe "setting the bucket properties" do
    before :each do
      @http = mock("HTTPBackend")
      @client.stub!(:http).and_return(@http)
    end

    it "should PUT the new properties to the bucket" do
      @http.should_receive(:put).with(204, "foo", '{"props":{"name":"foo"}}', {"Content-Type" => "application/json"}).and_return({:body => "", :headers => {}})
      @bucket.props = { :name => "foo" }
    end

    it "should raise an error if an invalid property is given" do
      lambda { @bucket.props = "blah" }.should raise_error(ArgumentError)
    end
  end

  describe "fetching an object" do
    before :each do
      @http = mock("HTTPBackend")
      @client.stub!(:http).and_return(@http)
    end

    it "should load the object from the server as a Riak::RObject" do
      @http.should_receive(:get).with(200, "foo", "db", {}, {}).and_return({:headers => {"content-type" => ["application/json"]}, :body => '{"name":"Riak","company":"Basho"}'})
      @bucket.get("db").should be_kind_of(Riak::RObject)
    end

    it "should use the given query parameters (for R value, etc)" do
      @http.should_receive(:get).with(200, "foo", "db", {:r => 2}, {}).and_return({:headers => {"content-type" => ["application/json"]}, :body => '{"name":"Riak","company":"Basho"}'})
      @bucket.get("db", :r => 2).should be_kind_of(Riak::RObject)
    end
  end
end
