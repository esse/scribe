module Authentication
  extend ActiveSupport::Concern

  # Local-first: there is no login. Every request is served as the single
  # implicit local user. This shim keeps the old controller/view surface
  # (`Current.user`, `authenticated?`) working without any accounts or sessions.
  included do
    before_action :set_current_user
    helper_method :authenticated?
  end

  class_methods do
    # No-op kept for source compatibility: there is no authentication to skip in
    # the local-first build, so endpoints that used to opt out just inherit the
    # (now trivial) behaviour.
    def allow_unauthenticated_access(**); end
  end

  private

  def set_current_user
    Current.user
  end

  def authenticated?
    true
  end
end
