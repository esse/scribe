require "tus/server"

Rails.application.routes.draw do
  # --- Auth (SPEC §4) ---
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]

  # --- Recordings / upload (SPEC §7, §13) ---
  resources :recordings, only: %i[index new create show destroy] do
    member do
      post :complete
      post :retry
    end
  end

  # Resumable tus upload endpoint (SPEC §7.2).
  mount Tus::Server => "/files"

  # --- Manuals / review-edit / exports (SPEC §10, §11, §13) ---
  resources :manuals, only: %i[show update] do
    resources :steps, only: %i[update], controller: "manuals/steps"
    scope module: :manuals do
      get "exports/formats", to: "exports#formats"
      resources :exports, only: %i[create]
    end
  end

  resources :exports, only: %i[show]

  # --- Credits / billing (SPEC §12, §13) ---
  get "credits", to: "credits#index"
  get "credits/balance", to: "credits#balance"
  get "credits/packs", to: "credits#packs"
  post "credits/checkout", to: "credits#checkout"
  post "webhooks/stripe", to: "webhooks/stripe#create"

  # --- Signed disk blobs (SPEC §5) ---
  get "storage/blob", to: "storage/blobs#show"

  # Health check for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # Recorder is the landing page once signed in.
  root "recordings#new"
end
