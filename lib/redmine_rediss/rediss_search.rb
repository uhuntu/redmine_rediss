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

require 'uri'

module RedmineRediss
  include ContainerTypeHelper
  module RedissSearch

    def rediss_search(tokens, limit_options, projects_to_search, all_words, user, rediss_file)
      Rails.logger.info 'RedissSearch::rediss_search'
      xpattachments = []
      return nil unless Setting.plugin_redmine_rediss['enable']
      Rails.logger.info "Global settings dump #{Setting.plugin_redmine_rediss.inspect}"
      stemming_lang = Setting.plugin_redmine_rediss['stemming_lang'].rstrip
      Rails.logger.info "stemming_lang: #{stemming_lang}"
      stemming_strategy = Setting.plugin_redmine_rediss['stemming_strategy'].rstrip
      Rails.logger.info "stemming_strategy: #{stemming_strategy}"
      databasepath = get_database_path(rediss_file)
      Rails.logger.info "databasepath: #{databasepath}"

      begin
        if rediss_file != 'Issue'
          return nil
        end
        # Issue.reindex
        # database = Rediss::Database.new(databasepath)
      rescue => e
        Rails.logger.error "Can't open Rediss database #{databasepath} - #{e.inspect}"
        return nil
      end

      # # Start an index session.
      # issue_index = Issue.search_index
      # Rails.logger.info "issue_index: #{issue_index.name}"

      # Combine the rest of the command line arguments with spaces between
      # them, so that simple queries don't have to be quoted at the shell
      # level.
      query_string = tokens.map{ |x| !(x[-1,1].eql?'*')? x+'': x }.join(' ')
      # Parse the query string to produce a Rediss::Query object.
      # qp = Rediss::QueryParser.new
      # stemmer = Rediss::Stem.new(stemming_lang)
      # qp.stemmer = stemmer
      # qp.database = database
      # case stemming_strategy
      #   when 'STEM_NONE'
      #     qp.stemming_strategy = Rediss::QueryParser::STEM_NONE
      #   when 'STEM_SOME'
      #     qp.stemming_strategy = Rediss::QueryParser::STEM_SOME
      #   when 'STEM_ALL'
      #     qp.stemming_strategy = Rediss::QueryParser::STEM_ALL
      # end
      # if all_words
      #   qp.default_op = Rediss::Query::OP_AND
      # else
      #   qp.default_op = Rediss::Query::OP_OR
      # end

      # flags = Rediss::QueryParser::FLAG_WILDCARD
      # flags |= Rediss::QueryParser::FLAG_CJK_NGRAM if Setting.plugin_redmine_rediss['enable_cjk_ngrams']
      # query = qp.parse_query(query_string, flags)
      Rails.logger.info "query_string is: #{query_string}"
      # Rails.logger.info "Parsed query is: #{query.description}"

      # Find the top 1000 results for the query.
      # enquire.query = query
      # matchset = enquire.mset(0, 1000)

#####################################################################

      OpenAI.configure do |config|
        config.access_token = ENV.fetch('OPENAI_ACCESS_TOKEN')
        config.http_proxy = ENV.fetch('http_proxy')
      end
      client = OpenAI::Client.new
    
      puts "Getting query_embedding..."
      query_embed = client.embeddings(
        parameters: {
          model: "text-embedding-ada-002",
          input: query_string
        }
      )
  
      query_data = query_embed.parsed_response["data"]
      query_embedding = query_data[0]["embedding"] if !query_data.nil?
  
      if query_data.nil?
        puts "query_data is nil"
        puts query_embed["error"]
        puts query_string.nil?
        abort
      end
  
      query_pack = query_embedding.pack("F*") if !query_embedding.nil?
      return nil if query_pack.nil?
  
      # Start an index session.
      puts "Rediss Search"
      issue_index = Issue.search_index

      if issue_index.nil?
        Rails.logger.info "issue_index is not existed"
        return nil
      end

      Rails.logger.info "issue_index: #{issue_index.name}"
  
      index_search = issue_index
        .search("*=>[KNN 10 @subject_vector $vector AS vector_score]")
        .return(:subject, :description, :vector_score)
        .sort_by(:subject)
        .limit(10)
        .dialect(2)
  
      index_search = index_search
        .params(:vector, query_pack) if !query_pack.nil?
  
      # index_results = index_search.results
      # index_inspect = index_results.inspect
      # puts index_results.pluck(:subject, :description)

