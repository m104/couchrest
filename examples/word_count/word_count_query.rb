#!/usr/bin/env ruby

# ensure that we're loading *this* version of couchrest, wherever we are
$:.unshift File.join(File.dirname(__FILE__), '..', '..','lib')

require 'couchrest'

couch = CouchRest.new("http://127.0.0.1:5984")
db = couch.database('word-count-example')

# this script assumes that the word_count_insert.rb script
# has been run successfully
unless db
  puts "To create the 'word-count-example' database, please run:"
  puts "  ruby word_count_insert.rb"
  puts "Then come back and run this script again!"
  puts "Go on, we'll be patient..."
  exit -1
end

# check for active tasks, just be sure that we're looking at
# the most up-to-date data in the view
results = db.view('word_count/words', :stale => 'ok') # prime the view

puts "Checking the status of the view..."
task = couch.active_tasks.select{|t| t['task'] == 'word-count-example _design/word_count'}.first

if task
  print <<-eos
NOTE: The view is not quite ready, so you can either cancel this script
      and come back later or wait for the documents to be fully indexed.
      You can still query the view with "stale=ok", but you won't get
      up-to-date answers...
eos
end

while task
  # the background view indexer is working away...
  print "\rView status: " + task['status']
  sleep 5
  task = couch.active_tasks.select{|t| t['task'] == 'word-count-example _design/word_count'}.first
  puts "" unless task
end

puts <<-eos

Now that we've parsed all of those books into CouchDB and the view has been
thoroughly indexed, we're ready to put the view to work.  The simplest query
we can run is the total word count for all words in all documents:

eos

puts "> Query: word_count/words"
response = db.view('word_count/words')
puts "> Response: " + response.inspect
puts "This means: " + (response['rows'].first)['value'].inspect + " total words the database"

puts <<-eos

We can also narrow the query down to just one word, across all documents.
Here is the count for 'flight' in all three books:

eos

word = 'flight'
params = {
  :startkey => [word], 
  :endkey => [word,{}]
}

puts "> Query: word_count/words, Params: " + params.inspect
response = db.view('word_count/words', params)
puts "> Response: " + response.inspect
puts "This means: " + (response['rows'].first)['value'].inspect + " instances of the word '#{word}'"

puts <<-eos

We can also count words on a per-title basis.

eos

title = 'da-vinci'
params = {
  :key => [word, title]
  }
  
puts "> Query: word_count/words, Params: " + params.inspect
response = db.view('word_count/words', params)
puts "> Response: " + response.inspect
puts "This means: " + (response['rows'].first)['value'].inspect + " instances of the word '#{word}' in the book '#{title}'"

puts <<-eos

Aside from the CouchRest interface, you can use your browser for these queries.
For instance, the last query can be obtained with this URL:

http://127.0.0.1:5984/word-count-example/_design/word_count/_view/words?key=["#{word}","#{title}"]

eos

puts "Try dropping that in your browser..."

