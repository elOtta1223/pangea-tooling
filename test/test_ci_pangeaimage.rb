require_relative '../ci-tooling/test/lib/testcase'
require_relative '../lib/ci/pangeaimage'

class PangeaImageTest < TestCase
  def setup
    @oldnamespace = CI::PangeaImage.namespace
    @namespace = 'pangea-testing'
    CI::PangeaImage.namespace = @namespace
  end

  def teardown
    CI::PangeaImage.namespace = @oldnamespace
  end

  def assert_image(flavor, series, image)
    assert_equal("#{@namespace}/#{flavor}:#{series}", image.to_s)
    assert_equal("#{@namespace}/#{flavor}", image.repo)
    assert_equal("#{flavor}", image.flavor)
    assert_equal(series, image.tag)
  end

  def test_name
    flavor = 'ubuntu'
    series = 'wily'
    i = CI::PangeaImage.new(flavor, series)
    assert_image(flavor, series, i)
  end

  def test_to_str
    # Coercion into string
    assert_nothing_raised TypeError do
      '' + CI::PangeaImage.new('flavor', 'series')
    end
  end

  def test_symbol_flavor
    flavor = :ubuntu
    series = 'wily'
    image = CI::PangeaImage.new(flavor, series)
    # Do not use assert_image here as we need to verify coercion from
    # :ubuntu to 'ubuntu' works as expected.
    # assert_image in fact relies on it.
    assert_equal("#{@namespace}/ubuntu:wily", image.to_s)
  end

  def test_tag_args
    flavor = :ubuntu
    series = 'wily'
    image = CI::PangeaImage.new(flavor, series)
    tag_args = image.tag_args
    assert_equal({ repo: "#{@namespace}/#{flavor}", tag: series },
                 tag_args)
    # Merge doesn't break it
    assert_equal({ repo: "#{@namespace}/#{flavor}", tag: series, force: true },
                 tag_args.merge(force: true))
  end
end
