Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :admin do
    get    "login",  to: "sessions#new"
    post   "login",  to: "sessions#create"
    delete "logout", to: "sessions#destroy"
  end

  resources :operations, only: [ :index, :show, :create ]
  resource  :logs, only: :show
  resource  :diagnostics, only: :show

  resources :devices, only: :index, param: :request_id do
    member do
      post :approve
      post :reject
    end
  end
  post "pairings/approve" => "pairings#approve", as: :approve_pairing

  resource :config, only: [ :show, :update ], controller: "config"
  resources :config_revisions, only: [ :index, :show ] do
    post :restore, on: :member
  end
  resource :access, only: [ :show, :update ], controller: "access" do
    post :trust_proxy
  end
  post "control_ui" => "control_ui#create", as: :control_ui
  resource :updates, only: :show
  resource :environment, only: [ :show, :update ], controller: "environment"
  resource :console, only: [ :show, :create ], controller: "console"
  resource :setting, only: [ :show, :update ]

  root "dashboard#show"
end
