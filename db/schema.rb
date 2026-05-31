# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_31_100001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "credit_packs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "credits", null: false
    t.string "currency", default: "usd", null: false
    t.string "name", null: false
    t.integer "price_cents", null: false
    t.string "stripe_price_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_price_id"], name: "index_credit_packs_on_stripe_price_id", unique: true
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.integer "kind", null: false
    t.bigint "reference_id"
    t.string "reference_type"
    t.integer "state", default: 0, null: false
    t.string "stripe_session_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["reference_type", "reference_id"], name: "index_credit_transactions_on_reference_type_and_reference_id"
    t.index ["stripe_session_id"], name: "index_credit_transactions_on_stripe_session_id", unique: true, where: "(stripe_session_id IS NOT NULL)"
    t.index ["user_id", "state"], name: "index_credit_transactions_on_user_id_and_state"
    t.index ["user_id"], name: "index_credit_transactions_on_user_id"
  end

  create_table "exports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_message"
    t.bigint "file_size"
    t.string "format", null: false
    t.bigint "manual_id", null: false
    t.integer "status", default: 0, null: false
    t.string "storage_key"
    t.datetime "updated_at", null: false
    t.index ["manual_id", "format"], name: "index_exports_on_manual_id_and_format"
    t.index ["manual_id"], name: "index_exports_on_manual_id"
  end

  create_table "frames", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "height"
    t.bigint "recording_id", null: false
    t.integer "source", default: 0, null: false
    t.string "storage_key", null: false
    t.string "thumbnail_storage_key"
    t.integer "timestamp_ms", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["recording_id", "timestamp_ms"], name: "index_frames_on_recording_id_and_timestamp_ms", unique: true
    t.index ["recording_id"], name: "index_frames_on_recording_id"
  end

  create_table "manual_steps", force: :cascade do |t|
    t.text "body_markdown"
    t.datetime "created_at", null: false
    t.bigint "frame_id"
    t.bigint "manual_id", null: false
    t.integer "position", null: false
    t.integer "source_end_ms"
    t.integer "source_start_ms"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["frame_id"], name: "index_manual_steps_on_frame_id"
    t.index ["manual_id", "position"], name: "index_manual_steps_on_manual_id_and_position"
    t.index ["manual_id"], name: "index_manual_steps_on_manual_id"
  end

  create_table "manuals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "generated_at"
    t.integer "input_tokens"
    t.string "model"
    t.integer "output_tokens"
    t.bigint "recording_id", null: false
    t.integer "status", default: 0, null: false
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["recording_id"], name: "index_manuals_on_recording_id", unique: true
  end

  create_table "recordings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "duration_seconds"
    t.jsonb "edit_segments"
    t.string "edited_storage_key"
    t.string "error_message"
    t.integer "failed_stage"
    t.string "mime"
    t.datetime "raw_video_purged_at"
    t.float "scene_threshold", default: 0.4, null: false
    t.integer "status", default: 0, null: false
    t.string "storage_key"
    t.string "tus_upload_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tus_upload_id"], name: "index_recordings_on_tus_upload_id", unique: true, where: "(tus_upload_id IS NOT NULL)"
    t.index ["user_id", "status"], name: "index_recordings_on_user_id_and_status"
    t.index ["user_id"], name: "index_recordings_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "stripe_events", id: :string, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.string "type", null: false
    t.datetime "updated_at", null: false
  end

  create_table "transcript_segments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "end_ms", null: false
    t.integer "position", null: false
    t.integer "start_ms", null: false
    t.text "text", default: "", null: false
    t.bigint "transcript_id", null: false
    t.datetime "updated_at", null: false
    t.index ["transcript_id", "position"], name: "index_transcript_segments_on_transcript_id_and_position", unique: true
    t.index ["transcript_id"], name: "index_transcript_segments_on_transcript_id"
  end

  create_table "transcripts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "full_text"
    t.string "language"
    t.string "provider"
    t.jsonb "raw_payload", default: {}, null: false
    t.bigint "recording_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id"], name: "index_transcripts_on_recording_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "stripe_customer_id"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
  end

  add_foreign_key "credit_transactions", "users"
  add_foreign_key "exports", "manuals"
  add_foreign_key "frames", "recordings"
  add_foreign_key "manual_steps", "frames"
  add_foreign_key "manual_steps", "manuals"
  add_foreign_key "manuals", "recordings"
  add_foreign_key "recordings", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "transcript_segments", "transcripts"
  add_foreign_key "transcripts", "recordings"
end
