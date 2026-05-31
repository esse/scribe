class Current < ActiveSupport::CurrentAttributes
  # Local-first: a single implicit user. `Current.user` resolves to it lazily so
  # controllers, jobs, and the CLI all share the same owner without any login.
  attribute :user

  def user
    super || (self.user = User.local)
  end
end
