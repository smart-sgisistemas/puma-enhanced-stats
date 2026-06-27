# frozen_string_literal: true

require "json"
require "time"

require_relative "../version"

module Puma
  module Enhanced
    module Stats
      module CLI
        # Builds schema v1 payloads for the stub HTTP server.
        class StubPayloadBuilder
          FIXTURE_DIR = File.expand_path "../../../../../spec/fixtures/stub", __dir__

          class << self
            def build(scenario:, workers: 3, stale: 0)
              path = File.join FIXTURE_DIR, "#{scenario_file scenario}.json"
              payload = JSON.parse File.read path
              customize! payload, workers: workers, stale: stale
              payload
            end

            private

            def scenario_file(scenario)
              case scenario
              when "mixed" then "mixed-cluster"
              when "stale" then "stale-worker"
              when "truncated" then "truncated-paths"
              when "custom" then "mixed-cluster"
              else scenario
              end
            end

            def customize!(payload, workers:, stale:)
              payload["meta"]["gem_version"] = Stats::VERSION
              payload["meta"]["collected_at"] = Time.now.utc.iso8601
              list = payload["workers"].first workers
              payload["workers"] = list
              payload["summary"]["workers_total"] = list.size
              payload["summary"]["workers_reporting"] = [list.size - stale, 0].max
              payload["summary"]["workers_stale"] = stale
            end
          end
        end
      end
    end
  end
end
