#!/usr/bin/env ruby

# Author:       Eva Bihari based on teh work from Russ Brooks, TelVue Corporation (www.telvue.com)
# Description:  Migrates GitHub Issues to Pivotal Tracker.
# Dependencies: Ruby 1.9.2+
#               GitHub API gem: https://github.com/peter-murach/github
#               https://github.com/dashofcode/tracker_api v1.5.0 using Pivotal Tracker v5 API
# 
#   1. gem install github_api
#   2. gem install tracker_api
#   3. Modify constanst according to your github and PivotalTracker credentials
#   4. Run this file: ./to_wombat.rb
#
# Dry-run it first by commenting the create() methods below.1

#
# TODO: Exception handling. No error detection, sometimes script is failing with errors, ex. FARADAY_HTTP connection problems
#
# Logging pivotaltracker Rest calls: set the following Environment variable
# export RESTCLIENT_LOG="/Users/evabihari/external/export_repo_issues_to_csv/gh_to_pt/log.txt""Path/file_name"

GITHUB_USER = 'esl'
GITHUB_REPO = 'wombat'
# GITHUB_USER = 'evabihari'

# GITHUB_REPO = 'test_repo'
GITHUB_LOGIN = 'evabihari'
GITHUB_PASSWORD = 'MachuPichu1'
PIVOTAL_TOKEN = 'c9ece76da0fde1b7c2fc48d3d4ebc47b'

# PIVOTAL_PROJECT_ID = '1162936' trial project
PIVOTAL_PROJECT_ID = '1178396'

require 'rubygems'
require 'tracker_api'
require 'github_api'
require 'uri'
require 'net/http'
require 'net/https'
require 'logger'

$logger = Logger.new(STDOUT)
$logger.level = Logger::WARN

$github = Github.new user: GITHUB_USER, repo: GITHUB_REPO, login: GITHUB_LOGIN, password: GITHUB_PASSWORD
$issues = $github.issues.list(user: GITHUB_USER, repo: GITHUB_REPO,
  # milestone: 8, # Verison 1.1 is 8. Icebox is 6.
  state: 'open',
  per_page: 100, # 100 is max. 
  # labels: 'Bug', # 'Story', 'Request', 'Bug', 'High', 'Critical'
  sort: 'created', # 'created', 'updated', 'comments'
  direction: 'asc' # 'asc', 'desc'. 'Ascending' because we want newest ones prioritized first in Pivotal.
  # assignee: '*',
  # mentioned: 'octocat',
)

client = TrackerApi::Client.new(token: PIVOTAL_TOKEN)
project = client.project(PIVOTAL_PROJECT_ID)

$closed=0

def labelString(st, label)
  if st then
    st = st + ', ' + label
  else
    st = label
  end
end

def add_labels(labels, story)
  puts 'add_labels, story id:'+ story.id.to_s
  labels.each do |lable|
    story.add_label(lable.name)
  end
  story.save
end

def mapUsers (user)
 case user
 when 'evabihari'
   #  'Eva'
   1407124
when 'dszoboszlay'
  # 'Daniel Szoboszlay'
  1488574
when 'viktoriafordos'
  # 'Viktoria Fordos'
  1489638
 else
     nil
 end
end

def makelink(url)
  '<a href="' + url + '">' + url + '</a>'
end

def handle_closed_issue(closed_issue,pivotal_stories)
  title=closed_issue.title
  $logger.warn("------handle_closed_issue, title: #{title}--------")
  pivotal_story= pivotal_stories.find{ |story| story.name == title}
  if pivotal_story == nil
    #closed github issue was not added to pivotal - don't add it now
  else
    #state of the pivotal story should be changed to closed
    # if the points to the story are not allocated yet it can not have delivered state
    # for the time being use point 1 for these cases
    if (pivotal_story.story_type == 'bug') then
      pivotal_story.estimate = nil
    elsif (pivotal_story.estimate == nil) then
      pivotal_story.estimate = 1
    elsif ((pivotal_story.estimate > 3) or (pivotal_story.estimate < 0)) then
      pivotal_story.estimate = 1
    end
    if (pivotal_story.current_state!='accepted' and pivotal_story.current_state!='finished')
      pivotal_story.current_state = 'accepted'  #accepted state means it is done -> will be moved to the Done folder after the iteration ended
      puts "pivotal_story.name: "+pivotal_story.name
      puts "github issue no: "+closed_issue.number.to_s
      puts "pivotal story no: "+pivotal_story.id.to_s
      puts "estimate: "+pivotal_story.estimate.to_s
      $logger.warn("pivotal story no:#{pivotal_story.id.to_s}")
      $logger.warn("pivotal story estimate:#{pivotal_story.estimate.to_s}")

      pivotal_story.save
    end
    puts '*************************************************'
    puts ' Issue closed, number is: '+closed_issue.number.to_s
    puts '*************************************************'
    puts '*************************************************'
    puts '*************************************************'
    $closed = $closed + 1
  end
