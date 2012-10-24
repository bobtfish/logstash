require "test_utils"
require "logstash/filters/copy"

describe LogStash::Filters::Copy do
  extend LogStash::RSpec

  describe "single grep match" do
    # The logstash config goes here.
    # At this time, only filters are supported.
    config <<-CONFIG
      filter {
        copy {
          new_type => "test"
        }
      }
    CONFIG

    sample ({"@fields" => {"str" => "moo"}}) do
      insist { subject.type } == "test"
    end
  end
end
