module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # Local-first: no accounts, so every connection is the single local user.
    def connect
      self.current_user = User.local
    end
  end
end
