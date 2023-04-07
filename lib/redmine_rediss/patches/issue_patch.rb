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

module RedmineRediss
  module Patches
    module IssuePatch
    
      def self.included(base)
        base.class_eval do
          redi_search do
            text_field :subject, phonetic: "dm:en"
            text_field :description, phonetic: "dm:en"
            # text_field :combined do
            #   "#{subject} #{description}"
            # end
            vector_field :subject_vector, 
              algorithm: "FLAT", 
              count: 10,
              type: "FLOAT32",
              dim: 1536,
              distance_metric: "COSINE",
              initial_cap: 1024,
              block_size: 1024 do
            end
            vector_field :description_vector, 
              algorithm: "FLAT", 
              count: 10,
              type: "FLOAT32",
              dim: 1536,
              distance_metric: "COSINE",
              initial_cap: 1024,
              block_size: 1024 do
            end
          end
          Issue.acts_as_searchable  :columns  =>  ["#{Issue.table_name}.subject", "#{Issue.table_name}.description"],
                                    :preload  =>  [:project, :status, :tracker],
                                    :scope    =>  lambda {|options| options[:open_issues] ? self.open : self.all}
        end
      end

      def self.prepended(base)
        base.send(:prepend, EventMethods)
        class << base
          prepend SearchMethods
        end
      end

      module EventMethods

        def event_description
          desc = Redmine::Search.cache_store.fetch("Issue-#{id}")
          if desc
            Redmine::Search.cache_store.delete("Issue-#{id}")
          else
            desc = description
          end
          desc.force_encoding('UTF-8') if desc
        end

      end

      module SearchMethods

        def search_result_ranks_and_ids(tokens, user = User.current, projects = nil, options = {})
          r = search(tokens, user, projects, options)
          r.map{ |x| [x[0].to_i, x[1]] }
        end

      private

        # self = Issue
        # tokens = ["test"]
        # projects = 
        
        # options = {
        #   :all_words=>true, 
        #   :titles_only=>false, 
        #   :attachments=>"0", 
        #   :open_issues=>false, 
        #   :params=>{
        #     "utf8"=>"✓", 
        #     "scope"=>"", 
        #     "q"=>"test", 
        #     "controller"=>"search", 
        #     "action"=>"index"
        #   }
        # }
        
        # user = Redmine Admin
        # name = Issue

        def search(tokens, user, projects = nil, options = {})
          Rails.logger.info 'Issue::search'
          search_data = SearchData.new(self, tokens, projects, options, user, name)
          Rails.logger.info "search_data = #{search_data}"
          Rails.logger.info "self = #{self}"
          Rails.logger.info "tokens = #{tokens}"
          Rails.logger.info "projects = #{projects}"
          Rails.logger.info "options = #{options}"
          Rails.logger.info "user = #{user}"
          Rails.logger.info "name = #{name}"
          search_results = search_for_issues_rediss(user, search_data)
          unless options[:titles_only]
            Rails.logger.info "Call rediss search service for #{name}"
            rediss_results = RedissSearchService.search(search_data)
            search_results.concat rediss_results unless rediss_results.blank?
            Rails.logger.info "Call rediss search service for #{name} completed"
          end
          search_results
        end

        def search_for_issues_rediss(user, search_data)
          results = []
          # sql = +"#{Project.table_name}.status = ? AND #{Project.allowed_to_condition(user, :view_issues)}"
          # sql << " AND #{search_data.project_conditions}" if search_data.project_conditions
          # Issue
          #   .joins("JOIN #{Project.table_name}  ON #{Issue.table_name}.project_id   = #{Project.table_name}.id")
          #   .where(sql, Project::STATUS_ACTIVE).scoping do
          #     where(tokens_condition(search_data)).scoping do
          #       results = 
          #         where(search_data.limit_options)
          #         .distinct
          #         .pluck(searchable_options[:date_column], :id)
          #     end
          #   end
          results
        end

        def container_url
          if container.is_a? Issue
            issue_path id: container[:id]
          elsif container.is_a? WikiPage
            wiki_path project_id: container.project.identifier, id: container[:title]
          elsif container.is_a? Message
            message_path board_id: container[:board_id], id: container[:id]
          elsif container.is_a? Version
            attachment_path project_id: container[:project_id]
          end
        end

        def container_name
          container_name = +': '
          if container.is_a? Issue
            container_name += container[:subject].to_s
          elsif container.is_a? WikiPage
            container_name += container[:title].to_s
          elsif container.is_a? Message
            container_name += container[:subject].to_s
          elsif container.is_a? Version
            container_name += container[:name].to_s
          end
          container_name
        end

        def search_options(search_data, search_joins_query)
          search_data.find_options.merge joins: search_joins_query
        end

        def tokens_condition(search_data)
          options = search_data.options
          columns = search_data.columns
          tokens = search_data.tokens
          columns = columns[0..0] if options[:titles_only]
          token_clauses = columns.collect {|column| "(LOWER(#{column}) LIKE ?)"}
          sql = (['(' + token_clauses.join(' OR ') + ')'] * tokens.size).join(options[:all_words] ? ' AND ' : ' OR ')
          [sql, * (tokens.collect {|w| "%#{w.downcase}%"} * token_clauses.size).sort]
        end

      end

    end
  end
end

Issue.send :include, RedmineRediss::Patches::IssuePatch
Issue.send :prepend, RedmineRediss::Patches::IssuePatch