end

def handleComments (issue, story)
  # check whether additional comments were added
  puts "handeComments, story_name = " + story.name + "issue no: " + issue.number.to_s
    
  comments = $github.issues.comments.all user: GITHUB_USER, repo: GITHUB_REPO, number: issue.number
  story_comments = story.comments
  if story_comments
           st_comments_number = story_comments.size
  else
           st_comments_number = 0
  end
  puts "check for additional comments"
  puts "Story id = " + story.id.to_s
  puts "github id = " + issue.number.to_s
  puts "number of github comments: " + comments.length.to_s
  puts "Number of story notes: " + st_comments_number.to_s

  if (st_comments_number == 0)
         # create a note: "Migrated from Github <REPO> <ISSUE>
    body = 'Migrated from https://github.com/'+ GITHUB_USER + "/" + GITHUB_REPO + '/issues/' + issue.number.to_s
             new_comment=story.create_comment(text: body.gsub(/\r\n\r\n/, "\n\n"))
  end  
  if (comments.length >= st_comments_number) 
       j=1
       comments.each do |comment|
            if j < story_comments.length
              j = j+1
            else
              puts '--------------'
              puts 'ADDING COMMENT'
              puts 'From: ' + comment.user.login
              puts 'Date: ' + comment.created_at
              puts ''
              puts comment.body
              story.create_comment(
                              text: "created by : " + comment.user.login + " at " + comment.created_at + "\n" + comment.body.gsub(/\r\n\r\n/, "\n\n"),
                              # author: mapUsers(comment.user.login),
                              # noted_at: DateTime.parse(comment.created_at)
                              )
              j = j+1
            end #if
       end  #each
  end #if
end #handleComments


#main()

i = 0
pulls = 0
issues =  $github.issues.list(user: GITHUB_USER, repo: GITHUB_REPO,
  state: 'open',
  per_page: 100, # 100 is max. 
  # sort: 'created', # 'created', 'updated', 'comments'
  direction: 'asc' # 'asc', 'desc'. 'Ascending' because we want newest ones prioritized first in Pivotal.
                             )