#####################################################################

      searchset = index_search
      Rails.logger.info "issue_results is: #{searchset.results.inspect}"
      
      return nil if searchset.nil?

      # Display the results.
      Rails.logger.info "Results 1-#{searchset.results.count} records:"
      Rails.logger.info "Searching for #{rediss_file}"
      i = 0
      p = URI::Parser.new

      searchset.results.each do |s|
        if rediss_file == 'Repofile'
          if m.document.data =~ /^date=(.+)\W+sample=(.+)\W+url=(.+)\W/
            dochash = { date: $1, sample: $2, url: p.unescape($3) }
            repo_file = process_repo_file(projects_to_search, dochash, user, i)
            if repo_file
              xpattachments << repo_file
              i = i + 1
            end
          else
            Rails.logger.error "Wrong format of document data: #{m.document.data}"
          end
        elsif rediss_file == 'Attachment'
          if m.document.data =~ /^url=(.+)\W+sample=(.+)\W+(author|type|caption|modtime|size)=/
            dochash = { url: p.unescape($1), sample: $2 }
            attachment = process_attachment(projects_to_search, dochash, user)
            if attachment
              xpattachments << attachment
            end
          else
            Rails.logger.error "Wrong format of document data: #{m.document.data}"
          end
        elsif rediss_file == 'Issue'
          Rails.logger.info "s = #{s[:id]}"
          dochash = { id: s[:id], sample: s[:description] }
          issue = process_issue(projects_to_search, dochash, user)
          if issue
            xpattachments << issue
          end
        end
      end

      Rails.logger.info 'Rediss searched'

      xpattachments.map{ |a| [a.created_on, a.id] }

    end

  private

    def process_issue(projects, dochash, user)
      issue = Issue.where(id: dochash[:id]).first
      if issue
        Rails.logger.info "Issue created on #{issue.created_on}"
        Rails.logger.info "Issue's project #{issue.project}"
        Rails.logger.info "Issue's docattach not nil..:  #{issue}"
        Rails.logger.info 'Adding issue'
        project = issue.project
        allowed = user.allowed_to?(:view_issues, project)
        projects = [] << projects if projects.is_a?(Project)
        project_ids = projects.collect(&:id) if projects
        if allowed && (project_ids.blank? || (issue.project && project_ids.include?(issue.project.id)))
          Redmine::Search.cache_store.write("Issue-#{issue.id}",
            dochash[:sample].force_encoding('UTF-8')) if dochash[:sample]
          return issue
        else
          Rails.logger.error 'User without permissions for process issue in rediss search'
        end
      end
      nil
    end

    def process_attachment(projects, dochash, user)
      attachment = Attachment.where(disk_filename: dochash[:url].split('/').last).first
      if attachment
        Rails.logger.info "Attachment created on #{attachment.created_on}"
        Rails.logger.info "Attachment's project #{attachment.project}"
        Rails.logger.info "Attachment's docattach not nil..:  #{attachment}"
        if attachment.container
          Rails.logger.info 'Adding attachment'
          project = attachment.project
          container_type = attachment[:container_type]
          container_permission = ContainerTypeHelper.to_permission(container_type)
          can_view_container = user.allowed_to?(container_permission, project)

          if container_type == 'Issue'
            issue = Issue.find_by(id: attachment[:container_id])
            allowed = can_view_container && issue && issue.visible?
          else
            allowed = can_view_container
          end

          projects = [] << projects if projects.is_a?(Project)
          project_ids = projects.collect(&:id) if projects

          if allowed && (project_ids.blank? || (attachment.project && project_ids.include?(attachment.project.id)))
            Redmine::Search.cache_store.write("Attachment-#{attachment.id}",
              dochash[:sample].force_encoding('UTF-8')) if dochash[:sample]
            return attachment
          else
            Rails.logger.error 'User without permissions for process attachment in rediss search'
          end
        end
      end
      nil
    end

    def process_repo_file(projects, dochash, user, id)
      Rails.logger.info "Repository file: #{dochash[:url]}"
      Rails.logger.info "Repository date: #{dochash[:date]}"
      Rails.logger.info "Repository sample field: #{dochash[:sample]}"
      repository_attachment = nil
      if dochash[:url] =~ /^#{Redmine::Utils::relative_url_root}\/projects\/(.+)\/repository\/(?:revisions\/(.*)\/|([a-zA-Z_0-9]*)\/)?(?:revisions\/(.*))?\/?entry\/(?:(?:branches|tags)\/(.+?)\/)?(.+?)(?:\?rev=(.*))?$/
        repo_project_identifier = $1
        Rails.logger.info "Project identifier: #{repo_project_identifier}"
        repo_identifier = $3
        Rails.logger.info "Repository identifier: #{repo_identifier}"
        repo_filename = $6
        Rails.logger.info "Repository file: #{repo_filename}"
        repo_revision = (!$2.nil? ? $2 : '') + (!$4.nil? ? $4 : '') + (!$5.nil? ? $5 : '') +(!$7.nil? ? $7 : '')
        Rails.logger.info "Repository revision: #{repo_revision}"
        project = Project.where(identifier: repo_project_identifier).first
        if project
          if repo_identifier != ''
            repository = Repository.where(project_id: project.id, identifier: repo_identifier).first if project
          else
            repository = Repository.where(project_id: project.id).first if project
          end
          if repository
            Rails.logger.info "Repository found #{repository.identifier}"
            projects = [] << projects if projects.is_a?(Project)
            project_ids = projects.collect(&:id) if projects
            allowed = user.allowed_to?(:browse_repository, repository.project)

            if allowed
              if project_ids.blank? || (project_ids.include?(project.id))
                repository_attachment = Repofile.new
                repository_attachment.filename = repo_filename
                begin
                  repository_attachment.created_on = dochash[:date].to_datetime
                rescue => e
                  Rails.logger.error e.message
                  repository_attachment.created_on = Time.at(0)
                end
                repository_attachment.project_id = project.id
                if dochash[:sample]
                  if dochash[:sample].encoding.to_s != 'UTF-8'
                    repository_attachment.description = dochash[:sample].force_encoding('UTF-8')
                  else
                    repository_attachment.description = dochash[:sample]
                  end
                end
                repository_attachment.repository_id = repository.id
                repository_attachment.id = id
                repository_attachment.url = dochash[:url]
                repository_attachment.revision = repo_revision
                h = { filename: repository_attachment.filename, created_on: repository_attachment.created_on.to_s,
                      project_id: repository_attachment.project_id, description: repository_attachment.description,
                      repository_id: repository_attachment.repository_id, url: repository_attachment.url,
                      revision: repository_attachment.revision }
                Redmine::Search.cache_store.write "Repofile-#{repository_attachment.id}", h.to_s
              else
                Rails.logger.error 'No projects to search in'
              end
            else
              Rails.logger.error 'User without :browse_repository permissions'
            end
          else
            Rails.logger.error "Repository not found"
          end
        else
          Rails.logger.error "Project #{repo_project_identifier} not found"
        end
      else
        Rails.logger.error 'Wrong format of the URL'
      end
      repository_attachment
    end

    def get_database_path(rediss_file)
      if rediss_file == 'Repofile'
        File.join Setting.plugin_redmine_rediss['index_database'].rstrip, 'repodb'
      else
        File.join Setting.plugin_redmine_rediss['index_database'].rstrip,
          Setting.plugin_redmine_rediss['stemming_lang'].rstrip
      end
    end

  end

end
