# -*- ruby -*-
# vim: set nosta noet ts=4 sw=4:
# encoding: utf-8

require 'loggability'
require 'newrelic_rpm'

require 'strelka' unless defined?( Strelka )
require 'strelka/app' unless defined?( Strelka::App )

# Monkeypatch NewRelic to use Loggability.
module NewRelic
	extend Loggability
	log_as :newrelic

	module Agent
		class AgentLogger

			# No-op this unhelpful crap
			remove_method :set_log_format!
			def set_log_format!; end

		end
	end

end


# Strelka::App plugin module for reporting application performance to New Relic.
module Strelka::App::NewRelic
	extend Strelka::Plugin,
	       Configurability

	include NewRelic::Agent::Instrumentation::ControllerInstrumentation


	# Library version constant
	VERSION = '0.0.3'

	# Version-control revision constant
	REVISION = %q$Revision$



	# Insert this plugin after routing in the app's stack
	run_after :routing, :templating

	# Configurability API -- load newrelic configuration from the 'newrelic'
	# section of the universal config. Since NewRelic's config is separate
	# this only *needs* to point to the newrelic.yml config file, but it can
	# also override settings from there
	config_key :newrelic


	### Configurability API -- configure this class with the appropriate
	### section of the universal config when it's installed.
	def self::configure( config=nil )
		if config
			logger = Loggability[ NewRelic ]
			ra_logger = NewRelic::Agent::AgentLogger.new( {:log_level => 'debug'}, '', logger )
			NewRelic::Agent.logger = ra_logger

			self.log.info "Applying NewRelic config: %p" % [ config.to_hash ]
			NewRelic::Agent.config.apply_config( config.to_hash, 1 )
		end

		super
	end


	### Set up the NewRelic agent.
	def run( * )
		self.start_newrelic_agent
		super
	end


	### Starts the New Relic agent in a background thread.
	def start_newrelic_agent
		options     = {
			framework: :ruby,
			dispatcher: :strelka
		}

		self.log.info "Starting the NewRelic agent with options: %p." % [ options ]
		NewRelic::Agent.manual_start( options )

		return self
	end


	### Mark and time the app.
	def handle_request( request )
		response = nil
		self.log.debug "[:newrelic] Instrumenting with NewRelic."

		request.notes[:rum_header] = NewRelic::Agent.browser_timing_header
		request.notes[:rum_footer] = NewRelic::Agent.browser_timing_footer

		txname = if !request.notes[:routing][:route].empty?
				note = request.notes[:routing][:route]
				self.log.debug "Making route name out of the route notes: %p" % [ note ]
				self.make_route_name( note )
			else
				self.log.debug "Making route name out of the verb (%p) and app path (%p)" %
					[ request.verb, request.app_path ]
					"handle_request"
			end

		options = {
			name:     txname.to_s,
			request:  request,
			category: 'Controller/Strelka',
		}
		return self.perform_action_with_newrelic_trace( options ) do
			super
		end

	rescue => err
		NewRelic::Agent.notice_error( err.message )
		raise
	end


	### Make a normalized transaction name from the specified +route+.
	def make_route_name( route )
		action_method = route[:action] or return '(Unknown)'
		return action_method.name
	end

end # module Strelka::App::Metriks


