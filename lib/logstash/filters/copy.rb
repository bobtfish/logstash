require "logstash/filters/base"
require "logstash/namespace"

# The copy filter is for duplicating messages into separate events.
#
# An example use case of this filter is for taking a message to be output
# to elasticsearch, and copying it to add another tag (which is excluded
# by your elasticsearch output).
#
# You can then mutate this copied event further (for example replacing
# . for _ in the @source_host field) before using it in another output
# (for example statsd)
#
# The end result of each copy is a complete copy of the message with
# a new type. Note that this new message runs through _all_ filters
# including any uses of the copy filter - it's possible to write
# a config which creates infinite messages - beware!

class LogStash::Filters::Copy < LogStash::Filters::Base

  config_name "copy"
  plugin_status "experimental"

  config :new_type, :validate => :string, :required => true

  public
  def register
    # Nothing to do
  end # def register

  public
  def filter(event)
    return unless filter?(event)

    event_copied = event.clone
    event_copied['@type'] = @new_type
    @logger.debug("Copied event", :event => event_copied)

    yield event_copied

    # Emit original event
    filter_matched(event)
  end # def filter
end # class LogStash::Filters::Copy

