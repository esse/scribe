module SessionTestHelper
  # Local-first: there is no authentication. These remain as no-ops so existing
  # tests read clearly; every request is served as the single local user.
  def sign_in_as(_user = nil)
    Current.user = User.local
  end

  def sign_out
    Current.user = nil
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
