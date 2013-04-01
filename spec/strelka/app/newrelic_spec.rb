# -*- ruby -*-
# vim: set nosta noet ts=4 sw=4:
# encoding: utf-8

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent.parent

	srcdir = basedir.parent
	strelkadir = srcdir + 'Strelka/lib'

	nradir = basedir.parent.parent + 'newrelic/ruby_agent/lib'

	$LOAD_PATH.unshift( strelkadir.to_s ) unless $LOAD_PATH.include?( strelkadir.to_s )
	$LOAD_PATH.unshift( nradir.to_s ) unless $LOAD_PATH.include?( nradir.to_s )
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
			:application_id         => '5, 6', # collector can return multiple appids
			:'rum.enabled'          => true,
			:episodes_file          => 'this_is_my_file',
			:'rum.jsonp'            => true,
			:license_key            => 'a' * 40,
			:log_level              => :debug,
		}
		NewRelic::Agent.config.apply_config( @nr_config )
	end

	after( :all ) do
		NewRelic::Agent.shutdown
		reset_logging()
	end


	it_should_behave_like( "A Strelka::App Plugin" )


	describe "included in an App" do

		before( :each ) do
			@app = Class.new( Strelka::App ) do
				def self::name; "TestApp"; end

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

		context "that has routing" do

			before( :each ) do
				@app.instance_eval do
					plugin :parameters
					param :sku, :integer

					plugin :routing

					get '/foo' do |request|
						self.log.debug "Agent logger: %p" % [ NewRelic::Agent.logger ]
						NewRelic::Agent.logger.debug "DEBUG"
						NewRelic::Agent.logger.info "INFO"
						NewRelic::Agent.browser_timing_header
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

				# logdevice = Loggability[ NewRelic ]
				# logger = NewRelic::Agent::AgentLogger.new(NewRelic::Agent.config, '', logdevice )
				# NewRelic::Agent.logger = logger

			end

			after( :each ) do
	            NewRelic::Agent.agent.stats_engine.reset_stats
			end


			it "records a trace for requests to simple routes" do
				request = @request_factory.get( '/foo' )
				response = @app.new.start_newrelic_agent.handle( request )
				response.status.should == HTTP::OK

	            engine = NewRelic::Agent.agent.stats_engine
	            engine.metrics.should include(
					"HttpDispatcher",
					"Controller/Strelka/TestApp/GET_foo",
					"Apdex",
					"Apdex/Strelka/TestApp/GET_foo"
				)
			end

			it "adds browser timing javascript header and footer to the response notes" do
				request = @request_factory.get( '/foo' )
				response = @app.new.start_newrelic_agent.handle( request )

				response.notes[:rum_header].should =~ /NREUMQ/
				response.notes[:rum_footer].should =~ /NREUMQ/
			end

		end


	end


end

