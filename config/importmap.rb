# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# Resumable uploads in the browser (SPEC §7.2).
pin "tus-js-client", to: "https://ga.jspm.io/npm:tus-js-client@4.1.0/lib.es5/browser/index.js"
pin_all_from "app/javascript/controllers", under: "controllers"
