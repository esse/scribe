require "tus/server"

Rails.application.routes.draw do
  # --- Recordings / upload (SPEC §7, §13) ---
  resources :recordings, only: %i[index new create show destroy] do
    member do
      post :complete
      get :edit
      get :source_url
      post :apply_edits
      post :retry
    end
    collection do
      # "Use an existing recording" — upload a video file you already have.
      post :upload
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

  # --- Signed disk blobs (SPEC §5) ---
  get "storage/blob", to: "storage/blobs#show"

  # Health check for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # The recorder is the landing page.
  root "recordings#new"
end
