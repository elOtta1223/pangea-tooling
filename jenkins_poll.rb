#!/usr/bin/env ruby

require 'date'
require 'logger'
require 'logger/colors'
require 'optparse'

require_relative 'ci-tooling/lib/jenkins'
require_relative 'ci-tooling/lib/thread_pool'
require_relative 'ci-tooling/lib/retry'

QUALIFIER_STATES = %w(success unstable)

OptionParser.new do |opts|
  opts.banner = <<-EOS
Usage: jenkins_poll.rb 'regex'

regex must be a valid Ruby regular expression matching the jobs you wish to
retry.

e.g.
  • All build jobs for vivid and utopic:
    '^(vivid|utopic)_.*_.*'

  • All unstable builds:
    '^.*_unstable_.*'

  • All jobs:
    '.*'
  EOS
end.parse!

@log = Logger.new(STDOUT).tap do |l|
  l.progname = 'poll'
  l.level = Logger::INFO
end

fail 'Need ruby pattern as argv0' if ARGV.empty?
pattern = Regexp.new(ARGV[0])
@log.info pattern

job_name_queue = Queue.new
job_names = Jenkins.job.list_all
job_names.each do |name|
  next unless pattern.match(name)
  job_name_queue << name
end

module Jenkins
  class Job
    class BuildDetails < OpenStruct
      def date
        @date ||= Date.parse(Time.at(timestamp / 1000).to_s)
      end
    end

    attr_reader :name

    def initialize(name)
      @name = name
    end

    def build
      BuildDetails.new(Jenkins.job.get_build_details(@name, 0))
    end

    def queued?
      Jenkins.client.queue.list.include?(@name)
    end

    private

    def method_missing(name, *args, &block)
      args.unshift(@name)
      Jenkins.job.send(name.to_sym, *args, &block)
    end
  end
end

BlockingThreadPool.run do
  until job_name_queue.empty?
    name = job_name_queue.pop(true)
    job = Jenkins::Job.new(name)
    next if job.queued?
    Retry.retry_it(times: 5) do
      if (Date.today - job.build.date) > 3
        @log.warn "  #{name} --> poll"
        job.poll
      end
    end
  end
end
