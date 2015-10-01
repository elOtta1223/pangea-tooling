#!/usr/bin/env ruby

require 'docker'
require 'logger'
require 'logger/colors'

require_relative '../ci-tooling/lib/dpkg'
require_relative '../ci-tooling/lib/kci'
require_relative '../ci-tooling/lib/dci'
require_relative '../lib/ci/container'
require_relative '../lib/ci/pangeaimage'

Docker.options[:read_timeout] = 3 * 60 * 60 # 3 hours.

$stdout = $stderr

def create_container(flavor, version)
  base = CI::PangeaImage.new(flavor, version)

  @log = Logger.new(STDERR)

  Thread.new do
    Docker::Event.stream { |event| @log.debug event } unless ENV['TESTING']
  end

  # create base
  upgrades = [] # [0] from [1] to. iff upgrade is necessary
  unless Docker::Image.exist?(base.to_s)
    base_image = "#{flavor}:#{version}"
    base_image = "armbuild/#{flavor}:#{version}" if DPKG::HOST_ARCH == 'armhf'
    begin
      @log.info "creating base docker image from #{base_image} for #{base}"
      image = Docker::Image.create(fromImage: base_image)
    rescue Docker::Error::ArgumentError
      error = "Failed to create Image from #{base_image}"
      raise error if version != 'wily' || !upgrades.empty?
      puts error
      puts 'Trying again with vivid and an upgrade...'
      base_image = base_image.gsub(version, 'vivid')
      upgrades << 'vivid' << 'wily'
      retry
    end
    image.tag(repo: base.repo, tag: base.tag)
  end

  # Take the latest image which either is the previous latest or a completely
  # prestine fork of the base ubuntu image and deploy into it.
  # FIXME use containment here probably
  @log.info "creating container from #{base}"
  cmd = ['sh', '/tooling-pending/deploy_in_container.sh']
  unless upgrades.empty?
    cmd = ['sh', '/tooling-pending/deploy_upgrade_container.sh'] + upgrades
  end
  c = CI::Container.create(Image: base.to_s,
                           WorkingDir: ENV.fetch('HOME'),
                           Cmd: cmd)
  unless ENV.fetch('TESTING', false)
    # :nocov:
    @log.info 'creating debug thread'
    Thread.new do
      c.attach do |_stream, chunk|
        puts chunk
        STDOUT.flush
      end
    end
    # :nocov:
  end
  @log.info "starting container from #{base}"
  c.start(Binds: ["#{Dir.home}/tooling-pending:/tooling-pending"])
  ret = c.wait
  status_code = ret.fetch('StatusCode', 1)
  fail "Bad return #{ret}" if status_code != 0
  c.stop!

  # Flatten the image by piping a tar export into a tar import.
  # Flattening essentially destroys the history of the image. By default docker
  # will however stack image revisions ontop of one another. Namely if we have
  # abc and create a new image edf, edf will be an AUFS ontop of abc. While this
  # is probably useful if one doesn't commit containers repeatedly for us this
  # is pretty crap as we have massive turn around on images.
  @log.warn 'Flattening latest image by exporting and importing it.' \
            ' This can take a while.'
  require 'thwait'

  rd, wr = IO.pipe
  @i = nil

  Thread.abort_on_exception = true
  read_thread = Thread.new do
    @i = Docker::Image.import_stream do
      rd.read(1000).to_s
    end
    @log.warn 'Import complete'
    rd.close
  end
  write_thread = Thread.new do
    c.export do |chunk|
      wr.write(chunk)
    end
    @log.warn 'Export complete'
    wr.close
  end
  ThreadsWait.all_waits(read_thread, write_thread)

  c.remove
  begin
    @log.info "Deleting old image of #{base}"
    previous_image = Docker::Image.get(base.to_s)
    @log.info previous_image.to_s
    previous_image.delete
  rescue Docker::Error::NotFoundError
    @log.warn 'There is no previous image, must be a new build.'
  rescue Docker::Error::ConflictError
    @log.warn 'Could not remove old latest image, supposedly it is still used'
  end
  @log.info "Tagging #{@i}"
  @i.tag(repo: base.repo, tag: base.tag, force: true)

  # Disabled because we should not be leaking. And this has reentrancy problems
  # where another deployment can cleanup our temporary container/image...
  # cleanup_dangling_things
end

KCI.series.keys.each do |k|
  create_container('ubuntu', k)
end

DCI.series.keys.each do |k|
  create_container('debian', k)
end
