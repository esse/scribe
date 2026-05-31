require "test_helper"
require "aws-sdk-s3"

# S3/MinIO storage adapter (SPEC §4, §5). Live MinIO is exercised via
# docker-compose locally; here we use the AWS SDK's response stubbing to verify
# the adapter wires the right calls and produces a MinIO-style presigned URL —
# all offline, so it runs in CI.
class StorageS3Test < ActiveSupport::TestCase
  def build(stub_overrides = {})
    client = Aws::S3::Client.new(
      stub_responses: true,
      region: "us-east-1",
      access_key_id: "minioadmin",
      secret_access_key: "minioadmin",
      endpoint: "http://localhost:9000",
      force_path_style: true
    )
    stub_overrides.each { |op, resp| client.stub_responses(op, resp) }
    [ Storage::S3Adapter.new(client:, bucket: "scribe"), client ]
  end

  test "put / get / exists / delete round-trip through the S3 client" do
    adapter, _ = build(get_object: { body: "frame-bytes" }, head_object: {})

    assert_equal "frames/1.png", adapter.put("frames/1.png", StringIO.new("frame-bytes"), content_type: "image/png")
    assert_equal "frame-bytes", adapter.get("frames/1.png")
    assert adapter.exists?("frames/1.png")
    adapter.delete("frames/1.png") # no raise
  end

  test "exists? is false when the object is missing" do
    adapter, _ = build(head_object: "NotFound")
    refute adapter.exists?("missing.png")
  end

  test "signed_url presigns a MinIO-style URL with the key and expiry" do
    adapter, _ = build
    url = adapter.signed_url("exports/5/manual.pdf", expires_in: 600, disposition: "attachment", filename: "manual.pdf")

    assert_includes url, "http://localhost:9000/scribe/exports/5/manual.pdf"
    assert_includes url, "X-Amz-Expires=600"
    assert_includes url, "X-Amz-Signature="
    assert_includes url, "response-content-disposition"
  end

  test "put sets server-side encryption only when S3_SSE is configured" do
    captured = nil
    adapter, client = build
    client.stub_responses(:put_object, lambda { |ctx| captured = ctx.params; {} })

    with_sse("") { adapter.put("k.png", StringIO.new("x"), content_type: "image/png") }
    refute captured.key?(:server_side_encryption), "MinIO dev: no SSE header"

    with_sse("AES256") { adapter.put("k.png", StringIO.new("x"), content_type: "image/png") }
    assert_equal "AES256", captured[:server_side_encryption], "real S3/R2: encrypt at rest"
  end

  private

  def with_sse(value)
    original = Scribe.config.s3_sse
    Scribe.config.s3_sse = value
    yield
  ensure
    Scribe.config.s3_sse = original
  end
end
