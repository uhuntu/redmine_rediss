# encoding: utf-8
# frozen_string_literal: true
#
# Redmine Rediss is a Redmine plugin to allow attachments searches by content.
#
# Copyright © 2010    Xabier Elkano
# Copyright © 2015-22 Karel Pičman <karel.picman@kontron.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'redmine'
require File.dirname(__FILE__) + '/lib/redmine_rediss'

Redmine::Plugin.register :redmine_rediss do
  name 'Rediss search plugin'
  author 'Hunt Redmine'
  url 'https://www.redmine.org/plugins/rediss_search'
  author_url 'https://github.com/uhuntu/redmine_rediss/graphs/contributors'

  description 'With this plugin you will be able to do searches by file name and by strings inside your documents'
  version '3.0.2'
  requires_redmine version_or_higher: '4.1.0'

  settings partial: 'settings/redmine_rediss_settings',
    default: {
      'enable' => true,
      'index_database' => File.expand_path('file_index', Rails.root),
      'stemming_lang' => 'english',
      'stemming_strategy' => 'STEM_SOME',
      'stem_langs' =>  %w(danish dutch english finnish french german german2 hungarian italian kraaij_pohlmann
        lovins norwegian porter portuguese romanian russian spanish swedish turkish),
      'save_search_scope' => false,
      'enable_cjk_ngrams' => false
    }
end

Redmine::Search.map do |search|
  search.register :attachments
  search.register :repofiles
  search.register :issues
end

RediSearch.configure do |config|
  config.redis_config = {
    host: "127.0.0.1",
    port: "6379"
  }
end