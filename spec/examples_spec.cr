require "./spec_helper"

describe "examples" do
  examples = {
    "channel_receive"     => "receive stopped: client disconnected\n",
    "cooperative_worker"  => "worker stopped after 2 jobs: shutdown requested\n",
    "sandbox_interpreter" => "sandbox stopped: context deadline exceeded; accumulator=110\n",
    "timeout_loop"        => "context deadline exceeded\n",
  }

  examples.each do |name, expected_output|
    it "runs #{name}" do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(
        crystal_binary,
        ["run", "--error-on-warnings", "examples/#{name}.cr"],
        output: stdout,
        error: stderr,
        env: crystal_env
      )

      status.exit_code.should eq(0), stderr.to_s
      stdout.to_s.should eq(expected_output)
      stderr.to_s.should be_empty
    end
  end
end

private def crystal_binary : String
  ENV["CRYSTAL"]? || "crystal"
end

private def crystal_env : Hash(String, String)
  env = ENV.to_h
  env["CRYSTAL_CACHE_DIR"] ||= ".crystal_cache"
  env
end
