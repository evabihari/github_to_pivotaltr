#!/usr/bin/env ruby

# Author:       Russ Brooks, TelVue Corporation (www.telvue.com)
# Description:  Migrates GitHub Issues to Pivotal Tracker.
# Dependencies: Ruby 1.9.2+
#               GitHub API gem: https://github.com/peter-murach/github
#               Pivtal Tracker gem: https://github.com/jsmestad/pivotal-tracker
#   1. Change the constants below accordingly for your project.
#   2. Change the options in list_repo() method for your GitHub project.
#   3. Change the options in stories.create() method accordingly.
#   4. Change the options in notes.create() method accordingly.
#   5. gem install github_api
#   6. gem install pivotal-tracker
#   7. Save this code to a .rb file (gh_to_pt.rb), and chmod it executable [775].
#   8. Run this file: ./gh_to_pt.rb
#
# Dry-run it first by commenting the create() methods below.
#
# TODO: Exception handling. Pivotal create operations just silently fail right now.
#       You have to just observe your Pivotal project immeidately afterwards.

GITHUB_USER = XXXX
GITHUB_REPO = XXXY
GITHUB_LOGIN = YYYY
GITHUB_PASSWORD = YYYZ
PIVOTAL_TOKEN = ZZZZ
PIVOTAL_PROJECT_ID = NNNN

require 'rubygems'
require 'github_api'
require 'pivotal-tracker'
require 'tracker_api'
require 'uri'
require 'net/http'
require 'net/https'

github = Github.new user: GITHUB_USER, repo: GITHUB_REPO, login: GITHUB_LOGIN, password: GITHUB_PASSWORD
issues = github.issues.list_repo(GITHUB_USER, GITHUB_REPO,
  # milestone: 8, # Verison 1.1 is 8. Icebox is 6.
  state: 'open',
  per_page: 100, # 100 is max. 
  # labels: 'Bug', # 'Story', 'Request', 'Bug', 'High', 'Critical'
  sort: 'created', # 'created', 'updated', 'comments'
  direction: 'asc' # 'asc', 'desc'. 'Ascending' because we want newest ones prioritized first in Pivotal.
  # assignee: '*',
  # mentioned: 'octocat',
)

PivotalTracker::Client.token = PIVOTAL_TOKEN
proj = PivotalTracker::Project.find(PIVOTAL_PROJECT_ID)

i = 0
pulls = 0
issues.each_page do |page|
   page.each do |issue|
     p issue.id

     # do not create stories from pull requests 
     if issue["pull_request"]
       pulls += 1
       puts '*************************************************'
       puts ' pull request found, id = ' +  issue.number.to_s     

     else

       story_label = nil

       bug_in_labels = false
    
       for label in issue.labels
         if label.name == 'bug'
           bug_in_labels = true
         end
         if story_label then
           story_label = story_label + ', ' + label.name
         else
           story_label = label.name
         end
       end

       if bug_in_labels then
         this_story_type = 'bug'
       else
         this_story_type = 'feature'
       end


       # try to find a story with the same title
       new_story = true
       story_list = proj.stories.all(:story_type => [this_story_type])
       story_list.each do |c_story|
      
        if c_story.name == issue.title then
          puts '*************************************************'
          puts ' Already stored story with title: '+issue.title
          puts ' Issue number: '+issue.number.to_s
          puts '*************************************************'
          puts '*************************************************'
          puts '*************************************************'
          new_story = false
        end
       end

       if new_story then       
         puts '*************************************************'
         puts '*** MIGRATING GITHUB ISSUE to PIVOTAL TRACKER ***'
         puts 'Owner:       ' + issue.user.login
         puts 'Assigned to: ' + issue.assignee.login if issue.assignee
         puts 'Date:        ' + issue.created_at
         puts 'Story:       ' + issue.title
         puts 'Type:        ' + this_story_type
         puts 'Labels:      ' + story_label if story_label
         puts '*************************************************'
         puts issue.body

         puts 'Story no:    ' + i.to_s

         ## Create story in Pivotal Tracker

         #    Pivotal Tracker users does not exist yet, can not be mapped    
         #    if (issue.assignee and issue.assignee.login) then 
         #      owned_by_value = issue.assignee.login
         #    else
         #       owned_by_value = nil
         #    end
         #    if (issue.user and issue.user.login) then
         #      requester = issue.user.login
         #    else
         #      requester = nil
         #    end
         story = proj.stories.create(
                                     name: issue.title,
                                     description: issue.body,
                                     created_at: issue.created_at,
                                     labels: story_label,
                                     #    owned_by: owned_by_value,
                                     #    requested_by: requester,
                                     #    story_type: 'feature' # 'bug', 'feature', 'chore', 'release'.
                                     #                Omitting makes it a feature.
                                     story_type: this_story_type
                                     # current_state: 'unstarted'
                                     #        'unstarted', 'started', 'accepted', 'delivered', 'finished', 'unscheduled'.
                                     # Omitting puts it in the Icebox.
                                     # 'unstarted' puts it in 'Current' if Commit Mode is on;
                                     #                        'Backlog' if Auto Mode is on.
                                     )

         # create a note: "Migrated from Github <REPO> <ISSUE>
         body = 'Migrated from https://github.com/'+ GITHUB_USER + "/" + GITHUB_REPO + '/issues/' + issue.number.to_s
         story.notes.create(
                            text: body.gsub(/\r\n\r\n/, "\n\n"),
                            author: issue.user.login,
                            # noted_at: issue.created_at
                            )
         
         comments = github.issues.comments.all GITHUB_USER, GITHUB_REPO, issue.number
         comments.each do |comment|
           puts '--------------'
           puts 'ADDING COMMENT'
           puts 'From: ' + comment.user.login
           puts 'Date: ' + comment.created_at
           puts ''
           puts comment.body

           story.notes.create(
                              text: comment.body.gsub(/\r\n\r\n/, "\n\n"),
                              author: comment.user.login,
                              noted_at: comment.created_at
                              )
         end
         i = i + 1
       end
     end
  end
