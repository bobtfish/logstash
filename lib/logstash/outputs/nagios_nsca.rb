require "logstash/outputs/base"
require "logstash/namespace"

# The nagios_nsca output is used for sending passive check results to Nagios
# through the NSCA protocol.
#
# This is useful if your Nagios server is not the same as the source host from
# where you want to send logs or alerts. If you only have one server, this
# output is probably overkill # for you, take a look at the 'nagios' output
# instead.
#
# Here is a sample config using the nagios_nsca output:
#     output {
#       nagios_nsca {
#         # specify the hostname or ip of your nagios server
#         host => "nagios.example.com"
#
#         # specify the port to connect to
#         port => 5667
#       }
#     }

class LogStash::Outputs::NagiosNsca < LogStash::Outputs::Base

  config_name "nagios_nsca"
  milestone 1

  # The status to send to nagios. Should be 0 = OK, 1 = WARNING, 2 = CRITICAL, 3 = UNKNOWN
  config :nagios_status, :validate => :string

  config :nagios_status_field, :validate => :string
  config :nagios_service_field, :validate => :string

  # The nagios host or IP to send logs to. It should have a NSCA daemon running.
  config :host, :validate => :string, :default => "localhost"

  # The port where the NSCA daemon on the nagios host listens.
  config :port, :validate => :number, :default => 5667

  # The path to the 'send_nsca' binary on the local host.
  config :send_nsca_bin, :validate => :path, :default => "/usr/sbin/send_nsca"

  # The path to the send_nsca config file on the local host.
  # Leave blank if you don't want to provide a config file.
  config :send_nsca_config, :validate => :path

  # The nagios 'host' you want to submit a passive check result to. This
  # parameter accepts interpolation, e.g. you can use @source_host or other
  # logstash internal variables.
  config :nagios_host, :validate => :string, :default => "%{@source_host}"

  # The nagios 'service' you want to submit a passive check result to. This
  # parameter accepts interpolation, e.g. you can use @source_host or other
  # logstash internal variables.
  config :nagios_service, :validate => :string, :default => "LOGSTASH"

  # The format to use when writing events to nagios. This value
  # supports any string and can include %{name} and other dynamic
  # strings.
  config :message_format, :validate => :string, :default => "%{@timestamp} %{@source}: %{@message}"

  public
  def register
    if @nagios_service_field and not @nagios_status_field
      raise("You have set nagios_service_field but not nagios_status_field - unsupported")
    end
    if @nagios_status_field and not @nagios_service_field
      raise("You have set nagios_status_field but not nagios_service_field - unsupported")
    end
  end

  public
  def receive(event)
    # exit if type or tags don't match
    return unless output?(event)

    # catch logstash shutdown
    if event == LogStash::SHUTDOWN
      finished
      return
    end

    # skip if 'send_nsca' binary doesn't exist
    if !File.exists?(@send_nsca_bin)
      @logger.warn("Skipping nagios_nsca output; send_nsca_bin file is missing",
                   "send_nsca_bin" => @send_nsca_bin, "missed_event" => event)
      return
    end

    if @nagios_service_field and @nagios_status_field
      statuses = event[@nagios_status_field].to_a
      services = event[@nagios_service_field].to_a

      @logger.debug(" STATUSES: #{statuses.join(', ')} SERVICES: #{services.join(', ')}")

      if statuses.size != services.size
        @logger.warn("Skipping nagios_nsca output; field #{@nagios_service_field} had different number of entries to #{@nagios_status_field}", "missed_event" => event)
        return
      end

      services.each do |service|
        send_event(event, service, statuses.shift)
      end
    else
      send_event(event, event.sprintf(@nagios_service), event.sprintf(@nagios_status))
    end
  end # receive

  def send_event(event, nagios_service, status)
    # interpolate params
    nagios_host = event.sprintf(@nagios_host)

    # escape basic things in the log message
    # TODO: find a way to escape the message correctly
    msg = event.sprintf(@message_format)
    msg.gsub!("\n", "<br/>")
    msg.gsub!("'", "&#146;")

    if status.to_i.to_s != status # Check it round-trips to int correctly
      msg = "status '#{status}' is not numeric"
      status = 2
    else
      status = status.to_i
      if status > 3 || status < 0
         msg "status must be > 0 and <= 3, not #{status}"
         status = 2
      end
    end

    # build the command
    # syntax: echo '<server>!<nagios_service>!<status>!<text>'  | \
    #           /usr/sbin/send_nsca -H <nagios_host> -d '!' -c <nsca_config>"
    cmd = %(echo '#{nagios_host}~#{nagios_service}~#{status}~#{msg}' |)
    cmd << %( #{@send_nsca_bin} -H #{@host} -p #{@port} -d '~')
    cmd << %( -c #{@send_nsca_config}) if @send_nsca_config
    cmd << %( 2>/dev/null >/dev/null)

    # N.B. system() run twice - never seems to return from the 2nd invocation
    #   Assume this is something insane about jruby threading, changing to backticks works fine!
    `#{cmd}`
    if $?.exitstatus != 0
      @logger.warn("Skipping nagios_nsca output; error calling send_nsca",
                   "status" => $?.exitstatus, "nagios_nsca_command" => cmd,
                   "missed_event" => event)
    end
  end # def send_event
end # class LogStash::Outputs::NagiosNsca

