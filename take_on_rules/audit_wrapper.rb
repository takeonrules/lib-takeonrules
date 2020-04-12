# Responsible for wrapping the logic for audit logging and audit violations
class AuditWrapper
  def self.run(*args, &block)
    new(*args).run(&block)
  end

  attr_reader :there_were_errors, :exit_on_failure, :task, :depth
  def initialize(task, args)
    @task = task
    @exit_on_failure = args.fetch(:exit_on_failure, false)
    @depth = args.fetch(:depth, 0)
    @there_were_errors = false
  end

  def there_were_errors!(message: nil)
    padding = "\t" * (depth + 1)
    $stderr.puts("#{padding}#{message}") if message
    @there_were_errors = true
  end

  def there_are_warnings!(message:)
    padding = "\t" * (depth + 1)
    $stderr.puts("#{padding}#{message}") if message
  end

  def run
    padding = "\t" * depth
    $stdout.puts %(#{padding}STARTING: "#{task}" task)
    yield(self)
    if there_were_errors && exit_on_failure
      $stderr.puts %(#{padding}\tERROR: "#{task}" task failed, please review STDERR)
      exit!(1)
    else
      $stdout.puts %(#{padding}SUCCESS: "#{task}" task)
    end
  end
  def invoke(task)
    Rake::Task[task].invoke(exit_on_failure, depth+1)
  end
end
