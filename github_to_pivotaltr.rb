#!/usr/bin/env ruby

# Author:       Eva Bihari (Erlang Solutions Ltd)
# Description:  Migrates GitHub Issues to Pivotal Tracker.
# Dependencies: Ruby 1.9.2+
#               GitHub API gem: https://github.com/peter-murach/github (0.7.0)
#               Pivtal Tracker gem: https://github.com/jsmestad/pivotal-tracker (0.5.12)
#   1. Change the constants below accordingly for your project.
#   2. Change the options in list_repo() method for your GitHub project.
#   3. Change the options in stories.create() method accordingly.
#   4. Change the options in notes.create() method accordingly.
#   5. gem install github_api
#   6. gem install pivotal-tracker
#   7. Save this code to a .rb file (github_to_pivotaltr.rb), and chmod it executable [775].
#   8. Run this file: ./github_to_pivotaltr.rb
#
# Dry-run it first by commenting the create() methods below.
#
# All open github issues will be converted to stories and put into icebox
#      labels used in github will be assigned also to the stories
#      github comments are also added to the stories

# TODO: Exceoption handling. Pivotal create operations just silently fail right now.
#       You have to just observe your Pivotal project immeidately afterwards.

GITHUB_USER = 'SOURCE_XXX'
GITHUB_REPO = 'SOURCE_YYY'
GITHUB_LOGIN = 'LOGIN_XXX'
GITHUB_PASSWORD = 'LOGIN_PWD'
PIVOTAL_TOKEN = 'PIVOTAL_TOKEN'
PIVOTAL_PROJECT_ID = 'TARGET_PROJECT_ID'

require 'rubygems'
require 'github_api'
require 'pivotal-tracker'

github = Github.new user: GITHUB_USER, repo: GITHUB_REPO, login: GITHUB_LOGIN, password: GITHUB_PASSWORD
issues = github.issues.list_repo(GITHUB_USER, GITHUB_REPO,
  # milestone: none
  state: 'open',
  per_page: 100, # 100 is max. 
  # labels: 'Bug', # 'Story', 'Request', 'Bug', 'High', 'Critical'
  sort: 'created', # 'created', 'updated', 'comments'
  direction: 'asc' # 'asc', 'desc'. 'Ascending' because we want newest ones prioritized first in Pivotal.
  # assignee: '*',
  # mentioned: 'octocat',
)

# Get a single issue:
#issue = github.issues.find(GITHUB_USER, GITHUB_REPO, 301)
# Careful when getting a single issue. The signature of the objects
# returned is different than when iterating issues.list_repo().
# IOW, some stuff below breaks.

PivotalTracker::Client.token = PIVOTAL_TOKEN
proj = PivotalTracker::Project.find(PIVOTAL_PROJECT_ID)

i = 0
issues.each_page do |page|
   page.each do |issue|
     p issue.id

    story_label = nil
    for label in issue.labels
      puts '--------------'
      puts 'ADDING LABEL'
      puts label.name
      if story_label then
        story_label = story_label + ', ' + label.name
      else
        story_label = label.name
      end
    end

    puts '*************************************************'
    puts '*** MIGRATING GITHUB ISSUE to PIVOTAL TRACKER ***'
    puts 'Owner:       ' + issue.user.login
    puts 'Assigned to: ' + issue.assignee.login if issue.assignee
    puts 'Date:        ' + issue.created_at
    puts 'Story:       ' + issue.title
    puts 'Labels:      ' + story_label if story_label
    puts '*************************************************'
    puts issue.body

    puts 'Story no:    ' + i.to_s

    ## Create story in Pivotal Tracker

#    Pivotal Tracker users does not exist yet, can not be mapped
#    code can be modified later if users are created in PivotalTracker as well
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
    story_type: 'feature' # 'bug', 'feature', 'chore', 'release'. Omitting makes it a feature.
    # current_state: 'unstarted' # 'unstarted', 'started', 'accepted', 'delivered', 'finished', 'unscheduled'.
    # Omitting puts it in the Icebox.
    # 'unstarted' puts it in 'Current' if Commit Mode is on; 'Backlog' if Auto Mode is on.
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

puts '=============='
puts 'TOTAL MIGRATED: ' + i.to_s
puts '=============='
