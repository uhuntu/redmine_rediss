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
  module SearchHelper
    
    def link_to_container(attachment)
      link = ''
      case attachment.container_type        
        when 'Message'
          link = link_to("#{l(:label_message)}: #{attachment.container.subject}".truncate(255),
            board_message_path(attachment.container.board, attachment.container))
        when 'WikiPage'
          link = link_to("#{l(:label_wiki)}: #{attachment.container.title}".truncate(255),
            wiki_page_path(attachment.container))
        when 'Issue'
          link = link_to("#{l(:label_issue)}: #{attachment.container.subject}".truncate(255),
            issue_path(attachment.container))        
        when 'Project'
          link = link_to("#{l(:label_file_plural)}",
            project_files_path(attachment.container))
      end
      link + ' / '
    end  
    
  end
end