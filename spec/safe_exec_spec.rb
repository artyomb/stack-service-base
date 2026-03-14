require 'open3'
require 'rbconfig'

RSpec.describe 'SafeExec self-test' do
  let(:safe_exec_file) { File.expand_path('../lib/stack-service-base/safe_exec.rb', __dir__) }

  it 'runs successfully when executed directly' do
    stdout, stderr, status = Open3.capture3({ 'RUBYOPT' => nil }, RbConfig.ruby, safe_exec_file)

    aggregate_failures do
      expect(status.success?).to be(true), -> { "stderr: #{stderr}\nstdout: #{stdout}" }
      expect(stderr).to eq('')
      expect(stdout).to include('[self-test] capture with streaming')
      expect(stdout).to include('success?: true')
      expect(stdout).to include('stdout: "out\n"')
      expect(stdout).to include('stderr: "err\n"')
      expect(stdout).to include('[self-test] capture! exit error')
      expect(stdout).to include('exit_error: Command failed: bash -lc echo boom >&2; exit 7 with exit status 7')
      expect(stdout).to include('stderr: "boom\n"')
      expect(stdout).to include('[self-test] call data result')
      expect(stdout).to include('data: {ok: true, items: [1, 2, 3]}')
      expect(stdout).to include('[self-test] call timeout')
      expect(stdout).to match(/timeout: (SafeExec::TimeoutError|Timeout::Error): Timed out after 1s/)
    end
  end
end