init_story_list=project.stories()
issues.each_page do |page|
   page.each do |issue|
     p =issue.id
     title =issue.title
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
         story_label = labelString(story_label, label.name)
       end
       if bug_in_labels then
         this_story_type = 'bug'
       else
         this_story_type = 'feature'
       end
       if issue.milestone and issue.milestone.title then
        # milestone needs to be handled -> 1st just try to add it's as a label
           story_label = labelString(story_label, issue.milestone.title)
       end

       # try to find a story with the same title
       new_story = true
       a_story=init_story_list.find{|story| story.name == title}
       if a_story != nil then
          puts '*************************************************'
          puts ' Already stored story with title: '+issue.title
          puts ' Issue number: '+issue.number.to_s
          puts '*************************************************'
          puts '*************************************************'
          puts '*************************************************'
          new_story = false
          handleComments(issue, a_story)
        end
       end

       if new_story then       
         puts '*************************************************'
         puts '*** MIGRATING GITHUB ISSUE to PIVOTAL TRACKER ***'
         puts 'GitHub Issue number: ' + issue.number.to_s
         puts 'Owner:       ' + issue.user.login
         puts 'Assigned to: ' + issue.assignee.login if issue.assignee
         puts 'Date:        ' + issue.created_at
         puts 'Story:       ' + issue.title
         puts 'Type:        ' + this_story_type
         puts 'Labels:      ' + story_label if story_label
         puts '*************************************************'
         puts issue.body.gsub(/\r\n\r\n/, "\n\n")
         puts 'Story no:    ' + i.to_s
         ## Create story in Pivotal Tracker
         #  Pivotal Tracker users does not exist yet, can not be mapped    
         if (issue.assignee and issue.assignee.login) then 
            owned_by_value = issue.assignee.login
         else
            owned_by_value = nil
         end
         if (issue.user and issue.user.login) then
            requester = issue.user.login
         else
            requester = nil
         end
         owned_by_pvt = mapUsers(owned_by_value)
         requester_pvt= mapUsers(requester)
         # links needs to be handled within the string before including it to a HTTP post request
         # to bo done: check that URL is present in the text or not
         body = issue.body
         story = project.create_story(name: issue.title)         #CGI.escape introduced '+' characters!
         story.attributes= {description: issue.body.gsub(/\r\n\r\n/, "\n\n"),
                            created_at: issue.created_at,
                            story_type: this_story_type
                                       # current_state: 'unstarted'
                                       # 'unstarted', 'started', 'accepted', 'delivered', 'finished', 'unscheduled'.
                                       # Omitting puts it in the Icebox.
                                       # 'unstarted' puts it in 'Current' if Commit Mode is on;
                                       # 'Backlog' if Auto Mode is on.
                           }
         story.description= issue.body.gsub(/\r\n\r\n/, "\n\n")
         add_labels(issue.labels, story)
         if owned_by_pvt
           story.attributes={owned_by_id: owned_by_pvt}
         end
         if requester_pvt
           story.attributes={requested_by_id: requester_pvt}
         end
         story.save
         # create a note: "Migrated from Github <REPO> <ISSUE>
         body = 'Migrated from https://github.com/'+ GITHUB_USER + "/" + GITHUB_REPO + '/issues/' + issue.number.to_s
         story.create_comment(
                             text: body.gsub(/\r\n\r\n/, "\n\n")
 ##                            # author: issue.user.login,
 ##                            # noted_at: issue.created_at
                             )
         
         comments = $github.issues.comments.all user: GITHUB_USER, repo: GITHUB_REPO, number: issue.number
         comments.each do |comment|
           puts '--------------'
           puts 'ADDING COMMENT'
           puts 'From: ' + comment.user.login
           puts 'Date: ' + comment.created_at
           puts ''
           puts comment.body

           story.create_comment(
                              text: "created by : " + comment.user.login + " at " + comment.created_at + "\n" + comment.body.gsub(/\r\n\r\n/, "\n\n"),
 ##                              # author: mapUsers(comment.user.login),
 ##                              # noted_at: DateTime.parse(comment.created_at)
                               )
         end
         i = i + 1
       end
     end
  end

$logger.warn("--------------")
$logger.warn("---end of firts round----")
$logger.warn("---now remove closed items-----------")
        
all_pivotal_story=project.stories()
closed_github_issues=Array.new 
## accept issues in PivotalTracker which were closed in Github
closed_issues =  $github.issues.list(user: GITHUB_USER, repo: GITHUB_REPO,
  state: 'closed',
  per_page: 100, # 100 is max. 
  # sort: 'created', # 'created', 'updated', 'comments'
  direction: 'asc' # 'asc', 'desc'. 'Ascending' because we want newest ones prioritized first in Pivotal.
  )
$closed=0
## collect all closed github issue into an array
closed_issues.each_page do |page|
  page.each do |issue|
    if not(issue["pull_request"])
      closed_github_issues.push(issue)
    end
  end
end
puts '----number of pivotal stories----' + all_pivotal_story.size.to_s
puts '----number of closed github issues----' + closed_github_issues.size.to_s
closed_github_issues.each {|github_issue |
  if github_issue!=nil
    handle_closed_issue(github_issue,all_pivotal_story)
  end
} 
puts '=================================='
puts 'TOTAL MIGRATED (NEW ISSUES): ' + i.to_s
puts '=================================='
puts 'NUMBER OF OPEN PRs : ' + pulls.to_s
puts '=================================='
puts 'NUMBER OF CLOSED issues : ' + $closed.to_s
puts '=================================='

