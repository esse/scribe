require "test_helper"

# Real STT providers (SPEC §2, §9.3). The network call (#fetch) is exercised live
# only against the real APIs; here we test provider selection, the response
# mapping each provider applies (offline, against canned payloads), and the
# missing-key guard.
class TranscriptionTest < ActiveSupport::TestCase
  # --- provider selection ---------------------------------------------------
  test "build selects the configured provider" do
    assert_instance_of Transcription::Deepgram, Transcription::Base.build("deepgram")
    assert_instance_of Transcription::Openai, Transcription::Base.build("openai")
    assert_instance_of Transcription::Whisper, Transcription::Base.build("whisper")
    assert_instance_of Transcription::Stub, Transcription::Base.build("stub")
  end

  test "an unknown provider is a hard error, not a silent stub" do
    assert_raises(Transcription::ConfigurationError) { Transcription::Base.build("does-not-exist") }
  end

  # --- missing credentials --------------------------------------------------
  test "hosted providers raise ConfigurationError without a key" do
    assert_raises(Transcription::ConfigurationError) do
      Transcription::Deepgram.new(api_key: nil).transcribe(audio_path: "/tmp/x.flac")
    end
    assert_raises(Transcription::ConfigurationError) do
      Transcription::Openai.new(api_key: nil).transcribe(audio_path: "/tmp/x.flac")
    end
  end

  # --- Deepgram response mapping --------------------------------------------
  test "deepgram maps utterances to timestamped segments" do
    payload = {
      "results" => {
        "channels" => [ { "detected_language" => "en", "alternatives" => [ { "transcript" => "hello world" } ] } ],
        "utterances" => [
          { "start" => 0.0, "end" => 1.5, "transcript" => "hello" },
          { "start" => 1.5, "end" => 3.0, "transcript" => "world" }
        ]
      }
    }
    result = Transcription::Deepgram.new(api_key: "k").parse(payload)

    assert_equal "en", result[:language]
    assert_equal 2, result[:segments].size
    assert_equal({ start_ms: 0, end_ms: 1500, text: "hello" }, result[:segments].first)
    assert_equal 3000, result[:segments].last[:end_ms]
  end

  test "deepgram falls back to a single segment from words" do
    payload = {
      "results" => {
        "channels" => [ {
          "alternatives" => [ {
            "transcript" => "just one line",
            "words" => [ { "start" => 0.2 }, { "end" => 2.4 } ]
          } ]
        } ]
      }
    }
    result = Transcription::Deepgram.new(api_key: "k").parse(payload)

    assert_equal 1, result[:segments].size
    assert_equal 200, result[:segments].first[:start_ms]
    assert_equal 2400, result[:segments].first[:end_ms]
    assert_equal "just one line", result[:full_text]
  end

  # --- OpenAI response mapping ----------------------------------------------
  test "openai maps verbose_json segments" do
    payload = {
      "language" => "english",
      "text" => "step one step two",
      "duration" => 4.0,
      "segments" => [
        { "start" => 0.0, "end" => 2.0, "text" => " step one" },
        { "start" => 2.0, "end" => 4.0, "text" => " step two" }
      ]
    }
    result = Transcription::Openai.new(api_key: "k").parse(payload)

    assert_equal 2, result[:segments].size
    assert_equal({ start_ms: 0, end_ms: 2000, text: "step one" }, result[:segments].first)
    assert_equal "step one step two", result[:full_text]
  end

  test "openai falls back to one segment when only text is returned" do
    payload = { "text" => "no segments here", "duration" => 5.0 }
    result = Transcription::Openai.new(api_key: "k").parse(payload)

    assert_equal 1, result[:segments].size
    assert_equal 5000, result[:segments].first[:end_ms]
    assert_equal "no segments here", result[:segments].first[:text]
  end

  # --- transcribe wires fetch → parse ---------------------------------------
  test "transcribe maps a provider response end to end" do
    provider = Transcription::Openai.new(api_key: "k")
    canned = { "text" => "hi", "duration" => 1.0, "segments" => [ { "start" => 0, "end" => 1, "text" => "hi" } ] }
    provider.define_singleton_method(:fetch) { |_audio| canned }

    result = provider.transcribe(audio_path: "/tmp/whatever.flac")
    assert_equal "hi", result[:full_text]
    assert_equal 1, result[:segments].size
  end
end
