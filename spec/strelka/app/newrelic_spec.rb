# -*- ruby -*-
# vim: set nosta noet ts=4 sw=4:
# encoding: utf-8

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent.parent

	srcdir = basedir.parent
	strelkadir = srcdir + 'Strelka/lib'

	$LOAD_PATH.unshift( strelkadir.to_s ) unless $LOAD_PATH.include?( strelkadir.to_s )
	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
}

require 'rspec'

require 'strelka'
require 'strelka/plugins'
require 'strelka/app/newrelic'

require 'mongrel2/testing'
require 'strelka/testing'
require 'strelka/behavior/plugin'
require 'loggability/spechelpers'

### Mock with RSpec
RSpec.configure do |c|
	c.mock_with( :rspec )

	c.include( Loggability::SpecHelpers )
	c.include( Mongrel2::SpecHelpers )
	c.include( Strelka::Testing )

	include Mongrel2::Constants
end


#####################################################################
###	C O N T E X T S
#####################################################################

describe Strelka::App::NewRelic do

	# 0mq socket specifications for Handlers
	TEST_SEND_SPEC = 'tcp://127.0.0.1:9998'
	TEST_RECV_SPEC = 'tcp://127.0.0.1:9997'


	before( :all ) do
		setup_logging()

		@request_factory = Mongrel2::RequestFactory.new( route: '' )

		@nr_config = {
			:beacon                 => 'beacon',
			:disable_mobile_headers => false,
			:browser_key            => 'browserKey',
			:application_id         => '5, 6', # collector can return app multiple ids
			:'rum.enabled'          => true,
			:episodes_file          => 'this_is_my_file',
			:'rum.jsonp'            => true,
			# :license_key            => 'a' * 40
		}
		NewRelic::Agent.config.apply_config( @nr_config )
	    @log_wrapper = NewRelic::Agent::AgentLogger.new( {:log_level => :debug}, '', Loggability[NewRelic] )
	    NewRelic::Agent.logger = @log_wrapper

	end

	after( :all ) do
		NewRelic::Agent.shutdown
		reset_logging()
	end


	it_should_behave_like( "A Strelka::App Plugin" )


	describe "an including App" do

		before( :each ) do
			@app = Class.new( Strelka::App ) do
				plugin :newrelic
				def initialize( appid='nr-test', sspec=TEST_SEND_SPEC, rspec=TEST_RECV_SPEC )
					super
				end
				def set_signal_handlers; end
				def start_accepting_requests; end
				def restore_signal_handlers; end
			end
		end


		it "starts the NewRelic agent when the app starts" do
			NewRelic::Agent.should_receive( :manual_start )
			@app.new.run
		end



		context "with routing" do

			before( :each ) do
				@app.instance_eval do
					plugin :parameters
					param :sku, :integer
			
					plugin :routing

					get '/foo' do |request|
						res = request.response
						res.status = HTTP::OK
						return res
					end
				
					post '/foo/:sku' do |request|
						res = request.response
						res.status = HTTP::OK
						return res
					end
				end
			end

			after( :each ) do
	            NewRelic::Agent.agent.stats_engine.reset_stats
			end


			it "records a trace for requests to simple routes" do
				request = @request_factory.get( '/foo' )
				response = @app.new.handle( request )
				response.status.should == HTTP::OK

	            engine = NewRelic::Agent.agent.stats_engine
	            engine.stats_hash.keys.map( &:to_s ).should include( 'Controller/nr-test/GET_foo' )
			end
			
		end




	end


end