end

closed=0
story_list = proj.stories.all()
story_list.each do |c_story|

  firstNote = c_story.notes.all.first()
  issueNo = firstNote.text[/\d+/]
  issue = github.issues.find(GITHUB_USER, GITHUB_REPO, issueNo)
  # Careful when getting a single issue. The signature of the objects
  # returned is different than when iterating issues.list_repo().
  # IOW, some stuff below breaks.
  if issue.state == 'closed' then
    # if the points to the story are not allocated yet it can not have delivered state
    # for the time being use point 1 for these cases
    if (c_story.story_type != 'bug') and ((c_story.estimate>3) or (c_story.estimate<0)) then
      c_story.estimate = 1
    end
    c_story.update(:current_state => 'accepted')
    puts '*************************************************'
    puts ' Issue closed, number is: '+issue.number.to_s
    puts '*************************************************'
    puts '*************************************************'
    puts '*************************************************'
    closed = closed + 1
  end
end

PivotalTracker::Client.token = PIVOTAL_TOKEN
proj = PivotalTracker::Project.find(PIVOTAL_PROJECT_ID)

client = TrackerApi::Client.new(token:PIVOTAL_TOKEN)
project = client.project(PIVOTAL_PROJECT_ID)

 # go through the MileStone list and Create Epics with these names
 # problem: only GET is supported by the tracker_api
no_of_mss = 0
       milestones = github.issues.milestones.all GITHUB_USER, GITHUB_REPO
       milestones.each do |milestone|
        title = milestone.title
        description = milestone.description
        due_on = milestone.due_on
        epics_list = project.epics


#  curl -X POST -H "X-TrackerToken: $TOKEN" -H "Content-Type: application/json" -d '
#  {"description":"Install tractor beam systems in all landing bays. Beam systems should report to central monitoring.","label":{"name":"tractor-beams"},
#   "name":"Tractor Beams"}' "https://www.pivotaltracker.com/services/v5/projects/$PROJECT_ID/epics"

        new_epic = TrackerApi::Resources::Epic::new(
                            # id: 
                            # created_at: 
                            description: milestone.description,
                            # kind:epic ,
                            # label: # TrackerApi::Resources::Label
                            name: milestone.title,
                            project_id: PIVOTAL_PROJECT_ID
                            )
        project.epics = project.epics << new_epic

        uri = URI.parse('https://www.pivotaltracker.com/services/v5/projects/'+ PIVOTAL_PROJECT_ID+'/epics')
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
         request = Net::HTTP::Post.new(uri.path)
         request.add_field('X-TrackerToken', PIVOTAL_TOKEN)


        request.set_form_data({'name'=> milestone.title, 'description' => milestone.description,
                                'project_id' => PIVOTAL_PROJECT_ID})

        puts '----- REQUEST ---------'
        puts 'NAME=' + milestone.title
        puts 'DESCRIPTION=' + milestone.description
        
  
        response = https.request(request)

        puts ' ---------RESPONSE----------'
        puts uri
        puts response.code
        puts response.message
       no_of_mss = no_of_mss + 1
      end


puts '=============='
puts 'TOTAL MIGRATED: ' + i.to_s
puts '=============='
puts 'NUMBER OF PRs : ' + pulls.to_s
puts '=============='
puts 'NUMBER OF CLOSED issues : ' + closed.to_s
puts '=============='
puts 'NUMBER OF EPICS  : ' + no_of_mss.to_s
puts '=============='
