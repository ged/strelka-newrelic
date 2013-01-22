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
end


# Strelka::App plugin module for Metriks statistics and analysis.
module Strelka::App::NewRelic
	extend Strelka::Plugin,
	       Configurability

	include NewRelic::Agent::Instrumentation::ControllerInstrumentation


	# Library version constant
	VERSION = '0.0.1'

	# Version-control revision constant
	REVISION = %q$Revision$



	# Insert this plugin after routing in the app's stack
	run_after :routing

	# Configurability API -- load newrelic configuration from the 'newrelic'
	# section of the universal config. Since NewRelic's config is separate
	# this only *needs* to point to the newrelic.yml config file, but it can
	# also override settings from there
	config_key :newrelic


	### Configurability API -- configure this class with the appropriate
	### section of the universal config when it's installed.
	def self::configure( config=nil )
		if config
			self.log.info "Applying NewRelic config: %p" % [ config.to_hash ]
			NewRelic::Agent.config.apply_config( config.to_hash, 1 )
		end
	end


	### Set up the NewRelic agent.
	def run( * )
		logger = Loggability[ NewRelic ]
	    log_wrapper = NewRelic::Agent::AgentLogger.new( {:log_level => :debug}, '', logger )
	    NewRelic::Agent.logger = log_wrapper

		environment = 'development' if self.class.in_devmode?
		options = { env: environment, log: Loggability[NewRelic] }

		self.log.info "Starting the NewRelic agent."
		NewRelic::Agent.manual_start( options )
		self.log.info "  started."

		super
	end


	### Mark and time the app.
	def handle_request( request )
		self.log.debug "[:newrelic] Instrumenting with NewRelic."

		txname = if request.notes[:routing][:route]
				note = request.notes[:routing][:route]
				self.log.debug "Making route name out of the route notes: %p" % [ note ]
				self.make_route_name( note )
			else
				self.log.debug "Making route name out of the verb (%p) and app path (%p)" %
					[ request.verb, request.app_path ]
				"%s %s" % [ request.verb, request.app_path ]
			end

		self.log.debug "  txname is: %p" % [ txname ]
		options = { name: txname.to_s, request: request, class_name: self.app_id }
		self.perform_action_with_newrelic_trace( options ) do
			super
		end

	end


	### Make a normalized transaction name from the specified +route+.
	def make_route_name( route )
		action_method = route[:action] or return '(Unknown)'
		return action_method.name
	end

end # module Strelka::App::Metriks


