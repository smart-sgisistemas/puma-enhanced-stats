# frozen_string_literal: true

module EnhancedStatsHelpers
  def default_puma_stats(**overrides)
    Puma::Server::STAT_METHODS.to_h { |key| [key, 0] }.merge(overrides)
  end

  def wire_row(index:, pid:, items: [], **puma_overrides)
    {
      index: index,
      pid: pid,
      stats: default_puma_stats(**puma_overrides),
      requests: items
    }
  end

  def enhanced_worker_status_row(index:, pid:, items: [], last_enhanced_checkin: nil,
                                 phase: 0, booted: true, started_at: nil, **puma_overrides)
    {
      index: index,
      pid: pid,
      phase: phase,
      booted: booted,
      started_at: started_at || Time.now.utc.iso8601,
      last_enhanced_checkin: last_enhanced_checkin,
      last_enhanced_status: default_puma_stats(**puma_overrides),
      requests: items
    }
  end

  def empty_enhanced_status
    {
      stats: default_puma_stats,
      requests: []
    }
  end

  def default_cluster_stats(worker_rows:)
    {
      started_at: Time.now.utc.iso8601,
      workers: worker_rows.size,
      phase: 0,
      booted_workers: worker_rows.size,
      old_workers: 0,
      worker_status: worker_rows.map do |row|
        {
          started_at: row[:started_at] || Time.now.utc.iso8601,
          pid: row[:pid],
          index: row[:index],
          phase: row[:phase] || 0,
          booted: row.fetch(:booted, true),
          last_checkin: Time.now.utc.iso8601,
          last_status: default_puma_stats
        }
      end,
      versions: {
        puma: Puma::Const::PUMA_VERSION,
        ruby: {
          engine: RUBY_ENGINE,
          version: RUBY_VERSION,
          patchlevel: RUBY_PATCHLEVEL
        }
      }
    }
  end

  def default_single_stats(**puma_overrides)
    {
      started_at: Time.now.utc.iso8601,
      **default_puma_stats(**puma_overrides),
      versions: {
        puma: Puma::Const::PUMA_VERSION,
        ruby: {
          engine: RUBY_ENGINE,
          version: RUBY_VERSION,
          patchlevel: RUBY_PATCHLEVEL
        }
      }
    }
  end

  def with_inflight_env(env)
    Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = env
    yield
  ensure
    Thread.current[Puma::Enhanced::Stats::Middleware::KEY] = nil
  end

  def wire_line(pid, row)
    "#{pid}\t#{Puma::JSONSerialization.generate(row)}\n"
  end

  def server_double(enhanced_stats: Puma::Enhanced::Stats::Configuration.default, **stats_overrides)
    instance_double(
      Puma::Server,
      options: { enhanced_stats: enhanced_stats },
      stats: default_puma_stats(**stats_overrides)
    )
  end
end

RSpec.configure do |config|
  config.include EnhancedStatsHelpers
end
