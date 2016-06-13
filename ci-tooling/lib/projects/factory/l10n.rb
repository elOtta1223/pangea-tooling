# frozen_string_literal: true
#
# Copyright (C) 2016 Rohan Garg <rohan@garg.io>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

require_relative 'base'
require 'net/sftp'

class ProjectsFactory
  # Debian specific project factory.
  class KDEL10N < Base
    DEFAULT_URL_BASE = 'git://git.launchpad.net/~kubuntu-packagers/kubuntu-packaging/+git/kde-l10n-common'.freeze

    # FIXME: same as in neon
    def self.url_base
      @url_base ||= DEFAULT_URL_BASE
    end

    def self.understand?(type)
      type == 'kde-l10n'
    end

    private

    def params(str)
      name = str.split('/')[-1]
      default_params.merge(
        name: name,
        component: 'kde-l10n',
        url_base: self.class.url_base
      )
    end

    # FIXME: test needs to check that we get the correct url out
    # FIXME: same as in neon
    def from_string(str, params = {})
      kwords = params(str)
      kwords.merge!(symbolize(params))
      puts "new_project(#{kwords})"
      new_project(**kwords)
    rescue Project::GitTransactionError, RuntimeError => e
      p e
      nil
    end

    # FIXME: same as in neon
    def split_hash(hash)
      clean_hash(*hash.first)
    end

    # FIXME: NOT same as in neon, pattern is different!
    def clean_hash(base, subset)
      subset.collect! do |sub|
        # Coerce flat strings into hash. This makes handling more consistent
        # further down the line. Flat strings simply have empty properties {}.
        sub = sub.is_a?(Hash) ? sub : { sub => {} }
        # Convert the subset into a pattern matching set by converting the
        # keys into suitable patterns.
        key = sub.keys[0]
        sub[CI::FNMatchPattern.new(key.to_s)] = sub.delete(key)
        sub
      end
      [base, subset]
    end

    # FIXME: same as in neon
    def each_pattern_value(subset)
      subset.each do |sub|
        pattern = sub.keys[0]
        value = sub.values[0]
        yield pattern, value
      end
    end

    # FIXME: NOT same as in neon path is not final path but just the name
    def match_path_to_subsets(base, name, subset)
      matches = {}
      each_pattern_value(subset) do |pattern, value|
        next unless pattern.match?(name)
        match = ["#{base}/#{name}", value]
        matches[pattern] = match
      end
      matches
    end

    def from_hash(hash)
      base, subset = split_hash(hash)
      raise 'not array' unless subset.is_a?(Array)

      selection = self.class.ls(base).collect do |name|
        matches = match_path_to_subsets(base, name, subset)
        # Get best matching pattern.
        CI::PatternBase.sort_hash(matches).values[0]
      end
      selection.compact.collect { |s| from_string(*s) }
    end

    class << self
      def ls(base)
        @list_cache ||= {}
        return @list_cache[base] if @list_cache.key?(base)
        @list_cache[base] = check_ftp(base).freeze
      end

      private

      def check_ftp(base)
        stable_path = "/home/ftpubuntu/stable/applications/#{base}/src/kde-l10n/"
                      .freeze
        unstable_path = "/home/ftpubuntu/unstable/applications/#{base}/src/kde-l10n/"
                        .freeze
        output = nil
        Net::SFTP.start('depot.kde.org', 'ftpubuntu') do |sftp|
          output = sftp.dir.glob(stable_path, '**/**.tar.*').map(&:name)
          output ||= sftp.dir.glob(unstable_path, '**/**.tar.*').map(&:name)
        end
        cleanup_ls(output, base)
      end

      def cleanup_ls(data, str)
        pattern = "(kde-l10n-.*)-#{str}".freeze
        data.collect do |entry|
          entry.match(/#{pattern}/)[1] if entry =~ /#{pattern}/
        end
      end
    end
  end
end
