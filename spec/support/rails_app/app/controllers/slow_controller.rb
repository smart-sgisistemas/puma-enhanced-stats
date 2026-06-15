# frozen_string_literal: true

class SlowController < ApplicationController
  def index
    render plain: "ok"
  end

  def slow
    sleep RailsTestApp.slow_sleep
    render plain: "slow"
  end
end
