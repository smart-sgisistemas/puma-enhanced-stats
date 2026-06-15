# frozen_string_literal: true

Rails.application.routes.draw do
  get "/slow", to: "slow#slow"
  root to: "slow#index"
end
