#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(__FILE__), '..', '..','lib')

require 'couchrest'

couch = CouchRest.new("http://127.0.0.1:5984")
db = couch.database('word-count-example')

# this script assumes that the word_count_insert.rb script
# has been run successfully
unless db
  puts <<-eos
    To create the 'word-count-example' database, please run:
      ruby insert.rb
    Then come back and run this script again!
    Go on, we'll be patient...
  eos
  exit -1
end

begin
  db.get("_design/word_count")
rescue RestClient::ResourceNotFound
  puts "Creating the 'word_count' view..."
  # create the view, if it hasn't been created already

  db.save_doc({
    "_id" => "_design/word_count",
    :views => {
      :words => {
        :map => 'function(doc){
          var words = doc.text.split(/[^a-z]+/i);
          words.forEach(function(word){
            if (word.length > 0) emit([word,doc.title],1);
          });
        }',
        :reduce => 'function(key,combine){
          return sum(combine);
        }'
      }
    }
  })
end

# check for active tasks, just be sure that we're looking at
# the most up-to-date data in the view
begin
  puts "Checking the status of the view..."
  results = db.view('word_count/words', :stale => 'ok') # prime the view
rescue RestClient::RequestTimeout => e
  # nothing
end

# still indexing the view?
if task = couch.active_tasks.select{|t| t['task'] == 'word-count-example _design/word_count'}.first
  puts <<-eos
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
puts "  (This means: " + (response['rows'].first)['value'].inspect + " total words the database)"

puts <<-eos

We can narrow the query down to just one word, across all documents.
Here is the count for 'flight' in all of the books:

eos

word = 'flight'
params = {
  :startkey => [word], 
  :endkey => [word,{}]
}

puts "> Query: word_count/words, Params: " + params.inspect
response = db.view('word_count/words', params)
puts "> Response: " + response.inspect
puts "  (This means: " + (response['rows'].first)['value'].inspect + " instances of the word '#{word}')"

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
puts "  (This means: " + (response['rows'].first)['value'].inspect + " instances of the word '#{word}' in the book '#{title}')"

puts <<-eos

Aside from the CouchRest interface, you can use your browser for these queries.
For instance, the last query can be obtained with this URL:

http://localhost:5984/word-count-example/_design/word_count/_view/words?key=["#{word}","#{title}"]

eos

puts "Try dropping that in your browser..."

puts <<-eos

Finally, let's try something a bit more interactive...  Enter a word and we'll count
how many times that word appears in all of the documents.  Case matters.

eos

instances = -1

while instances < 1
  if instances == 0
    puts "Whoops, looks like '#{word}' wasn't in any of the documents.  Have another shot, on us!"
    puts ""
  end
  print "Word, please: "
  word = (STDIN.gets || '').strip
  puts ""

  params = {
    :startkey => [word, nil],
    :endkey => [word, {}]
    }

  puts "> Query: word_count/words, Params: " + params.inspect
  response = db.view('word_count/words', params)
  instances = (response['rows'].first || {})['value'] || 0
  puts "> Response: " + response.inspect
  puts ""
end

puts "Fantastic!  We counted " + instances.to_s + " instance#{instances > 1 ? 's' : ''} of the word '#{word}' in the database"
puts ""

puts "For bonus points, see if you can find a word that only appears once in the whole database."
puts ""

